use serde::Serialize;
use serde_json::{json, Value};

use super::{normalize_uri, LspPendingRequest, LspServer};

const MAX_ITEM_BYTES: usize = 64 * 1024;
const MAX_RESPONSE_BYTES: usize = 4 * 1024 * 1024;
const MAX_ITEMS: usize = 2000;
const MAX_CALL_SITES: usize = 4000;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum HierarchyKind {
    Call,
    Type,
}

impl HierarchyKind {
    fn capability(self) -> &'static str {
        match self {
            Self::Call => "/capabilities/callHierarchyProvider",
            Self::Type => "/capabilities/typeHierarchyProvider",
        }
    }

    fn prepare_method(self) -> &'static str {
        match self {
            Self::Call => "textDocument/prepareCallHierarchy",
            Self::Type => "textDocument/prepareTypeHierarchy",
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum HierarchyDirection {
    Incoming,
    Outgoing,
    Supertypes,
    Subtypes,
}

impl HierarchyDirection {
    fn kind(self) -> HierarchyKind {
        match self {
            Self::Incoming | Self::Outgoing => HierarchyKind::Call,
            Self::Supertypes | Self::Subtypes => HierarchyKind::Type,
        }
    }

    fn method(self) -> &'static str {
        match self {
            Self::Incoming => "callHierarchy/incomingCalls",
            Self::Outgoing => "callHierarchy/outgoingCalls",
            Self::Supertypes => "typeHierarchy/supertypes",
            Self::Subtypes => "typeHierarchy/subtypes",
        }
    }

    fn edge_key(self) -> Option<&'static str> {
        match self {
            Self::Incoming => Some("from"),
            Self::Outgoing => Some("to"),
            Self::Supertypes | Self::Subtypes => None,
        }
    }
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct HierarchyEntry {
    /// The original provider object is passed back when expanding a node.
    pub item: Value,
    /// Incoming ranges belong to the caller and outgoing ranges to the parent.
    pub from_ranges: Vec<HierarchyRange>,
}

impl LspServer {
    pub fn supports_hierarchy(&self, kind: HierarchyKind) -> Result<bool, String> {
        Ok(self
            .shared
            .server_capabilities
            .lock()
            .map_err(|_| "capabilities lock poisoned")?
            .as_ref()
            .and_then(|result| result.pointer(kind.capability()))
            .is_some_and(|provider| provider == true || provider.is_object()))
    }

    fn hierarchy_request(
        &self,
        kind: HierarchyKind,
        method: &'static str,
        params: Value,
    ) -> Result<Option<LspPendingRequest>, String> {
        if !self.supports_hierarchy(kind)? {
            return Ok(None);
        }
        self.send_request(method, params, true).map(Some)
    }

    pub fn prepare_hierarchy_async(
        &self,
        kind: HierarchyKind,
        uri: &str,
        line: u64,
        character: u64,
    ) -> Result<Option<LspPendingRequest>, String> {
        self.hierarchy_request(
            kind,
            kind.prepare_method(),
            json!({
                "textDocument": {"uri": normalize_uri(uri)},
                "position": {"line": line, "character": character},
            }),
        )
    }

    pub fn hierarchy_children_async(
        &self,
        direction: HierarchyDirection,
        item: Value,
    ) -> Result<Option<LspPendingRequest>, String> {
        if hierarchy_item_size(&item).is_none() {
            return Err("invalid or oversized hierarchy item".into());
        }
        self.hierarchy_request(direction.kind(), direction.method(), json!({"item": item}))
    }
}

#[derive(Debug, Serialize, PartialEq, Eq, PartialOrd, Ord, Clone, Copy)]
pub struct HierarchyPosition {
    pub line: u64,
    pub character: u64,
}

#[derive(Debug, Serialize)]
pub struct HierarchyRange {
    pub start: HierarchyPosition,
    pub end: HierarchyPosition,
}

fn position(value: &Value) -> Option<HierarchyPosition> {
    let line = value.get("line")?.as_u64()?;
    let character = value.get("character")?.as_u64()?;
    let maximum = i32::MAX as u64;
    (line <= maximum && character <= maximum).then_some(HierarchyPosition { line, character })
}

fn range(value: &Value) -> Option<HierarchyRange> {
    let start = position(value.get("start")?)?;
    let end = position(value.get("end")?)?;
    (start <= end).then_some(HierarchyRange { start, end })
}

