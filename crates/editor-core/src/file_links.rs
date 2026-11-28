use editor_buffer::{BufferError, MAX_READ_RANGE_UTF16};

use crate::{ApplyError, DocRegistry};

const FILE_SCHEME: &[u8] = b"file://";

#[derive(Debug, PartialEq, Eq)]
pub(crate) struct FileLink {
    pub(crate) uri: String,
    pub(crate) start_utf16: usize,
    pub(crate) end_utf16: usize,
}

pub(crate) fn file_link_at_utf16(
    documents: &DocRegistry,
    id: u64,
    offset_utf16: usize,
) -> Result<(u64, Option<FileLink>), ApplyError> {
    let version = documents.version_of(id).ok_or(ApplyError::UnknownDoc)?;
    let (line_number, column) = documents
        .line_col(id, offset_utf16)
        .ok_or(BufferError::InvalidUtf16Offset { offset_utf16 })?;
    let column = column as usize;
    let lines = documents
        .read_lines(
            id,
            line_number as usize,
            1,
            column.saturating_sub(MAX_READ_RANGE_UTF16 / 2),
            MAX_READ_RANGE_UTF16,
            MAX_READ_RANGE_UTF16,
        )
        .ok_or(ApplyError::UnknownDoc)??;
    let Some(line) = lines.lines.first() else {
        return Ok((version, None));
    };
    let includes_line_end = if line.end_utf16 == lines.total_utf16_length {
        true
    } else {
        let after = documents
            .read_range(id, line.end_utf16, 2)
            .ok_or(ApplyError::UnknownDoc)??;
        after.text.starts_with('\n') || after.text.starts_with("\r\n")
    };
    let link = scan_file_link(
        &line.text,
        line.start_utf16,
        offset_utf16,
        line.start_utf16 == offset_utf16 - column,
        includes_line_end,
    );
    Ok((version, link))
}

fn scan_file_link(
    text: &str,
    start_utf16: usize,
    caret_utf16: usize,
    includes_line_start: bool,
    includes_line_end: bool,
) -> Option<FileLink> {
    let mut consumed = 0;
    let mut consumed_utf16 = start_utf16;
    while let Some(relative_start) = text.as_bytes()[consumed..]
        .windows(FILE_SCHEME.len())
        .enumerate()
        .find_map(|(index, candidate)| {
            if !candidate.eq_ignore_ascii_case(FILE_SCHEME) {
                return None;
            }
            let start = consumed + index;
            let separated = if start == 0 {
                includes_line_start
            } else {
                text[..start]
                    .chars()
                    .next_back()
                    .is_some_and(|ch| !ch.is_alphanumeric() && ch != '_')
            };
            separated.then_some(index)
        })
    {
        let start = consumed + relative_start;
        let link_start_utf16 = consumed_utf16 + text[consumed..start].encode_utf16().count();
        if caret_utf16 < link_start_utf16 {
            return None;
        }
        let tail = &text[start..];
        let token_end = link_token_end(tail);
        let uri = tail[..token_end].trim_end_matches(['.', ',', ';', ':']);
        let link_end_utf16 = link_start_utf16 + uri.encode_utf16().count();
        if caret_utf16 <= link_end_utf16 {
            return (uri.len() > FILE_SCHEME.len()
                && (token_end < tail.len() || includes_line_end))
                .then(|| FileLink {
                    uri: uri.to_owned(),
                    start_utf16: link_start_utf16,
                    end_utf16: link_end_utf16,
                });
        }
        consumed = start + token_end;
        consumed_utf16 = link_start_utf16 + tail[..token_end].encode_utf16().count();
    }
    None
}

fn link_token_end(tail: &str) -> usize {
    let mut closers = Vec::new();
    for (index, ch) in tail.char_indices() {
        if ch.is_whitespace()
            || ch.is_control()
            || matches!(
                ch,
                '"' | '\'' | '<' | '>' | '\u{60}' | '|' | '“' | '”' | '‘' | '’'
            )
        {
            return index;
        }
        match ch {
            '(' => closers.push(')'),
            '[' => closers.push(']'),
            '{' => closers.push('}'),
            ')' | ']' | '}' if closers.last() != Some(&ch) => return index,
            ')' | ']' | '}' => {
                closers.pop();
            }
            _ => {}
        }
    }
    tail.len()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reports_utf16_coordinates_with_bom_crlf_and_wrapped_paths() {
        let prefix = "\u{feff}前🦊\r\n查看 (";
        let uri = "FILE:///tmp/with%20space(a).txt";
        let text = format!("{prefix}{uri}).\r\nnext");
        let mut docs = DocRegistry::new();
        let version = docs.open(3, &text);
        let start = prefix.encode_utf16().count();
        let end = start + uri.encode_utf16().count();
        let (actual_version, link) = file_link_at_utf16(&docs, 3, start + 9).unwrap();
        assert_eq!(actual_version, version);
        assert_eq!(
            link,
            Some(FileLink {
                uri: uri.into(),
                start_utf16: start,
                end_utf16: end,
            }),
        );
        assert_eq!(file_link_at_utf16(&docs, 3, end + 1).unwrap().1, None);
    }

    #[test]
    fn selects_only_the_link_under_the_caret() {
        let text = "notafile:///tmp/ignored rust and file:///tmp/one, file:///tmp/two.";
        let mut docs = DocRegistry::new();
        docs.open(3, text);
        let first = text.find("file:///tmp/ignored").unwrap();
        assert_eq!(file_link_at_utf16(&docs, 3, first + 9).unwrap().1, None);
        let second = text.find("file:///tmp/two").unwrap();
        assert_eq!(
            file_link_at_utf16(&docs, 3, second + 9)
                .unwrap()
                .1
                .unwrap()
                .uri,
            "file:///tmp/two",
        );
    }

    #[test]
    fn reads_near_the_caret_and_declines_truncated_paths() {
        let prefix = format!("{} ", "a".repeat(MAX_READ_RANGE_UTF16 + 10));
        let text = format!("{prefix}file:///tmp/keep.txt");
        let mut docs = DocRegistry::new();
        docs.open(3, &text);
        assert_eq!(
            file_link_at_utf16(&docs, 3, prefix.len() + 9)
                .unwrap()
                .1
                .unwrap()
                .uri,
            "file:///tmp/keep.txt",
        );

        let too_long = format!("file:///tmp/{}", "a".repeat(MAX_READ_RANGE_UTF16));
        docs.open(3, &too_long);
        assert_eq!(file_link_at_utf16(&docs, 3, 12).unwrap().1, None);
    }
}
