use std::collections::HashSet;

use serde::Serialize;

use super::{normalize_uri, Diagnostic, LspServer};

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
