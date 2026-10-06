"""Static check for property names passed through table literals.

luau-lsp catches `part.Typo = 1`, but not keys inside `Components.new("Frame", { Typo = 1 })`
because the helper assigns them dynamically. This script checks those keys against the
Roblox API type definitions used by luau-lsp.

Usage: python3 tools/check_props.py path/to/globalTypes.d.luau src
"""
import re, sys, glob

defs = open(sys.argv[1]).read()
classes = {}
cur = None
for line in defs.split('\n'):
    m = re.match(r'declare (?:extern type|class) (\w+)(?: extends (\w+))? with', line) or re.match(r'declare (?:extern type|class) (\w+)(?: extends (\w+))?\s*$', line)
    if m:
        cur = m.group(1); classes[cur] = {'base': m.group(2), 'props': set()}; continue
    if cur and line.strip() == 'end':
        cur = None; continue
    if cur:
        pm = re.match(r'\s+(\w+)\s*:', line)
        if pm: classes[cur]['props'].add(pm.group(1))
        fm = re.match(r'\s+function (\w+)', line)
        if fm: classes[cur]['props'].add(fm.group(1))

def props(cls):
    out = set()
    while cls and cls in classes:
        out |= classes[cls]['props']; cls = classes[cls]['base']
    return out

def table_keys(src, start):
    """Given index of '{', return top-level keys and end index."""
    depth = 0; i = start; keys = []; n = len(src)
    token_start = start + 1
    while i < n:
        c = src[i]
        if c in '"\'':
            q = c; i += 1
            while i < n and src[i] != q:
                if src[i] == '\\': i += 1
                i += 1
        elif c == '[' and src[i:i+2] in ('[[', '[='):
            j = src.find(']]', i); i = j + 1
        elif c in '{([':
            depth += 1
            if depth == 1 and c == '{': token_start = i + 1
        elif c in '})]':
            depth -= 1
            if depth == 0: return keys, i
        elif depth == 1 and c == ',':
            token_start = i + 1
        if depth == 1 and c == '=' and src[i+1] != '=' and src[i-1] not in '=~<>':
            seg = src[token_start:i].strip()
            if re.fullmatch(r'\w+', seg): keys.append(seg)
        i += 1
    return keys, n

HELPERS = {
    'Components.label': ('TextLabel', {'MaxTextSize', 'NoConstraint'}),
    'Components.panel': ('Frame', {'Stroke', 'Radius', 'Gradient'}),
    'Components.scroll': ('ScrollingFrame', set()),
}
problems = []
for path in glob.glob(sys.argv[2] + '/**/*.luau', recursive=True):
    src = open(path).read()
    # Components.new("Class", { ... }) / new("Class", { ... })
    for m in re.finditer(r'(?:Components\.new|\bnew)\(\s*"(\w+)"\s*,\s*\{', src):
        cls = m.group(1); keys, _ = table_keys(src, m.end() - 1)
        valid = props(cls) | {'Parent'}
        for k in keys:
            if k not in valid: problems.append(f'{path}: {cls}.{k}')
    for helper, (cls, extra) in HELPERS.items():
        for m in re.finditer(re.escape(helper) + r'\(\s*\{', src):
            keys, _ = table_keys(src, m.end() - 1)
            valid = props(cls) | {'Parent'} | extra
            for k in keys:
                if k not in valid: problems.append(f'{path}: {helper} -> {cls}.{k}')
print('\n'.join(sorted(set(problems))) or 'no problems')
sys.exit(1 if problems else 0)
