use std::collections::{BTreeSet, HashSet};
use std::hash::{DefaultHasher, Hash, Hasher};
use std::ops::Bound::{Included, Unbounded};

use serde::{Deserialize, Serialize};

use super::{normalize_uri, Diagnostic, DiagnosticCache, DiagnosticCode, LspServer};

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct WorkspaceDiagnosticCandidate {
    pub uri: String,
    pub wrapped: bool,
    pub diagnostic: Diagnostic,
    pub unopened_total: usize,
    pub unopened_before_file: usize,
    pub file_total: usize,
}

type DiagnosticOrder = (u32, (u64, u64), (u64, u64));

fn navigable_diagnostics(
    diagnostics: &[Diagnostic],
) -> impl Iterator<Item = (DiagnosticOrder, &Diagnostic)> {
    let mut seen = HashSet::new();
    diagnostics.iter().filter_map(move |diagnostic| {
        let end = (diagnostic.end_line?, diagnostic.end_character?);
        let start = (diagnostic.line, diagnostic.character);
        if !(1..=3).contains(&diagnostic.severity) || end < start {
            return None;
        }
        let order = (diagnostic.severity, start, end);
        // Match the workbench's marker identity when a provider repeats a row.
        seen.insert((
            order,
            diagnostic.message.as_str(),
            diagnostic.source.as_deref(),
        ))
        .then_some((order, diagnostic))
    })
}

impl LspServer {
    /// Read one diagnostic and counts for navigable markers outside open files.
    /// The cached provider version, including its absence, is returned verbatim.
    pub fn next_unopened_diagnostic(
        &self,
        cursor_uri: Option<&str>,
        open_uris: &[String],
        forward: bool,
    ) -> Option<WorkspaceDiagnosticCandidate> {
        let cursor = cursor_uri.map(normalize_uri);
        let excluded = open_uris
            .iter()
            .map(|uri| normalize_uri(uri))
            .collect::<HashSet<_>>();
        let cache = self.shared.diagnostics.lock().ok()?;
        let cache = &cache.by_uri;
        let is_unopened_file = |uri: &str| uri.starts_with("file://") && !excluded.contains(uri);
        let mut unopened_total = 0;
        let (wrapped, uri, file_total, diagnostic) = cache
            .iter()
            .filter(|(uri, _)| is_unopened_file(uri))
            .filter_map(|(uri, diagnostics)| {
                let mut file_total = 0;
                let (_, diagnostic) = navigable_diagnostics(diagnostics)
                    .inspect(|_| file_total += 1)
                    .min_by(|left, right| {
                        if forward {
                            left.0.cmp(&right.0)
                        } else {
                            right.0.cmp(&left.0)
                        }
                    })?;
                unopened_total += file_total;
                let uri = uri.as_str();
                let wrapped = cursor.as_deref().is_some_and(|cursor| {
                    if forward {
                        uri <= cursor
                    } else {
                        uri >= cursor
                    }
                });
                Some((wrapped, uri, file_total, diagnostic))
            })
            .min_by(|a, b| {
                a.0.cmp(&b.0)
                    .then_with(|| if forward { a.1.cmp(b.1) } else { b.1.cmp(a.1) })
            })?;
        let unopened_before_file = cache
            .iter()
            .filter(|(other, _)| other.as_str() < uri && is_unopened_file(other))
            .map(|(_, diagnostics)| navigable_diagnostics(diagnostics).count())
            .sum();
        Some(WorkspaceDiagnosticCandidate {
            uri: uri.to_owned(),
            wrapped,
            diagnostic: diagnostic.clone(),
            unopened_total,
            unopened_before_file,
            file_total,
        })
    }
}

