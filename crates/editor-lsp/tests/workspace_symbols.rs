use editor_lsp::extract_workspace_symbols;
use serde_json::json;

#[test]
fn workspace_symbol_ranges_are_validated_without_fabricating_locations() {
    let valid = json!({"name":"😀target", "kind":12, "containerName":"scope", "location":{
        "uri":"file:///workspace/target.rs", "range":{
            "start":{"line":1,"character":3}, "end":{"line":2,"character":9}
        }
    }});
    let wide = json!({"name":"wide","kind":12,"location":{"uri":"file:///workspace/wide.rs","range":{"start":{"line":2147483648u64,"character":0},"end":{"line":2147483648u64,"character":1}}}});
    let mut invalid = valid.clone();
    invalid["location"]["range"]["end"]["line"] = json!(0);
    let entries = extract_workspace_symbols(&json!([
        {"name":"unresolved", "kind":12, "location":{"uri":"file:///workspace/x.rs"}},
        wide, invalid, valid
    ]))
    .unwrap();
    assert_eq!(entries.len(), 1);
    assert_eq!(entries[0].name, "😀target");
    assert_eq!(entries[0].line, 1);
    assert_eq!(entries[0].character, 3);
    assert_eq!(entries[0].end_line, 2);
    assert_eq!(entries[0].end_character, 9);
    assert_eq!(entries[0].container_name.as_deref(), Some("scope"));
    assert!(extract_workspace_symbols(&json!(null)).unwrap().is_empty());
    assert!(extract_workspace_symbols(&json!({})).is_err());
    assert!(extract_workspace_symbols(&json!(vec![json!({}); 2001])).is_err());
}
