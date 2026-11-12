use crate::api::editor::RustFoldRange;
use ropey::{Rope, RopeSlice};
use std::collections::HashMap;

// Mirrors the renderer's per-line fallback for small documents: a bracket
// fold, or for a line ending in ':' the run of deeper-indented lines after
// it, the smaller of the two when a line has both.
pub fn compute_all(rope: &Rope, tab_size: usize) -> Vec<RustFoldRange> {
    let mut ends: HashMap<i32, i32> = HashMap::new();
    for fold in bracket_folds(rope) {
        ends.entry(fold.start_line).or_insert(fold.end_line);
    }
    for fold in indent_folds(rope, tab_size) {
        ends.entry(fold.start_line)
            .and_modify(|end| *end = (*end).min(fold.end_line))
            .or_insert(fold.end_line);
    }
    let mut folds: Vec<RustFoldRange> = ends
        .into_iter()
        .map(|(start_line, end_line)| RustFoldRange {
            start_line,
            end_line,
        })
        .collect();
    folds.sort_by_key(|fold| fold.start_line);
    folds
}

fn bracket_folds(rope: &Rope) -> Vec<RustFoldRange> {
    let mut folds = Vec::new();
    let mut open: [Vec<i32>; 3] = Default::default();
    let mut line_idx: i32 = 0;

    for ch in rope.chars() {
        let (kind, opens) = match ch {
            '\n' => {
                line_idx += 1;
                continue;
            }
            '{' => (0, true),
            '}' => (0, false),
            '[' => (1, true),
            ']' => (1, false),
            '(' => (2, true),
            ')' => (2, false),
            _ => continue,
        };
        if opens {
            open[kind].push(line_idx);
        } else if let Some(start_line) = open[kind].pop() {
            if start_line < line_idx {
                folds.push(RustFoldRange {
                    start_line,
                    end_line: line_idx,
                });
            }
        }
    }
    folds
}

fn indent_folds(rope: &Rope, tab_size: usize) -> Vec<RustFoldRange> {
    let mut folds = Vec::new();
    let mut open: Vec<(usize, usize)> = Vec::new();
    let mut last_content = 0;
    for (line_idx, line) in rope.lines().enumerate() {
        let Some((indent, ends_with_colon)) = scan_line(line, tab_size) else {
            continue;
        };
        while let Some(&(start, start_indent)) = open.last() {
            if indent > start_indent {
                break;
            }
            open.pop();
            close(start, last_content, &mut folds);
        }
        if ends_with_colon {
            open.push((line_idx, indent));
        }
        last_content = line_idx;
    }
    for (start, _) in open {
        close(start, last_content, &mut folds);
    }
    folds
}

fn close(start: usize, end: usize, folds: &mut Vec<RustFoldRange>) {
    if end > start {
        folds.push(RustFoldRange {
            start_line: start as i32,
            end_line: end as i32,
        });
    }
}

// The leading indent in columns and whether the line ends in ':', or None
// for a blank line.
fn scan_line(line: RopeSlice, tab_size: usize) -> Option<(usize, bool)> {
    let mut indent = 0;
    let mut in_indent = true;
    let mut last = None;
    for ch in line.chars() {
        if in_indent {
            match ch {
                ' ' => indent += 1,
                '\t' if tab_size > 0 => indent += tab_size - indent % tab_size,
                '\t' => indent += 1,
                _ => in_indent = false,
            }
        }
        // The per-line pass in Dart trims U+FEFF as whitespace.
        if !ch.is_whitespace() && ch != '\u{feff}' {
            last = Some(ch);
        }
    }
    last.map(|ch| (indent, ch == ':'))
}

// The editor asks while it paints, so a bracket whose pair lies further away
// than this goes unmatched rather than stall the frame on a large document.
const MAX_BRACKET_SCAN: usize = 100_000;

