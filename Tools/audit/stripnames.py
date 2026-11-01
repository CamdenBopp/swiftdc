# Stripped-name oracle: strip a binary that has its local symbols, run
# `swiftdc disasm` on the stripped copy, and check every function name
# swiftdc recovered from metadata (no symbol left at that address) against
# the original symbol there, demangled by swift-demangle.
#
#   python3 -I Tools/audit/stripnames.py <swiftdc> <binary> <scratch dir> [--arch=A] [--show]
#
# A name is exact when it equals the demangled symbol, compatible when every
# identifier in it occurs in the demangled symbol (`Circle: Shape.method` for
# a protocol witness), and a conflict otherwise: it names something the
# function is not. Addresses with no original symbol are counted apart.
import os, re, subprocess, sys

swiftdc, binary, scratch = sys.argv[1], sys.argv[2], sys.argv[3]
arch = next((a[7:] for a in sys.argv if a.startswith('--arch=')), None)
show = '--show' in sys.argv
os.makedirs(scratch, exist_ok=True)
base = os.path.join(scratch, os.path.basename(binary))
thin = base + '.thin'
if arch:
    subprocess.run(['lipo', '-thin', arch, binary, '-output', thin], check=True)
else:
    subprocess.run(['cp', binary, thin], check=True)
stripped = base + '.stripped'
subprocess.run(['xcrun', 'strip', '-x', '-o', stripped, thin], check=True, capture_output=True)


def symbols(path):
    table = {}
    for line in subprocess.run(['nm', '-n', path], capture_output=True, text=True).stdout.splitlines():
        # An Objective-C method's symbol has spaces: `-[Class sel:]`.
        fields = line.split(maxsplit=2)
        if len(fields) == 3 and fields[1].lower() == 't':
            table.setdefault(int(fields[0], 16), []).append(fields[2])
    return table


before, after = symbols(thin), symbols(stripped)
listing = subprocess.run([swiftdc, 'disasm', stripped], capture_output=True, text=True, errors='replace').stdout
# The copies are this run's own.
os.remove(thin)
os.remove(stripped)
lines = listing.split('\n')
recovered = {}
for i, line in enumerate(lines):
    if not line.endswith(':') or line.startswith(' ') or line.startswith('sub_'):
        continue
    for j in (1, 2):
        m = re.match(r'\s+([0-9a-f]+):', lines[i + j]) if i + j < len(lines) else None
        if m:
            recovered[int(m.group(1), 16)] = line[:-1]
            break
judged = {a: n for a, n in recovered.items() if a not in after}
mangled = {a: before[a] for a in judged if a in before}
flat = sorted({s for names in mangled.values() for s in names})
demangled = dict(zip(flat, subprocess.run(['xcrun', 'swift-demangle', '--compact'],
                                          input='\n'.join(s[1:] if s.startswith('_$') else s for s in flat),
                                          capture_output=True, text=True).stdout.splitlines()))
# Words that describe a function's kind or the language, not an entity.
KIND = {'getter', 'setter', 'modify', 'method', 'static', 'init', 'deinit', 'Swift', 'objc', 'thunk',
        'witness', 'protocol', 'conformance', 'in', 'for', 'of', 'async', 'throws', 'to', 'is', 'as'}
exact = compatible = conflict = unknown = objc = 0
conflicts = []
for address, name in sorted(judged.items()):
    if address not in mangled:
        unknown += 1
        continue
    truths = [demangled.get(s, s) for s in mangled[address]]
    if name in truths:
        exact += 1
        continue
    # An `@objc` thunk is the IMP of an Objective-C method, and swiftdc
    # names it by its runtime class and selector (`-[SDWidget label]` for
    # `@objc sample.Widget.label.getter`), which words cannot match.
    if name[:2] in ('-[', '+[') and any(t.startswith('@objc ') for t in truths):
        objc += 1
        continue
    words = {w for w in re.findall(r'[A-Za-z_][A-Za-z0-9_]+', name) if w not in KIND}
    if any(all(re.search(r'\b' + re.escape(w) + r'\b', t) for w in words) for t in truths):
        compatible += 1
    else:
        conflict += 1
        conflicts.append((address, name, truths[0]))
print(f'{binary}\trecovered={len(judged)}\texact={exact}\tcompatible={compatible}\tobjc-thunk={objc}\tconflict={conflict}\tno-symbol={unknown}')
if show:
    for address, name, truth in conflicts[:40]:
        print(f'  0x{address:x}  swiftdc: {name}\n           symbol:  {truth}')
