use std::collections::HashSet;

use serde::Serialize;

use super::{normalize_uri, Diagnostic, LspServer};

#[derive(Debug, Clone, Serialize)]
pub struct WorkspaceDiagnosticCandidate {
    pub uri: String,
    pub wrapped: bool,
    pub diagnostic: Diagnostic,
}

impl LspServer {
    /// Read one navigable file diagnostic outside the caller's open resources.
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
        let (wrapped, uri, _, diagnostic) = cache
            .iter()
            .filter(|(uri, _)| uri.starts_with("file://") && !excluded.contains(uri.as_str()))
            .flat_map(|(uri, diagnostics)| {
                let uri = uri.as_str();
                let wrapped = cursor.as_deref().is_some_and(|cursor| {
                    if forward {
                        uri <= cursor
                    } else {
                        uri >= cursor
                    }
                });
                diagnostics.iter().filter_map(move |diagnostic| {
                    let end = (diagnostic.end_line?, diagnostic.end_character?);
                    let start = (diagnostic.line, diagnostic.character);
                    if !(1..=3).contains(&diagnostic.severity) || end < start {
                        return None;
                    }
                    let sort_key = (diagnostic.severity, start, end);
                    Some((wrapped, uri, sort_key, diagnostic))
                })
            })
            .min_by(|a, b| {
                a.0.cmp(&b.0).then_with(|| {
                    let order = (a.1, a.2).cmp(&(b.1, b.2));
                    if forward {
                        order
                    } else {
                        order.reverse()
                    }
                })
            })?;
        Some(WorkspaceDiagnosticCandidate {
            uri: uri.to_owned(),
            wrapped,
            diagnostic: diagnostic.clone(),
        })
    }
}
