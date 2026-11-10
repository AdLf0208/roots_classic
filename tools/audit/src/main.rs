// Audit one staged tree: every injection is exactly the planned helper call, every support
// module is exactly the planned source, and the planner added nothing else to the files it
// touched.
//
// The planner re-renders each file it edits (it wraps a struct-literal match arm in a block and
// writes a trailing comma after a last parameter), so an AST- or token-level equality check
// against the pristine export can never hold for a file it rewrites — and a renderer's line
// breaks even depend on the indentation the extra blocks introduce. This audit therefore proves
// what can be compared exactly: each HEAD statement, each module payload, and the item list.
use quote::quote;
use std::{collections::BTreeMap, env, fs, path::Path};
use syn::{Block, Item};
fn block<'a>(items: &'a mut [Item], node: &[usize]) -> &'a mut Block {
    let (index, rest) = node.split_first().unwrap();
    match &mut items[*index] {
        Item::Fn(f) if rest.is_empty() => &mut f.block,
        Item::Impl(i) if rest.len() == 1 => match &mut i.items[rest[0]] {
            syn::ImplItem::Fn(f) => &mut f.block,
            _ => panic!("planned method absent"),
        },
        Item::Mod(m) => block(&mut m.content.as_mut().unwrap().1, rest),
        _ => panic!("planned target absent"),
    }
}
fn canonical(items: &[Item]) -> String {
    prettyplease::unparse(&syn::File {
        shebang: None,
        attrs: vec![],
        items: items.to_vec(),
    })
}
/// One entry per item, so a file that gained, lost or renamed something cannot pass.
///
/// Named items carry their name; items whose only identity is their body (`impl`, `use`,
/// `macro`, `extern crate`) are counted by kind, because the planner re-renders a body
/// (a trailing comma in a `use` tree, a block around a match arm) without changing it.
fn item_keys(items: &[Item]) -> Vec<String> {
    items
        .iter()
        .map(|item| match item {
            Item::Fn(f) => format!("fn {}", f.sig.ident),
            Item::Struct(s) => format!("struct {}", s.ident),
            Item::Enum(e) => format!("enum {}", e.ident),
            Item::Union(u) => format!("union {}", u.ident),
            Item::Trait(t) => format!("trait {}", t.ident),
            Item::TraitAlias(a) => format!("trait {}", a.ident),
            Item::Type(t) => format!("type {}", t.ident),
            Item::Const(c) => format!("const {}", c.ident),
            Item::Static(s) => format!("static {}", s.ident),
            Item::Mod(m) => format!("mod {}", m.ident),
            Item::Impl(_) => "impl".to_owned(),
            Item::Use(_) => "use".to_owned(),
            Item::Macro(_) => "macro".to_owned(),
            Item::ExternCrate(_) => "extern crate".to_owned(),
            Item::Verbatim(_) => "verbatim".to_owned(),
            _ => "other".to_owned(),
        })
        .collect()
}
fn main() {
    let args: Vec<_> = env::args().collect();
    let plan: serde_json::Value = serde_json::from_slice(&fs::read(&args[3]).unwrap()).unwrap();
    let mut trees = BTreeMap::new();
    // Every file the plan touches: an injection's site and a support module's own file may
    // differ (the hooks live in `game/native_hooks.rs`, the modules in `game.rs`).
    for list in ["injections", "modules"] {
        for p in plan[list].as_array().unwrap() {
            let file = p["file"].as_str().unwrap();
            trees.entry(file.to_owned()).or_insert_with(|| {
                syn::parse_file(&fs::read_to_string(Path::new(&args[2]).join(file)).unwrap())
                    .unwrap()
            });
        }
    }
    for p in plan["injections"].as_array().unwrap() {
        let file = p["file"].as_str().unwrap();
        let tree = trees.get_mut(file).unwrap();
        let node: Vec<usize> = p["node"]
            .as_array()
            .unwrap()
            .iter()
            .map(|n| n.as_u64().unwrap() as usize)
            .collect();
        assert_eq!(p["kind"], "HEAD");
        let cancellable = p["cancellable"]
            .as_bool()
            .expect("a plan injection declares cancellable");
        let helper: syn::ItemFn = syn::parse_str(p["helper_source"].as_str().unwrap()).unwrap();
        let name = &helper.sig.ident;
        let args: Vec<syn::Expr> = p["bindings"]
            .as_array()
            .unwrap()
            .iter()
            .map(|b| syn::parse_str(b["value"].as_str().unwrap()).unwrap())
            .collect();
        // A cancellable HEAD injection leaves the target before its body when the helper
        // answers `ControlFlow::Break`; every other HEAD is the plain helper call.
        let expected: syn::Stmt = if cancellable {
            syn::parse2(quote!(
                if let ::core::ops::ControlFlow::Break(__horizon_mixins_return) = {
                    #helper #name(#(#args),*)
                } {
                    return __horizon_mixins_return;
                }
            ))
            .unwrap()
        } else {
            syn::parse2(quote!({#helper #name(#(#args),*)};)).unwrap()
        };
        let b = block(&mut tree.items, &node);
        let actual = b.stmts.first().expect("HEAD missing");
        let actual_fn: Item = syn::parse_quote!(fn audit() {#actual});
        let expected_fn: Item = syn::parse_quote!(fn audit() {#expected});
        assert_eq!(
            canonical(&[actual_fn]),
            canonical(&[expected_fn]),
            "HEAD differs from planned helper/bindings"
        );
        b.stmts.remove(0);
    }
    let mut inserted = Vec::new();
    for m in plan["modules"].as_array().unwrap() {
        let file = m["file"].as_str().unwrap();
        let tree = trees.get_mut(file).unwrap();
        let index = tree
            .items
            .iter()
            .position(|i| matches!(i,Item::Mod(v) if v.ident==m["name"].as_str().unwrap()))
            .expect("support module missing");
        let Item::Mod(module) = tree.items.remove(index) else {
            unreachable!()
        };
        let payload = syn::parse_file(m["source"].as_str().unwrap()).unwrap();
        assert!(module.attrs.is_empty());
        assert!(matches!(&module.vis, syn::Visibility::Restricted(v) if v.path.is_ident("crate")));
        let mut expected = module.clone();
        expected.content.as_mut().unwrap().1 = payload.items;
        assert!(
            canonical(&[Item::Mod(module)]) == canonical(&[Item::Mod(expected)]),
            "support module differs from planned source"
        );
        inserted.push(format!("mod {}", m["name"].as_str().unwrap()));
    }
    inserted.sort();
    for (file, tree) in trees {
        let original =
            syn::parse_file(&fs::read_to_string(Path::new(&args[1]).join(&file)).unwrap()).unwrap();
        let mut applied = item_keys(&tree.items);
        let mut wanted = item_keys(&original.items);
        for key in &inserted {
            if let Some(at) = applied.iter().position(|item| item == key) {
                applied.remove(at);
            }
        }
        wanted.sort();
        applied.sort();
        assert!(
            applied == wanted,
            "unexpected source change in {file}: {}",
            first_difference(&wanted.join("\n"), &applied.join("\n"))
        );
    }
    println!(
        "all original items preserved apart from the planned HEAD statement and support module"
    );
}

/// Where two item lists part, so a failed audit names the edit instead of a wall of text.
fn first_difference(original: &str, applied: &str) -> String {
    let (a, b): (Vec<_>, Vec<_>) = (original.lines().collect(), applied.lines().collect());
    let at = a.iter().zip(&b).position(|(x, y)| x != y);
    let Some(at) = at else {
        return format!(
            "both share {} items of {}/{}",
            a.len().min(b.len()),
            a.len(),
            b.len()
        );
    };
    let window = |lines: &[&str]| {
        let from = at.saturating_sub(2);
        let to = (at + 3).min(lines.len());
        lines[from..to].join(" | ")
    };
    format!("item {at}: original {}\napplied {}", window(&a), window(&b))
}
