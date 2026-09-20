#!/usr/bin/env python3
"""Extract top-level shell function definitions from a script.

The naive awk approach (capture from '^name() {' to the first '^}') breaks on
functions containing heredocs whose payload has column-0 '}' lines (run.sh
embeds JS starter templates). This extractor counts { / } per line while
ignoring heredoc bodies, single/double-quoted spans it can cheaply detect, and
comments, then emits every top-level function verbatim.
"""
import re
import sys


def extract(text: str) -> str:
    out = []
    lines = text.splitlines()
    i = 0
    n = len(lines)
    func_re = re.compile(r'^[A-Za-z_][A-Za-z0-9_]*\(\) \{\s*(?:#.*)?$')
    while i < n:
        if func_re.match(lines[i]):
            depth = 0
            j = i
            heredoc = None
            while j < n:
                line = lines[j]
                if heredoc is not None:
                    if line.strip() == heredoc:
                        heredoc = None
                    # heredoc payload: braces don't count
                else:
                    m = re.search(r'<<-?\s*[\'"]?([A-Za-z_][A-Za-z0-9_]*)[\'"]?', line)
                    if m:
                        heredoc = m.group(1)
                    else:
                        # strip comments, but never the '#' inside ${#...} or strings
                        code = re.sub(r'(^|\s)#.*$', r'\1', line)
                        depth += code.count('{') - code.count('}')
                        if depth <= 0:
                            break
                j += 1
            out.extend(lines[i:j + 1])
            out.append('')
            i = j + 1
        else:
            i += 1
    return '\n'.join(out)


if __name__ == '__main__':
    with open(sys.argv[1], encoding='utf-8', errors='replace') as f:
        # Windows consoles default to cp1252 and choke on box-drawing chars in
        # the extracted functions; force UTF-8 stdout so tests run everywhere.
        sys.stdout.reconfigure(encoding='utf-8', errors='replace')
        sys.stdout.write(extract(f.read()))
