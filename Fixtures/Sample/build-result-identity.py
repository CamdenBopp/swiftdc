#!/usr/bin/env python3
"""Build real-object retain controls after fresh compiler ABI checks; never load."""
from pathlib import Path
import argparse, importlib.util, json, re, shutil, tempfile

ROOT = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("arc_fixture_ir_checks", ROOT / "build-arc-origin.py")
checks = importlib.util.module_from_spec(spec)
spec.loader.exec_module(checks)
LEVELS = [("Onone", "ResultIdentityOnone", ".Onone"), ("O", "ResultIdentity", ""), ("Osize", "ResultIdentitySize", ".size")]


def abi(line, convention, result, arguments):
    symbol, prefix, parameters = checks.signature(line)
    if not re.search(r"\b" + result + r"\s*$", prefix):
        raise RuntimeError("Unproved result ABI: " + line)
    cc = re.findall(r"\b(?:cc\s+\d+|[A-Za-z_]+cc)\b", prefix)
    if not (cc == ["swiftcc"] if convention == "swift" else cc in ([], ["ccc"])):
        raise RuntimeError("Unproved calling convention: " + line)
    if len(parameters) != len(arguments) or any(not re.match(r"^" + typ + r"(?:\s|$)", item)
            for typ, item in zip(arguments, parameters)):
        raise RuntimeError("Unproved ordinary/hidden parameter ABI: " + line)
    if any(re.search(r"\b(?:swiftself|swifterror|swiftasync|sret|byval|inalloca)\b", item) for item in parameters):
        raise RuntimeError("Unexpected special ABI argument: " + line)
    return {"symbol": symbol, "mach_symbol": checks.mach_symbol(symbol), "header_or_call": line,
            "calling_convention": convention, "return_type": result, "parameter_types": arguments}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-directory", type=Path, default=ROOT)
    parser.add_argument("--legacy-bindings", action="store_true", help="Use dyld bind opcodes instead of chained fixups")
    parser.add_argument("--indirect-calls", action="store_true", help="Call the retain through its GOT pointer")
    options = parser.parse_args()
    output = options.output_directory.resolve()
    output.mkdir(parents=True, exist_ok=True)
    published = []
    with tempfile.TemporaryDirectory(prefix="result-identity-", dir=output) as temporary:
        workroot = Path(temporary)
        commands = []
        for level, module, suffix in LEVELS:
            if options.legacy_bindings:
                module += "Legacy"
                suffix += ".legacy"
            if options.indirect_calls:
                module += "Indirect"
                suffix += ".indirect"
            work = workroot / level
            work.mkdir()
            common = ["xcrun", "swiftc", "-parse-as-library", "-" + level, "-module-name", module]
            oracle = work / "oracle.ll"
            checks.run(common + ["-emit-ir", str(ROOT / "result_identity_abi.swift"), "-o", str(oracle)], work, "ABI-oracle", commands)
            checks.require_arm64_macos(oracle.read_text())
            functions = checks.ir_functions(oracle.read_text())
            entries = {}
            for name in ["run", "twice", "immediate"]:
                symbol = "$s" + str(len(module)) + module + str(len(name)) + name + "SiyF"
                function = checks.exact(functions, lambda f: f["symbol"] == symbol and f["header"].startswith("define "), name + " Swift ABI oracle")
                entries[name] = abi(function["header"], "swift", "i64", [])
            runtime = checks.exact(functions, lambda f: f["symbol"] == "swift_bridgeObjectRetain", "actual runtime declaration")
            runtime_abi = abi(runtime["header"], "C", "ptr", ["ptr"])
            calls = [line.strip() for line in oracle.read_text().splitlines()
                     if re.search(r"\bcall\b", line) and checks.SYMBOL.search(line)
                     and checks.signature(line)[0] == "swift_bridgeObjectRetain"]
            if not calls:
                raise RuntimeError("The compiler oracle emitted no bridge-object retain call")
            for line in calls:
                abi(line, "C", "ptr", ["ptr"])
                if "returned" not in checks.signature(line)[2][0].split():
                    raise RuntimeError("The compiler did not promise first-argument identity: " + line)
            source_ir = work / "provider.ll"
            checks.run(common + ["-emit-ir", str(ROOT / "result_identity.swift"), "-o", str(source_ir)], work, "provider-IR", commands)
            checks.require_arm64_macos(source_ir.read_text())
            providers = checks.ir_functions(source_ir.read_text())
            expected = {"result_identity_make": ("ptr", []), "result_identity_sink": ("i64", ["ptr"]),
                        "result_identity_destroy": ("void", ["ptr"]), "result_identity_count": ("i64", []),
                        "result_identity_destroyed": ("i64", []), "result_identity_reset": ("void", [])}
            provider_abi = {}
            for name, (result, arguments) in expected.items():
                function = checks.exact(providers, lambda f: f["symbol"] == name and f["header"].startswith("define "), name + " C export")
                provider_abi[name] = abi(function["header"], "C", result, arguments)
            assembly = (ROOT / "result_identity.s").read_text().replace("14ResultIdentity", str(len(module)) + module)
            if options.indirect_calls:
                if assembly.count("bl _swift_bridgeObjectRetain") != 3:
                    raise RuntimeError("Unexpected number of direct retain calls in the authored assembly")
                assembly = assembly.replace("bl _swift_bridgeObjectRetain",
                    "adrp x16, _swift_bridgeObjectRetain@GOTPAGE\n"
                    "  ldr x16, [x16, _swift_bridgeObjectRetain@GOTPAGEOFF]\n"
                    "  blr x16")
            labels = re.findall(r"^(_[A-Za-z0-9_$]+):", assembly, re.MULTILINE)
            if labels != [entries[name]["mach_symbol"] for name in ["run", "twice", "immediate"]]:
                raise RuntimeError("Assembly labels differ from actual compiler ABI oracles")
            asm = work / "entry.s"
            asm.write_text(assembly)
            obj = work / "entry.o"
            checks.run(["xcrun", "clang", "-arch", "arm64", "-mmacosx-version-min=15.0", "-c", str(asm), "-o", str(obj)], work, "assembly", commands)
            library = work / ("libResultIdentity" + suffix + ".dylib")
            link = common + ["-emit-library", str(ROOT / "result_identity.swift"), str(obj), "-o", str(library),
                "-Xlinker", "-twolevel_namespace", "-Xlinker", "-install_name", "-Xlinker", "@rpath/" + library.name]
            if options.legacy_bindings:
                link += ["-Xlinker", "-no_fixup_chains"]
            checks.run(link, work, "link", commands)
            proof = {"schema": 1, "compiler_ABI_verified": True, "module": module, "level": level,
                     "library_file": library.name, "library_sha256": checks.sha(library),
                     "binding_format": "legacy" if options.legacy_bindings else "chained",
                     "call_form": "indirect" if options.indirect_calls else "direct",
                     "entries": entries, "providers": provider_abi, "runtime": runtime_abi,
                     "actual_runtime_calls": calls, "oracle_IR": oracle.read_text(),
                     "provider_IR": source_ir.read_text(), "assembly": assembly,
                     "expected_value": 7, "expected_constructions": 1, "expected_destructions": 1}
            shutil.copy2(library, output / library.name)
            (output / (library.name + ".abi.json")).write_text(json.dumps(proof, indent=2) + "\n")
            published.append(library.name)
    print(json.dumps({"built": published, "native_invocations": 0}, sort_keys=True))


if __name__ == "__main__":
    main()
