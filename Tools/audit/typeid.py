# Type-identity oracle: every nominal type descriptor symbol ($s...Mn) a
# binary defines, demangled by Apple's swift-demangle, must be a type
# `swiftdc dump` declares, or one it names as not rendered.
#
#   python3 -I Tools/audit/typeid.py <swiftdc> <path | cache:<install path>> [--arch=A] [--show]
#
# A file's symbols come from `nm -U` (exported and local); a dyld cache
# image's from `dyld_info -exports`, since its symbol table may live in
# another subcache. Prints one line per binary (symbols, declared, missing,
# not-rendered) and, with --show, the missing types with their symbols.
import re, subprocess, sys
swiftdc, target = sys.argv[1], sys.argv[2]
arch = next((a[7:] for a in sys.argv if a.startswith('--arch=')), None)
show = '--show' in sys.argv
cache = target.startswith('cache:')
path = target[6:] if cache else target
def run(args):
    return subprocess.run(args, capture_output=True, text=True, errors='replace').stdout
syms = set()
if cache:
    for line in run(['xcrun', 'dyld_info', '-exports', path]).splitlines():
        t = line.split()
        if len(t) >= 2 and t[0].startswith('0x') and t[-1].endswith('Mn'): syms.add(t[-1])
else:
    for line in run(['nm', '-U'] + (['-arch', arch] if arch else []) + [path]).splitlines():
        t = line.split()
        if len(t) >= 3 and t[-1].endswith('Mn') and t[-1].startswith('_$s'): syms.add(t[-1])
syms = sorted(s[1:] if s.startswith('_') else s for s in syms)
p = subprocess.run(['xcrun', 'swift-demangle', '--compact'], input='\n'.join(syms), capture_output=True, text=True)
names = []
for s, d in zip(syms, p.stdout.splitlines()):
    pre = 'nominal type descriptor for '
    # A C type's descriptor (`__C.NSMatchingOptions`) is emitted for a
    # Swift conformance to it; `dump` declares only the image's own types.
    if d.startswith(pre) and not d[len(pre):].startswith('__C.'): names.append((s, d[len(pre):]))
dumpargs = [swiftdc, 'dump'] + (['--image-path', path] if cache else [path]) + (['--arch', arch] if arch else []) + ['-s', 'types']
dumped = subprocess.run(dumpargs, capture_output=True, text=True, errors='replace')
if dumped.returncode != 0:
    # A declined image (FairPlay-encrypted, malformed) declares nothing,
    # which is not a missing type.
    print(f'{target}\tsymbols={len(names)}\tdump-failed\t{dumped.stderr.strip().splitlines()[-1:] or ""}')
    sys.exit(0)
text = dumped.stdout
heads, declined, local = [], [], set()
for line in text.splitlines():
    m = re.match(r'^(?:(?:final|open|public|indirect|distributed|@objc)\s+)*(class|struct|enum|actor)\s+(.*)$', line)
    # A local type prints as swift-demangle does, "X #1 in f(...)": keyed by
    # its name and index, since dump and the symbol print f's signature
    # with different options.
    if m and ' #' in m.group(2): local.add(m.group(2).split(' #')[0] + ' #' + m.group(2).split(' #')[1].split(' ')[0])
    if m: heads.append(m.group(2))
    d = re.match(r'^// (?:class|struct|enum) (.*): not rendered: ', line)
    if d: declined.append(d.group(1))
def identity(text):
    # A type's identity, its module and nesting path. Printing differs
    # legitimately in what wraps it: dump shows an unconstrained same-module
    # extension that the mangling elides, and spells associated types in
    # full (A.Swift.Strideable.Stride for A.Stride). So drop
    # `(extension in M):`, every `<...>` group, and cut at the first space or
    # colon outside parentheses (`(Foo in _HASH)` keeps its spaces).
    text = re.sub(r'\(extension in [^)]*\):', '', text)
    # An imported C++ record prints by its C++ name in metadata,
    # `ns.ns::GfInterval`, and by its Swift path in the symbol, `ns.GfInterval`.
    text = re.sub(r'\b\w+::', '', text)
    out, angle, paren = [], 0, 0
    for c in text:
        if c == '<': angle += 1; continue
        if c == '>' and angle: angle -= 1; continue
        if angle: continue
        if c == '(': paren += 1
        if c == ')': paren -= 1
        if paren == 0 and c in ' :{': break
        out.append(c)
    return ''.join(out)
headset = {identity(h) for h in heads}
declinedset = {identity(h) for h in declined}
def localkey(n):
    return n.split(' #')[0] + ' #' + n.split(' #')[1].split(' ')[0] if ' #' in n else None
missing = [(s, n) for s, n in names if identity(n) not in headset and identity(n) not in declinedset and localkey(n) not in local]
nd = sum(1 for s, n in names if identity(n) not in headset and identity(n) in declinedset)
print(f'{target}\tsymbols={len(names)}\tdeclared={len(names)-len(missing)-nd}\tmissing={len(missing)}\tnot-rendered={nd}\theads={len(heads)}')
if show:
    for s, n in missing[:40]: print('  ', n, '   ', s)