pub fn find_matching_bracket(rope: &Rope, target_offset: usize) -> Option<usize> {
    if target_offset >= rope.len_chars() {
        return None;
    }

    let start_ch: char = rope.char(target_offset);

    let (matcher, search_forward) = match start_ch {
        '{' => ('}', true),
        '[' => (']', true),
        '(' => (')', true),
        '}' => ('{', false),
        ']' => ('[', false),
        ')' => ('(', false),
        _ => return None,
    };

    let mut depth = 1;
    let mut step = |ch: char| {
        if ch == start_ch {
            depth += 1;
        } else if ch == matcher {
            depth -= 1;
        }
        depth == 0
    };

    if search_forward {
        let mut chars = rope.chars_at(target_offset + 1);
        for distance in 1..=MAX_BRACKET_SCAN {
            if step(chars.next()?) {
                return Some(target_offset + distance);
            }
        }
    } else {
        let mut chars = rope.chars_at(target_offset);
        for distance in 1..=MAX_BRACKET_SCAN {
            if step(chars.prev()?) {
                return Some(target_offset - distance);
            }
        }
    }

    None
}

#[cfg(test)]
mod tests {
    use super::*;

    fn folds(text: &str) -> Vec<(i32, i32)> {
        compute_all(&Rope::from_str(text), 2)
            .into_iter()
            .map(|fold| (fold.start_line, fold.end_line))
            .collect()
    }

    #[test]
    fn a_key_folds_over_its_deeper_lines_across_blank_ones() {
        let text = "proxies:\n  - name: a\n    ws-opts:\n      path: /\n\n  - name: b\nrules:\n  - MATCH,DIRECT\n\n";
        assert_eq!(folds(text), [(0, 5), (2, 3), (6, 7)]);
    }

    #[test]
    fn a_key_without_deeper_lines_does_not_fold() {
        assert_eq!(folds("a:\nb: 1\nc:\n"), []);
    }

    #[test]
    fn a_byte_order_mark_counts_as_blank() {
        assert_eq!(folds("a:\u{feff}\n  b\nc\n"), [(0, 1)]);
        assert_eq!(folds("a:\n  b\n\u{feff}\n  c\nd\n"), [(0, 3)]);
    }

    #[test]
    fn a_line_with_both_keeps_the_smaller_fold() {
        assert_eq!(folds("f(a,\n  b:\n    c\n  d)\n"), [(0, 3), (1, 2)]);
        assert_eq!(folds("x: {\n  a: 1\n}\n"), [(0, 2)]);
    }

    #[test]
    fn a_bracket_finds_its_pair_in_either_direction() {
        let rope = Rope::from_str("a { b [ c ] { } } (");
        assert_eq!(find_matching_bracket(&rope, 2), Some(16));
        assert_eq!(find_matching_bracket(&rope, 16), Some(2));
        assert_eq!(find_matching_bracket(&rope, 10), Some(6));
        assert_eq!(find_matching_bracket(&rope, 18), None);
        assert_eq!(find_matching_bracket(&rope, 0), None);
    }

    #[test]
    fn a_pair_past_the_scan_limit_goes_unmatched() {
        let near = format!("{{{}}}", " ".repeat(MAX_BRACKET_SCAN - 1));
        let rope = Rope::from_str(&near);
        assert_eq!(find_matching_bracket(&rope, 0), Some(MAX_BRACKET_SCAN));
        assert_eq!(find_matching_bracket(&rope, MAX_BRACKET_SCAN), Some(0));

        let far = format!("{{{}}}", " ".repeat(MAX_BRACKET_SCAN));
        let rope = Rope::from_str(&far);
        assert_eq!(find_matching_bracket(&rope, 0), None);
        assert_eq!(find_matching_bracket(&rope, MAX_BRACKET_SCAN + 1), None);
    }

    #[test]
    fn a_stray_bracket_leaves_the_other_kinds_their_folds() {
        assert_eq!(folds("a {\n  b (\n}\n"), [(0, 2)]);
        assert_eq!(folds("a [\n  b )\n]\n"), [(0, 2)]);
        assert_eq!(folds("f(x, [\n  y)\n]\n"), [(0, 1)]);
    }
}
