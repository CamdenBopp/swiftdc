#!/usr/bin/env python3
"""Join checked ABI declarations to strong arm64 SDK exports and reexports.

Only the small install-name/reexport/TLS metadata is read here. LLVM's nm
parses the SDK's text stubs and identifies strong versus weak definitions.
Unsupported schemas, targets and unavailable reexports contribute no proof.
"""
import argparse
import ast
import json
from pathlib import Path
import re
import subprocess


def bracket_values(text):
    values = re.findall(r"'[^']*'|\"[^\"]*\"|[^,\s\[\]]+", text)
    return [ast.literal_eval(v) if v.startswith(("'", '"')) else v for v in values]


def declarations(paths):
    names = set()
    for path in paths:
        text = path.read_text()
        names.update(re.findall(r"^([A-Za-z_][A-Za-z_0-9$]*) [vidfsx](?: [A-Za-z0-9.]*)?[ \t]*$", text, re.M))
        names.update(re.findall(r'^\s*"([A-Za-z_][A-Za-z_0-9$]*)":\s*"[vidfsx] [A-Za-z0-9.]*"', text, re.M))
        # The fixed-arity runtime contracts predate the generated prototypes.
        # Join their exact switch labels to exports too; arity itself still
        # comes from Pseudo.swift, and no Swift error-register ABI is implied.
        marker = "    static func knownCArity(of callee: String) -> Int? {\n"
        if marker in text:
            body = text.split(marker, 1)[1].split("\n    }", 1)[0]
            body = re.sub(r"//[^\n]*", "", body)
            for labels in re.findall(r"(?ms)^        case (.*?):\s*return \d+\b", body):
                names.update(re.findall(r'"([A-Za-z_][A-Za-z_0-9$]*)"', labels))
    # objc/message.h declares these C dispatch entries. Their argument
    # layout is selector-dependent, so the ordinary prototype tables omit
    # them; their nonthrowing C error-register ABI is still fixed.
    names.update(["objc_msgSend", "objc_msgSendSuper", "objc_msgSendSuper2",
                  "objc_msgSend_stret", "objc_msgSendSuper_stret", "objc_msgSendSuper2_stret",
                  "objc_msgSend_fpret", "objc_msgSend_fp2ret"])
    assert {"getpid", "memset", "swift_getAtKeyPath"} <= names
    return names


def metadata(files):
    providers, edges, tls = set(), {}, {}
    for path in files:
        for doc in re.split(r"(?m)^---[^\n]*\n", path.read_text()):
            if not re.search(r"(?m)^tbd-version:\s*4\s*$", doc):
                continue
            install = re.search(r"(?m)^install-name:\s*(.+)$", doc)
            targets = re.search(r"(?s)^.*?\btargets:\s*(\[.*?\])", doc)
            if not install or not targets or not re.search(r"\barm64(?:e(?:\.x1)?)?-macos\b", targets[1]):
                continue
            name = install[1].strip()
            name = ast.literal_eval(name) if name.startswith(("'", '"')) else name
            if not name.startswith("/") or ".." in name.split("/"):
                continue
            providers.add(name)
            edges.setdefault(name, set())
            tls.setdefault(name, set())
            for field in re.finditer(r"(?s)\bthread-local-symbols:\s*(\[.*?\])", doc):
                tls[name].update(bracket_values(field[1]))
            section = re.search(r"(?ms)^reexported-libraries:\s*\n(.*?)(?=^\S|\Z)", doc)
            if not section:
                continue
            for group in re.split(r"(?m)^\s+- targets:", section[1])[1:]:
                target = re.match(r"\s*(\[.*?\])", group, re.S)
                if not target or not re.search(r"\barm64(?:e(?:\.x1)?)?-macos\b", target[1]):
                    continue
                libraries = re.search(r"(?s)\blibraries:\s*(\[.*?\])", group)
                if libraries:
                    edges[name].update(bracket_values(libraries[1]))
    return providers, edges, tls