fn hierarchy_item_size(item: &Value) -> Option<usize> {
    let name = item.get("name")?.as_str()?;
    let uri = item.get("uri")?.as_str()?;
    let kind = item.get("kind")?.as_u64()?;
    if name.is_empty()
        || name.len() > 4096
        || uri.is_empty()
        || uri.len() > 8192
        || !(1..=26).contains(&kind)
    {
        return None;
    }
    let extent = range(item.get("range")?)?;
    let selection = range(item.get("selectionRange")?)?;
    if selection.start < extent.start || selection.end > extent.end {
        return None;
    }
    let bytes = serde_json::to_vec(item).ok()?.len();
    (bytes <= MAX_ITEM_BYTES).then_some(bytes)
}

pub fn extract_hierarchy_entries(
    response: Value,
    direction: Option<HierarchyDirection>,
) -> Result<Vec<HierarchyEntry>, String> {
    let values = match response {
        Value::Null => return Ok(Vec::new()),
        Value::Array(values) => values,
        _ => return Err("hierarchy response must be an array or null".into()),
    };
    if values.len() > MAX_ITEMS {
        return Err(format!("hierarchy response exceeds {MAX_ITEMS} items"));
    }
    let edge_key = direction.and_then(HierarchyDirection::edge_key);
    let mut entries = Vec::with_capacity(values.len());
    let mut item_bytes = 0;
    let mut call_sites = 0;
    for mut value in values {
        let (item, ranges) = if let Some(edge_key) = edge_key {
            let Some(item) = value.get_mut(edge_key).map(Value::take) else {
                continue;
            };
            let Some(Value::Array(ranges)) = value.get_mut("fromRanges").map(Value::take) else {
                continue;
            };
            (item, ranges)
        } else {
            (value, Vec::new())
        };
        let Some(bytes) = hierarchy_item_size(&item) else {
            continue;
        };
        item_bytes += bytes;
        call_sites += ranges.len();
        if item_bytes > MAX_RESPONSE_BYTES || call_sites > MAX_CALL_SITES {
            return Err("hierarchy response exceeds the item or call site size limit".into());
        }
        let from_ranges = ranges.iter().filter_map(range).collect();
        entries.push(HierarchyEntry { item, from_ranges });
    }
    Ok(entries)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn item() -> Value {
        json!({
            "name": "root",
            "kind": 12,
            "detail": "module",
            "uri": "file:///workspace/main.rs",
            "range": {
                "start": {"line": 1, "character": 0},
                "end": {"line": 2, "character": 20},
            },
            "selectionRange": {
                "start": {"line": 1, "character": 15},
                "end": {"line": 1, "character": 19},
            },
            "data": ["opaque", {"uri": "file:///workspace/main.rs", "id": 44}],
        })
    }

    #[test]
    fn hierarchy_preserves_items_and_call_ranges() {
        let item = item();
        let site = json!({
            "start": {"line": 2, "character": 15},
            "end": {"line": 2, "character": 20},
        });
        for (direction, field) in [
            (HierarchyDirection::Incoming, "from"),
            (HierarchyDirection::Outgoing, "to"),
        ] {
            let reply = json!([{(field): item.clone(), "fromRanges": [site.clone()]}]);
            let entries = extract_hierarchy_entries(reply, Some(direction)).unwrap();
            assert_eq!(entries.len(), 1);
            assert_eq!(entries[0].item, item);
            assert_eq!(
                serde_json::to_value(&entries[0].from_ranges).unwrap(),
                json!([site.clone()])
            );
        }
        for direction in [
            None,
            Some(HierarchyDirection::Supertypes),
            Some(HierarchyDirection::Subtypes),
        ] {
            let entries = extract_hierarchy_entries(json!([item.clone()]), direction).unwrap();
            assert_eq!(entries[0].item, item);
            assert!(entries[0].from_ranges.is_empty());
        }
    }

    #[test]
    fn hierarchy_distinguishes_empty_and_invalid_and_limits_size() {
        assert!(extract_hierarchy_entries(Value::Null, None)
            .unwrap()
            .is_empty());
        assert!(extract_hierarchy_entries(json!({}), None).is_err());
        assert!(
            extract_hierarchy_entries(Value::Array(vec![Value::Null; MAX_ITEMS + 1]), None)
                .is_err()
        );
        let mut reversed = item();
        reversed["selectionRange"]["end"]["line"] = json!(0);
        let entries = extract_hierarchy_entries(json!([reversed, item()]), None).unwrap();
        assert_eq!(entries.len(), 1);
        let mut oversized = item();
        oversized["data"] = json!("x".repeat(MAX_ITEM_BYTES));
        assert!(hierarchy_item_size(&oversized).is_none());
    }
}