const MAX_DIAGNOSTIC_PAGE_ROWS: usize = 256;
const DIAGNOSTIC_PAGE_TEXT_BUDGET: usize = 512 * 1024;

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct WorkspaceDiagnosticPageRequest {
    pub open_uris: Vec<String>,
    pub limit: usize,
    pub cursor: Option<WorkspaceDiagnosticCursor>,
    pub known_snapshot: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct WorkspaceDiagnosticCursor {
    pub snapshot: String,
    pub uri: String,
    pub marker_index: usize,
}

#[derive(Debug, Default, Serialize)]
pub struct WorkspaceDiagnosticCounts {
    pub errors: usize,
    pub warnings: usize,
    pub infos: usize,
}

#[derive(Debug, Serialize)]
pub struct WorkspaceDiagnosticEntry {
    pub uri: String,
    pub diagnostic: Diagnostic,
}

#[derive(Debug, Serialize)]
#[serde(
    tag = "status",
    rename_all = "camelCase",
    rename_all_fields = "camelCase"
)]
pub enum WorkspaceDiagnosticPage {
    Page {
        snapshot: String,
        items: Vec<WorkspaceDiagnosticEntry>,
        next_cursor: Option<WorkspaceDiagnosticCursor>,
        #[serde(skip_serializing_if = "Option::is_none")]
        counts: Option<WorkspaceDiagnosticCounts>,
    },
    Unchanged {
        snapshot: String,
    },
    Stale {
        snapshot: String,
    },
}

impl LspServer {
    /// Read unopened diagnostics under one immutable cache revision and URI scope.
    /// The initial page carries workspace counts. Continuations preserve the
    /// provider's original document version and order within each resource.
    pub fn unopened_diagnostics_page(
        &self,
        request: WorkspaceDiagnosticPageRequest,
    ) -> Result<WorkspaceDiagnosticPage, &'static str> {
        self.shared
            .diagnostics
            .lock()
            .map_err(|_| "diagnostic cache unavailable")?
            .read_page(request)
    }
}

impl DiagnosticCache {
    fn read_page(
        &self,
        request: WorkspaceDiagnosticPageRequest,
    ) -> Result<WorkspaceDiagnosticPage, &'static str> {
        if !(1..=MAX_DIAGNOSTIC_PAGE_ROWS).contains(&request.limit) {
            return Err("diagnostic page limit must be between 1 and 256");
        }
        if request.cursor.is_some() && request.known_snapshot.is_some() {
            return Err("use a cursor or a known snapshot");
        }

        let excluded = request
            .open_uris
            .iter()
            .map(|uri| normalize_uri(uri))
            .collect::<BTreeSet<_>>();
        let mut hash = DefaultHasher::new();
        excluded.hash(&mut hash);
        let snapshot = format!("{:016x}-{:016x}", self.revision, hash.finish());
        let is_unopened = |uri: &str| uri.starts_with("file://") && !excluded.contains(uri);
        if request.known_snapshot.as_deref() == Some(snapshot.as_str()) {
            return Ok(WorkspaceDiagnosticPage::Unchanged { snapshot });
        }
        let cursor = request.cursor.as_ref();
        let start = if let Some(cursor) = cursor {
            if cursor.snapshot != snapshot {
                return Ok(WorkspaceDiagnosticPage::Stale { snapshot });
            }
            let found = is_unopened(&cursor.uri)
                && self.by_uri.get(&cursor.uri).is_some_and(|items| {
                    navigable_diagnostics(items)
                        .nth(cursor.marker_index)
                        .is_some()
                });
            if !found {
                return Err("invalid diagnostic page cursor");
            }
            Included(cursor.uri.as_str())
        } else {
            Unbounded
        };

