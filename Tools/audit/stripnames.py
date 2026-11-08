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
KIND = {'getter', 'setter', 'modify', 'method', 'override', 'static', 'init', 'deinit', 'Swift', 'objc', 'thunk',
        'witness', 'protocol', 'conformance', 'in', 'for', 'of', 'async', 'throws', 'to', 'is', 'as'}
exact = compatible = conflict = unknown = objc = merged = 0


def objcParts(text):
    m = re.match(r'([-+])\[(\S+?)(?:\([^)]*\))? (.*)\]$', text)
    if not m:
        return None
    cls = m.group(2)
    t = re.match(r'_TtC(\d+)(\w+)', cls)
    if t:
        rest = t.group(2)[int(t.group(1)):]
        n = re.match(r'(\d+)', rest)
        cls = rest[len(n.group(1)):len(n.group(1)) + int(n.group(1))] if n else cls
    return m.group(1), cls, m.group(3)


def kindOf(truth):
    # The accessor or entry kind the demangled symbol names.
    head = truth.split(' in conformance ')[0]
    for kind in ('getter', 'setter', 'modify'):
        # An accessor, `x.getter : T`; a method can be named `modify(…)`.
        if re.search(r'\.' + kind + r'\b(?!\()', head):
            return kind
    if re.search(r'\.(__allocating_)?init[(<]', head):
        return 'init'
    if re.search(r'\.(__deallocating_)?deinit\b', head):
        return 'deinit'
    return 'method'


def lastComponent(path):
    # `M.(Foo in _H)` names Foo; generic arguments are not part of a name.
    # A local type, `X #1 in M.f(…)`, is named X.
    path = re.sub(r' #\d+ in .*$', '', path.strip())
    while re.search(r'<[^<>]*>', path):
        path = re.sub(r'<[^<>]*>', '', path)
    m = re.search(r'\((\w+) in _\w+\)$', path)
    return m.group(1) if m else path.split('.')[-1]


def placeholderAgrees(name, truth):
    # `T: P.kind` is a witness of T's conformance to P; `M.T.kind` an entry
    # of M.T's vtable. The symbol must name that conformance or that type,
    # and the same kind of entry. `override` and `method` stand for any
    # method, including an initializer.
    m = re.match(r'^(?:static )?(.+?)\.(method|getter|setter|modify|override|init|deinit)$', name)
    if not m:
        return True
    subject, kind = m.group(1), m.group(2)
    actual = kindOf(truth)
    # `static T.kind` claims a static or class member, `T.kind` an instance one.
    member = re.sub(r'^vtable thunk for .* dispatching to ', '', truth)
    member = re.sub(r'^protocol witness for ', '', member)
    member = re.sub(r'^(@objc |merged |dispatch thunk of |method descriptor for )+', '', member)
    # `T.override` is a slot whose base method is in another image, and
    # claims nothing about it.
    if kind != 'override' and name.startswith('static ') != member.startswith('static '):
        return False
    if kind in ('method', 'override'):
        if actual not in ('method', 'init') and kind == 'method':
            return False
    elif kind != actual:
        return False
    if ': ' in subject:
        conformer, proto = subject.split(': ', 1)
        c = re.search(r' in conformance (.+?) : (.+?)(?: in \S+)?$', truth)
        return bool(c) and lastComponent(c.group(1)) == conformer and lastComponent(c.group(2)) == lastComponent(proto)
    c = re.search(r'^protocol witness for .* in conformance (.+?) : (.+?)(?: in \S+)?$', truth)
    if c:
        # A witness named by its protocol alone (`Attachable.method` for
        # `[Swift.UInt8] : Testing.Attachable`).
        return lastComponent(c.group(2)) == lastComponent(subject)
    # A dropped anonymous context is marked `(unknown context at $addr)`:
    # the type is local to a function or private to a file, which the
    # symbol spells `m in X #1 in M.T.f(…)` or `M.(X in _H)`.
    marked = '(unknown context at $' in subject
    subject = re.sub(r'\.\(unknown context at \$[0-9a-f]+\)', '', subject)
    local = re.search(r' in (\w+) #\d+ in (.*)$', truth)
    if marked and local:
        owner = re.sub(r'\(extension in [^)]*\):', '', local.group(2))
        while re.search(r'<[^<>]*>', owner):
            owner = re.sub(r'<[^<>]*>', '', owner)
        owner = re.sub(r'\((\w+) in _\w+\)', r'\1', owner)
        function = re.match(r'^(?:static )?([\w.]+?)\.[^.(]+\(', owner)
        context = function.group(1) if function else ''
        return subject in (context + '.' + local.group(1), local.group(1))
    # A vtable thunk is an entry of the class it dispatches to.
    entity = re.sub(r'^vtable thunk for .* dispatching to ', '', truth)
    entity = re.sub(r'^(static |@objc |merged |dispatch thunk of |method descriptor for )+', '', entity)
    # swiftdc spells a type by its module and nesting path: no extension
    # context, generic arguments or private discriminator.
    entity = re.sub(r'\(extension in [^)]*\):', '', entity)
    while re.search(r'<[^<>]*>', entity):
        entity = re.sub(r'<[^<>]*>', '', entity)
    entity = re.sub(r'\((\w+) in _\w+\)', r'\1', entity)
    subject = re.sub(r'\(extension in [^)]*\):', '', subject)
    subject = re.sub(r'\((\w+) in _\w+\)', r'\1', subject)
    return entity.startswith(subject + '.') or entity.startswith(re.sub(r'^.*?\.', '', subject, count=1) + '.')


def objcMatch(name, truth):
    a, b = objcParts(name), objcParts(truth)
    return a is not None and a == b
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
    # The same class and selector under another category: the linker merges
    # a class's categories and keeps the first one's name, which is then the
    # name the runtime reports (`NSTextView(diffSpecials)` holds `extras`'s
    # methods in FileMerge). A Swift class prints by its runtime name
    # (`_TtC15IDESourceEditor16SourceCodeEditor` for `SourceCodeEditor`).
    if name[:2] in ('-[', '+[') and any(objcMatch(name, t) for t in truths):
        merged += 1
        continue
    # A C symbol keeps the C underscore (`___swift_project_…` for
    # `__swift_project_…`), and a recognised boxed-existential helper leaves
    # out the witness-table count the symbol carries (`…_existential_0`,
    # `…_1Tm` when merged).
    if any(t == '_' + name or re.fullmatch(re.escape('_' + name) + r'_\d+(Tm)?', t) for t in truths):
        exact += 1
        continue
    plain = re.sub(r'\(unknown context at \$[0-9a-f]+\)', '', name)
    words = {w for w in re.findall(r'[A-Za-z_][A-Za-z0-9_]+', plain) if w not in KIND}
    if any(all(re.search(r'\b' + re.escape(w) + r'\b', t) for w in words) and placeholderAgrees(name, t) for t in truths):
        compatible += 1
        if '--show-compatible' in sys.argv:
            print(f'  compatible 0x{address:x}  {name}  <=>  {truths[0]}')
    else:
        conflict += 1
        conflicts.append((address, name, truths[0]))
print(f'{binary}\trecovered={len(judged)}\texact={exact}\tcompatible={compatible}\tobjc-thunk={objc}\tobjc-merged={merged}\tconflict={conflict}\tno-symbol={unknown}')
if show:
    for address, name, truth in conflicts:
        print(f'  0x{address:x}  swiftdc: {name}\n           symbol:  {truth}')
