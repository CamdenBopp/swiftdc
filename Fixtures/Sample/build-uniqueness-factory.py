#!/usr/bin/env python3
"""Build authored uniqueness-query callers after proving the called ABIs.

The default installs fixture dylibs and ABI evidence. --build-to retains IR and
assembly for independent inspection. This builder never invokes native code.
"""
from pathlib import Path
import argparse
import hashlib
import json
import re
import subprocess
import shutil
import tempfile

ROOT = Path(__file__).resolve().parent
LEVELS = [("Onone", "FactorySnapshotOnone"),
          ("O", "FactorySnapshot"), ("Osize", "FactorySnapshotSize")]
WRAPPERS = {"immediate": "immediateWrapper", "shallow": "shallowWrapper", "deep": "deepWrapper",
            "operand_delayed": "operandDelayedWrapper",
            "deep_without_mark": "deepWithoutMarkWrapper", "unused_query": "unusedQueryWrapper"}


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def run(command, log):
    with log.open("w") as output, log.with_suffix(log.suffix + ".stderr").open("w") as error:
        subprocess.run(command, stdout=output, stderr=error, check=True)


def signature(line):
    """Read a single LLVM definition/declaration; balance attribute parentheses."""
    match = re.search(r'@(?:"([^"\\]+)"|([A-Za-z0-9_.$]+))\(', line)
    if match is None:
        raise RuntimeError("Cannot parse LLVM function header: " + line)
    start = match.end()
    depth = 1
    end = start
    while end < len(line) and depth:
        depth += (line[end] == "(") - (line[end] == ")")
        end += 1
    if depth:
        raise RuntimeError("Unbalanced LLVM function header: " + line)
    text = line[start:end - 1]
    parts = []
    depth = 0
    last = 0
    for index, character in enumerate(text):
        depth += (character == "(") - (character == ")")
        if character == "," and depth == 0:
            parts.append(text[last:index].strip())
            last = index + 1
    if text.strip():
        parts.append(text[last:].strip())
    return match.group(1) or match.group(2), line[:match.start()], parts


def check_abi(line, return_type, parameter_types, swift):
    name, prefix, parameters = signature(line)
    if not re.search(r"\b" + return_type + r"\s*$", prefix):
        raise RuntimeError("Unproved return ABI: " + line)
    conventions = re.findall(r"\b(?:swiftcc|fastcc|coldcc|tailcc|cc\s+\d+|[A-Za-z_]+cc)\b", prefix)
    wanted = ["swiftcc"] if swift else []
    if conventions != wanted and not (not swift and conventions == ["ccc"]):
        raise RuntimeError("Unproved calling convention: " + line)
    if len(parameters) != len(parameter_types) or any(
        not re.match(r"^" + ty + r"(?:\s|$)", part)
        for part, ty in zip(parameters, parameter_types)
    ):
        raise RuntimeError("Unproved parameter/hidden-argument ABI: " + line)
    return {"symbol": name, "llvm_header": line, "return_type": return_type,
            "parameter_types": parameter_types, "swiftcc": swift}


def headers(ir):
    return [line for line in ir.splitlines() if line.startswith(("define ", "declare "))]


def exact_header(lines, symbol):
    matches = [line for line in lines if signature(line)[0] == symbol]
    if len(matches) != 1:
        raise RuntimeError("Expected exactly one LLVM header for " + symbol + ": " + repr(matches))
    return matches[0]


def wrapper_symbol(module, name):
    return "$s" + str(len(module)) + module + str(len(name)) + name + "SiyF"