def collect(sdk, names):
    roots = [sdk / "usr/lib", sdk / "System/Library/Frameworks"]
    files = sorted({p.resolve() for root in roots for p in root.rglob("*.tbd")})
    assert files, "no SDK stubs found"
    providers, edges, tls = metadata(files)
    assert providers, "no supported arm64-macOS SDK provider metadata"
    exports = {p: set() for p in providers}
    diagnostics = []
    for arch in ["arm64", "arm64e"]:
        for start in range(0, len(files), 100):
            result = subprocess.run(["xcrun", "llvm-nm", "--format=posix", "--defined-only", "--extern-only",
                                     "-arch", arch, *map(str, files[start:start + 100])],
                                    text=True, capture_output=True)
            if result.stderr:
                diagnostics.append(result.stderr[:2000])
            current = None
            for line in result.stdout.splitlines():
                header = re.fullmatch(r"(/.+) \(for architecture arm64e?\):", line)
                if header:
                    current = header[1] if header[1] in providers else None
                    continue
                if current is None:
                    continue
                fields = line.split()
                if len(fields) != 4:
                    continue
                raw, kind = fields[:2]
                # nm prints weak definitions W/V and undefined imports U;
                # thread-local exports otherwise look like ordinary S symbols.
                if not kind.isupper() or kind in {"W", "V", "U"} or raw in tls[current]:
                    continue
                name = raw[1:] if raw.startswith("_") else raw
                if name in names:
                    exports[current].add(name)
    direct = sum(map(len, exports.values()))
    assert direct, "LLVM decoded no strong exports matching the ABI declarations: " + "\n".join(diagnostics[:3])
    for iteration in range(len(providers) + 1):
        changed = False
        for provider in sorted(providers):
            old = len(exports[provider])
            for child in sorted(edges.get(provider, ())):
                exports[provider].update(exports.get(child, ()))
            changed |= len(exports[provider]) != old
        if not changed:
            break
    else:
        raise RuntimeError("SDK reexports did not converge")
    libraries = sorted(p for p in providers if exports[p])
    by_name = {}
    for index, provider in enumerate(libraries):
        for name in exports[provider]:
            by_name.setdefault(name, []).append(index)
    return libraries, by_name, dict(stub_files=len(files), providers=len(libraries), symbols=len(by_name),
                                   strong_direct_pairs=direct, export_reexport_pairs=sum(map(len, by_name.values())),
                                   llvm_diagnostic_batches=len(diagnostics))


def render(libraries, by_name, version):
    rows = "\n".join(name + " " + ",".join(map(str, by_name[name])) for name in sorted(by_name))
    paths = "\n".join("        " + json.dumps(path) + "," for path in libraries)
    return f'''// Generated by Tools/generate-nonthrowing-abi-providers.py from macOS SDK {version}.
// Declarations: SDKCPrototypes, SwiftRuntimeSignatures, SwiftIntrinsicSignatures,
// fixed-arity runtime contracts in Pseudo.swift, and objc/message.h dispatch entries.
// Only strong arm64 exports and their SDK reexports supply provider identity.

/// Provider membership for an independently checked ABI declaration. This
/// establishes no complete source arity, result bank or memory effect.
enum NonThrowingABIProviders {{
    static func canonicalLibrary(_ library: String) -> String {{
        switch library {{
        case "@rpath/libswiftCore.dylib": return "/usr/lib/swift/libswiftCore.dylib"
        case "@rpath/libswift_Concurrency.dylib": return "/usr/lib/swift/libswift_Concurrency.dylib"
        default: return library
        }}
    }}

    static func containsLibrary(_ library: String) -> Bool {{ indices[canonicalLibrary(library)] != nil }}

    static func permits(_ name: String, from library: String) -> Bool {{
        guard let index = indices[canonicalLibrary(library)],
              let providers = providerList(name) else {{ return false }}
        return providers.split(separator: ",").contains {{ Int($0) == index }}
    }}

    private static func providerList(_ name: String) -> String? {{
        var name = name
        return name.withUTF8 {{ key in data.withUTF8Buffer {{ SDKCPrototypes.lookup(key, in: $0) }} }}
    }}

    private static let indices = Dictionary(uniqueKeysWithValues: libraries.enumerated().map {{ ($0.element, $0.offset) }})
    private static let libraries = [
{paths}
    ]

    private static let data: StaticString = """
{rows}
"""
}}
'''


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sdk", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--report", type=Path)
    args = parser.parse_args()
    sdk = args.sdk or Path(subprocess.check_output(["xcrun", "--show-sdk-path"], text=True).strip())
    source = Path(__file__).resolve().parents[1] / "Sources/SwiftDecompilerCore"
    names = declarations([source / p for p in ["SDKCPrototypes.swift", "SwiftRuntimeSignatures.swift", "SwiftIntrinsicSignatures.swift", "Pseudo.swift"]])
    libraries, by_name, report = collect(sdk, names)
    version = json.loads((sdk / "SDKSettings.json").read_text()).get("Version", "unknown")
    args.output.write_text(render(libraries, by_name, version))
    if args.report:
        args.report.write_text(json.dumps(dict(sdk_version=version, **report), indent=2) + "\n")
    print(json.dumps(dict(sdk_version=version, **report)), flush=True)


if __name__ == "__main__":
    main()