        let counts = cursor.is_none().then(|| {
            let mut severity = [0usize; 3];
            for (uri, diagnostics) in &self.by_uri {
                if !is_unopened(uri) {
                    continue;
                }
                for (_, diagnostic) in navigable_diagnostics(diagnostics) {
                    severity[diagnostic.severity as usize - 1] += 1;
                }
            }
            WorkspaceDiagnosticCounts {
                errors: severity[0],
                warnings: severity[1],
                infos: severity[2],
            }
        });
        let mut items = Vec::new();
        let mut text_bytes = 0usize;
        let mut last_entry = None;
        let mut has_more = false;
        'files: for (uri, diagnostics) in self.by_uri.range::<str, _>((start, Unbounded)) {
            if !is_unopened(uri) {
                continue;
            }
            let skip = cursor
                .filter(|cursor| cursor.uri == *uri)
                .map_or(0, |cursor| cursor.marker_index + 1);
            for (index, (_, diagnostic)) in
                navigable_diagnostics(diagnostics).enumerate().skip(skip)
            {
                let code_bytes = match &diagnostic.code {
                    Some(DiagnosticCode::Text(text)) => text.len(),
                    _ => 0,
                };
                let entry_bytes = uri
                    .len()
                    .saturating_add(diagnostic.message.len())
                    .saturating_add(diagnostic.source.as_deref().map_or(0, str::len))
                    .saturating_add(code_bytes);
                let next_bytes = text_bytes.saturating_add(entry_bytes);
                // Keep a large diagnostic intact and give it its own page.
                if items.len() == request.limit
                    || (!items.is_empty() && next_bytes > DIAGNOSTIC_PAGE_TEXT_BUDGET)
                {
                    has_more = true;
                    break 'files;
                }
                items.push(WorkspaceDiagnosticEntry {
                    uri: uri.clone(),
                    diagnostic: diagnostic.clone(),
                });
                text_bytes = next_bytes;
                last_entry = Some((uri, index));
            }
        }
        let next_cursor =
            last_entry
                .filter(|_| has_more)
                .map(|(uri, marker_index)| WorkspaceDiagnosticCursor {
                    snapshot: snapshot.clone(),
                    uri: uri.clone(),
                    marker_index,
                });
        Ok(WorkspaceDiagnosticPage::Page {
            snapshot,
            items,
            next_cursor,
            counts,
        })
    }
}

#[cfg(test)]
mod page_tests {
    use super::*;

    fn diagnostic(message: String) -> Diagnostic {
        Diagnostic {
            severity: 1,
            line: 0,
            character: 3,
            end_line: Some(0),
            end_character: Some(9),
            document_version: None,
            message,
            source: Some("rustc".to_owned()),
            code: Some(DiagnosticCode::Text("E0308".to_owned())),
        }
    }

    fn request(cursor: Option<WorkspaceDiagnosticCursor>) -> WorkspaceDiagnosticPageRequest {
        WorkspaceDiagnosticPageRequest {
            open_uris: Vec::new(),
            limit: MAX_DIAGNOSTIC_PAGE_ROWS,
            cursor,
            known_snapshot: None,
        }
    }

    #[test]
    fn pages_keep_large_diagnostics_intact_and_expire_on_cache_change() {
        let mut cache = DiagnosticCache::new();
        let uri = "file:///fixture/😀/same.rs";
        let large = diagnostic("x".repeat(DIAGNOSTIC_PAGE_TEXT_BUDGET + 1));
        let small = diagnostic("next marker".to_owned());
        cache.publish(uri.to_owned(), vec![large.clone(), small.clone()]);
        let revision = cache.revision;
        cache.publish(uri.to_owned(), vec![large.clone(), small.clone()]);
        assert_eq!(cache.revision, revision);
        let WorkspaceDiagnosticPage::Page {
            items,
            next_cursor: Some(cursor),
            counts: Some(counts),
            ..
        } = cache.read_page(request(None)).unwrap()
        else {
            panic!("expected the first page");
        };
        assert_eq!(counts.errors, 2);
        assert_eq!(items.len(), 1);
        assert_eq!(items[0].diagnostic, large);
        let WorkspaceDiagnosticPage::Page {
            items,
            next_cursor: None,
            counts: None,
            ..
        } = cache.read_page(request(Some(cursor.clone()))).unwrap()
        else {
            panic!("expected the final page");
        };
        assert_eq!(items[0].diagnostic, small);
        cache.discard(uri);
        assert!(matches!(
            cache.read_page(request(Some(cursor.clone()))).unwrap(),
            WorkspaceDiagnosticPage::Stale { .. },
        ));
        assert!(matches!(
            DiagnosticCache::new()
                .read_page(request(Some(cursor)))
                .unwrap(),
            WorkspaceDiagnosticPage::Stale { .. },
        ));
    }
}