def build(output):
    output = output.resolve()
    output.mkdir(exist_ok=False, parents=True)
    manifest = {"status": "building-not-qualified", "input_hashes": {
        name: sha(ROOT / name) for name in ("uniqueness_factory.swift", "uniqueness_factory_abi.swift", "build-uniqueness-factory.py")
    }, "runtime_not_invoked": True, "levels": {}}
    (output / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")

    # This checks the actual Swift runtime import, rather than guessing a private ABI.
    runtime_ir_path = output / "runtime-abi.ll"
    run(["xcrun", "swiftc", "-parse-as-library", "-O", "-module-name", "QueryRuntimeABIProbe",
         "-emit-ir", str(ROOT / "uniqueness_factory_abi.swift"), "-o", str(runtime_ir_path)], output / "runtime-abi.compile.stdout")
    runtime_ir = runtime_ir_path.read_text()
    if not re.search(r'^target triple = "arm64-apple-macosx', runtime_ir, re.MULTILINE):
        raise RuntimeError("Authored assembly requires proven arm64 Apple macOS target")
    runtime_symbol = "swift_isUniquelyReferenced_nonNull_native"
    runtime_header = exact_header(headers(runtime_ir), runtime_symbol)
    runtime_proof = check_abi(runtime_header, "i1", ["ptr"], swift=False)
    runtime_calls = [line for line in runtime_ir.splitlines()
                     if re.search(r'\bcall\b', line) and re.search(r'@"?' + runtime_symbol + r'"?\(', line)]
    if not runtime_calls:
        raise RuntimeError("Runtime query did not survive in compiler oracle")
    runtime_proof["surviving_calls"] = runtime_calls
    manifest["runtime_abi_proof"] = runtime_proof

    for level, module in LEVELS:
        work = output / level
        work.mkdir()
        symbols = {key: wrapper_symbol(module, name) for key, name in WRAPPERS.items()}
        declarations = []
        for key, symbol in symbols.items():
            declarations.append(f'@_silgen_name("{symbol}")\npublic func assembly_{key}_entry() -> Int\n')
            declarations.append(
                f'@_cdecl("query_factory_{key}_oracle")\n@_optimize(none) @inline(never)\n'
                f'public func {key}Oracle() -> Int {{ assembly_{key}_entry() }}\n')
        source = work / "combined.swift"
        source.write_text((ROOT / "uniqueness_factory.swift").read_text() + "\n" + "\n".join(declarations))
        common = ["xcrun", "swiftc", "-parse-as-library", "-" + level, "-module-name", module]
        ir_path = work / "providers.ll"
        run(common + ["-emit-ir", str(source), "-o", str(ir_path)], work / "providers-ir.compile.stdout")
        ir = ir_path.read_text()
        lines = headers(ir)
        swift_definitions = [(signature(line)[0], line) for line in lines
                             if line.startswith("define ") and signature(line)[0].startswith("$s")]
        demangle_path = work / "swift-definitions.demangled"
        run(["xcrun", "swift-demangle", "--compact"] + [name for name, _ in swift_definitions], demangle_path)
        demangled = demangle_path.read_text().splitlines()
        if len(demangled) != len(swift_definitions):
            raise RuntimeError("Unexpected swift-demangle output shape")
        by_description = {}
        for (name, line), description in zip(swift_definitions, demangled):
            by_description.setdefault(description, []).append((name, line))
        wanted_functions = {"factory": ("createFactoryObject", [], "Swift.UnsafeMutableRawPointer", "ptr")}
        wanted_functions.update({"layer" + str(n): ("factoryLayer" + str(n), ["i64"], "Swift.Int", "i64")
                                 for n in range(1, 8)})
        call_proofs = {}
        for key, (name, params, swift_return, llvm_return) in wanted_functions.items():
            argument = "Swift.Int" if params else ""
            description = f"{module}.{name}({argument}) -> {swift_return}"
            matches = by_description.get(description, [])
            if len(matches) != 1:
                raise RuntimeError("Cannot uniquely resolve exact Swift declaration: " + description)
            symbol, line = matches[0]
            call_proofs[key] = check_abi(line, llvm_return, params, swift=True)
            call_proofs[key]["demangled"] = description
        call_proofs["mark"] = check_abi(exact_header(lines, "query_factory_mark"), "void", [], swift=False)
        for c_symbol, returns in [("query_factory_reset", "void"), ("query_factory_creation_count", "i64"),
                                  ("query_factory_mark_count", "i64"), ("query_factory_creations_at_mark", "i64"),
                                  ("query_factory_destroy_last", "void")]:
            call_proofs[c_symbol] = check_abi(exact_header(lines, c_symbol), returns, [], swift=False)
        for key, symbol in symbols.items():
            call_proofs[key + "_entry"] = check_abi(exact_header(lines, symbol), "i64", [], swift=True)
            demangle_entry = work / (key + ".demangled")
            run(["xcrun", "swift-demangle", "--compact", symbol], demangle_entry)
            if demangle_entry.read_text().strip() != f"{module}.{WRAPPERS[key]}() -> Swift.Int":
                raise RuntimeError("Authored wrapper mangling not independently confirmed")
            call_proofs[key + "_oracle"] = check_abi(
                exact_header(lines, "query_factory_" + key + "_oracle"), "i64", [], swift=False)

        # ABI proof above is a hard precondition to writing any assembly caller.
        assembly = [".text", ".p2align 2"]
        expected_chains = {}
        for key, symbol in symbols.items():
            factory = call_proofs["factory"]["symbol"]
            chain = [factory]
            assembly += [".p2align 2", ".globl _" + symbol, "_" + symbol + ":",
                         "  stp x29, x30, [sp, #-32]!", "  stp x19, x20, [sp, #16]",
                         "  mov x29, sp", "  bl _" + factory]
            if key == "operand_delayed":
                assembly += ["  mov x19, x0", "  bl _query_factory_mark", "  mov x0, x19",
                             "  bl _" + runtime_symbol, "  and x0, x0, #1"]
                chain += ["query_factory_mark", runtime_symbol]
            else:
                assembly += ["  bl _" + runtime_symbol]
                chain.append(runtime_symbol)
                if key == "immediate":
                    assembly += ["  and x0, x0, #1"]
                elif key == "unused_query":
                    # The predicate is unused, but creating its object is an
                    # observable effect and must remain in rendered output.
                    assembly += ["  mov x0, #73"]
                else:
                    if key == "deep_without_mark":
                        # Nothing forces a query binding: its nested expression
                        # can hit the renderer depth bound. The factory must
                        # still run exactly once at its original instruction.
                        assembly += ["  and x0, x0, #1"]
                    else:
                        assembly += ["  and x20, x0, #1", "  bl _query_factory_mark", "  mov x0, x20"]
                        chain.append("query_factory_mark")
                    for n in range(1, 2 if key == "shallow" else 8):
                        layer = call_proofs["layer" + str(n)]["symbol"]
                        assembly.append("  bl _" + layer)
                        chain.append(layer)
            assembly += ["  ldp x19, x20, [sp, #16]", "  ldp x29, x30, [sp], #32", "  ret"]
            expected_chains[key] = chain
        assembly_path = work / "wrappers.s"
        assembly_path.write_text("\n".join(assembly) + "\n")
        object_path = work / "wrappers.o"
        run(["xcrun", "clang", "-arch", "arm64", "-c", str(assembly_path), "-o", str(object_path)], work / "assembly.compile.stdout")
        library = work / ("libFactorySnapshot." + level + ".dylib")
        run(common + ["-emit-library", str(source), str(object_path), "-o", str(library)], work / "library.compile.stdout")
        proof = {"module": module, "level": level, "calls": call_proofs,
                 "wrapper_symbols": symbols, "required_surviving_call_chains": expected_chains,
                 "source_sha256": sha(source), "ir_sha256": sha(ir_path), "assembly_sha256": sha(assembly_path),
                 "library_sha256": sha(library),
                 "qualification": "built-only; raw instructions and call chains MUST be inspected before native invocation"}
        (work / "abi-proof.json").write_text(json.dumps(proof, indent=2) + "\n")
        manifest["levels"][level] = proof
        (output / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    manifest["status"] = "built-only-not-qualified-native-not-invoked"
    (output / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--build-to", type=Path,
                        help="Retain all evidence in a fresh output directory")
    options = parser.parse_args()
    if options.build_to is not None:
        build(options.build_to)
        return
    with tempfile.TemporaryDirectory(prefix="swiftdc-uniqueness-factory-") as temporary:
        products = Path(temporary) / "products"
        build(products)
        for level, _ in LEVELS:
            name = "libFactorySnapshot." + level + ".dylib"
            shutil.copy2(products / level / name, ROOT / name)
            # Keep the exact emitted evidence beside the installed library so
            # a fresh fixture build can be inspected before native execution.
            proof = json.loads((products / level / "abi-proof.json").read_text())
            proof["provider_ir"] = (products / level / "providers.ll").read_text()
            proof["runtime_ir"] = (products / "runtime-abi.ll").read_text()
            proof["runtime_abi_proof"] = json.loads((products / "manifest.json").read_text())["runtime_abi_proof"]
            proof["assembly"] = (products / level / "wrappers.s").read_text()
            (ROOT / ("libFactorySnapshot." + level + ".abi.json")).write_text(json.dumps(proof, indent=2) + "\n")


if __name__ == "__main__":
    main()
