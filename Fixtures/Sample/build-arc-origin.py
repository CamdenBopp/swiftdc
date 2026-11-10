#!/usr/bin/env python3
"""Build scalar local/imported ARC-name controls; never load a product.

The ordinary C declaration deliberately uses an ARC helper's assembler name.
Verify compiler-emitted C and Swift calling conventions and argument/result
flow before publishing a fixture or allowing its native test to load it.
"""
from pathlib import Path
import argparse
import hashlib
import json
import re
import subprocess
import tempfile
import shutil

ROOT = Path(__file__).resolve().parent / "arc_identity_origin"
LEVELS = (("Onone", "-O0"), ("O", "-O2"), ("Osize", "-Os"))
TARGET = "_swift_nonatomic_retain"
SYMBOL = re.compile(r'@(?:"((?:[^"\\]|\\.)*)"|([-A-Za-z0-9_.$]+))\(')
REG = r'%[-A-Za-z0-9_.$]+'
VALUE = r'(?:' + REG + r'|-?\d+)'


def sha(path):
    with Path(path).open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def retained(path):
    return {"path": str(path.resolve()), "sha256": sha(path)}


def run(argv, directory, label, commands):
    stdout = directory / (label + ".stdout")
    stderr = directory / (label + ".stderr")
    commands.append({"argv": argv, "stdout": str(stdout), "stderr": str(stderr)})
    with stdout.open("w") as out, stderr.open("w") as err:
        subprocess.run(argv, stdout=out, stderr=err, check=True)


def signature(line):
    match = SYMBOL.search(line)
    if not match:
        raise RuntimeError("Unsupported LLVM function/call header: " + line)
    position = match.end()
    start = position
    depth = 1
    while position < len(line) and depth:
        depth += (line[position] == "(") - (line[position] == ")")
        position += 1
    if depth:
        raise RuntimeError("Unbalanced LLVM parameter list")
    parameters = []
    begin = start
    nested = 0
    for index in range(start, position - 1):
        character = line[index]
        nested += (character in "([{<") - (character in ")]}>" )
        if character == "," and nested == 0:
            parameters.append(line[begin:index].strip())
            begin = index + 1
    if line[begin:position - 1].strip():
        parameters.append(line[begin:position - 1].strip())
    return match.group(1) or match.group(2), line[:match.start()], parameters


def mach_symbol(llvm_symbol):
    # LLVM's \01 suppresses the target's ordinary leading underscore.
    return llvm_symbol[3:] if llvm_symbol.startswith("\\01") else "_" + llvm_symbol


def abi(line, convention):
    symbol, prefix, parameters = signature(line)
    if not re.search(r'\bi64\s*$', prefix):
        raise RuntimeError("Unproved i64 return ABI: " + line)
    cc = re.findall(r'\b(?:cc\s+\d+|[A-Za-z_]+cc)\b', prefix)
    if not (cc == ["swiftcc"] if convention == "swift" else cc in ([], ["ccc"])):
        raise RuntimeError("Unproved calling convention: " + line)
    if len(parameters) != 2 or any(not re.match(r'^i64(?:\s|$)', p) for p in parameters):
        raise RuntimeError("Unproved two-i64/hidden-argument ABI: " + line)
    if any(re.search(r'\b(?:swiftself|swifterror|sret|byval|inalloca)\b', p) for p in parameters):
        raise RuntimeError("Unexpected special ABI parameter: " + line)
    return {"llvm_symbol": symbol, "mach_symbol": mach_symbol(symbol),
            "header_or_call": line, "calling_convention": convention,
            "return_type": "i64", "parameter_types": ["i64", "i64"]}


def ir_functions(text):
    result = []
    lines = text.splitlines()
    index = 0
    while index < len(lines):
        line = lines[index]
        if not line.startswith(("define ", "declare ")):
            index += 1
            continue
        symbol = signature(line)[0]
        body = []
        if line.startswith("define "):
            index += 1
            while index < len(lines) and lines[index] != "}":
                body.append(lines[index])
                index += 1
            if index == len(lines):
                raise RuntimeError("Unclosed LLVM definition")
        result.append({"symbol": symbol, "header": line, "body": body})
        index += 1
    return result


def exact(functions, predicate, description):
    matches = [f for f in functions if predicate(f)]
    if len(matches) != 1:
        raise RuntimeError("Expected exactly one " + description + ": " + repr(matches))
    return matches[0]


def parameter_registers(header):
    result = []
    for parameter in signature(header)[2]:
        matches = re.findall(REG, parameter)
        if len(matches) != 1:
            raise RuntimeError("Unsupported formal operand: " + parameter)
        result.append(matches[0])
    return result


def require_forwarded_call(function, callee, convention):
    lines = [line.strip() for line in function["body"]]
    calls = [line for line in lines if re.search(r'\bcall\b', line) and SYMBOL.search(line)]
    actual = [line for line in calls if signature(line)[0] == callee]
    if len(actual) != 1:
        raise RuntimeError("Required exact surviving call absent or duplicated")
    proof = abi(actual[0], convention)
    operands = []
    for parameter in signature(actual[0])[2]:
        matches = re.findall(REG, parameter)
        if len(matches) != 1:
            raise RuntimeError("Unsupported forwarded argument: " + parameter)
        operands.append(matches[0])
    if operands != parameter_registers(function["header"]):
        raise RuntimeError("Actual call does not directly forward both scalar formals")
    assignment = re.match(r'(' + REG + r')\s*=\s*', actual[0])
    returns = [line for line in lines if line.startswith("ret ")]
    if not assignment or returns != ["ret i64 " + assignment[1]]:
        raise RuntimeError("Caller does not return the actual surviving call result")
    extra_calls = [line for line in calls if line != actual[0]
                   and not signature(line)[0].startswith("llvm.")]
    if extra_calls:
        raise RuntimeError("Unexpected non-intrinsic calls in scalar caller: " + repr(extra_calls))
    proof["body"] = function["body"]
    proof["formals_forwarded_in_order"] = True
    proof["returns_actual_call_result"] = True
    return proof


def require_second_plus_17(function):
    """Reject unsupported C IR; prove actual straight-line return, including O0 spills."""
    formals = parameter_registers(function["header"])
    values = {name: ("arg", index) for index, name in enumerate(formals)}
    memory = {}
    returned = []

    def value(token):
        return values[token] if token.startswith("%") else int(token)

    for raw in function["body"]:
        line = raw.strip()
        if not line or line.startswith(";") or re.match(r'^[-A-Za-z0-9_.$]+:', line):
            continue
        if re.match(r'^' + REG + r' = alloca i64(?:,|\s)', line):
            continue
        store = re.match(r'^store i64 (' + VALUE + r'), ptr (' + REG + r')(?:,|$)', line)
        load = re.match(r'^(' + REG + r') = load i64, ptr (' + REG + r')(?:,|$)', line)
        add = re.match(r'^(' + REG + r') = add(?: nsw| nuw)* i64 (' + VALUE + r'), (' + VALUE + r')$', line)
        ret = re.match(r'^ret i64 (' + VALUE + r')$', line)
        if store:
            memory[store[2]] = value(store[1])
        elif load:
            values[load[1]] = memory[load[2]]
        elif add:
            values[add[1]] = ("add", value(add[2]), value(add[3]))
        elif ret:
            returned.append(value(ret[1]))
        else:
            raise RuntimeError("Unsupported/unproved C return-body instruction: " + line)
    if returned not in [[("add", ("arg", 1), 17)], [("add", 17, ("arg", 1))]]:
        raise RuntimeError("C body is not proved to return second + 17: " + repr(returned))
    return {"actual_return_expression": "second + 17", "body": function["body"],
            "expected_at_7_99": 116, "first_argument_is_not_the_result": True}


def require_arm64_macos(text):
    match = re.search(r'^target triple = "([^"]+)"', text, re.MULTILINE)
    if not match or not match[1].startswith("arm64-apple-macosx"):
        raise RuntimeError("Only an actual arm64 macOS compiler output is supported")
    return match[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-directory", type=Path, default=ROOT.parent)
    options = parser.parse_args()
    output = options.output_directory.resolve()
    output.mkdir(parents=True, exist_ok=True)
    published = []
    with tempfile.TemporaryDirectory(prefix="arc-origin-", dir=output) as temporary:
        workroot = Path(temporary)
        commands = []
        for level, copt in LEVELS:
            for case in ["local", "import"]:
                local = case == "local"
                work = workroot / level / case
                work.mkdir(parents=True)
                ccommon = ["xcrun", "clang", copt, "-fPIC", "-fno-lto", "-I", str(ROOT / "include"),
                           "-DARC_ORIGIN_LOCAL=" + str(int(local))]
                cir, obj = work / "provider.ll", work / "provider.o"
                run(ccommon + ["-S", "-emit-llvm", str(ROOT / "foreign.c"), "-o", str(cir)], work, "C-ir", commands)
                ctriple = require_arm64_macos(cir.read_text())
                ctarget = exact(ir_functions(cir.read_text()), lambda f: mach_symbol(f["symbol"]) == TARGET
                                and f["header"].startswith("define "), "asm-labeled C definition")
                cproof = abi(ctarget["header"], "C")
                cproof["return_semantics"] = require_second_plus_17(ctarget)
                if local != bool(re.search(r"\bhidden\b", ctarget["header"])):
                    raise RuntimeError("C definition visibility disagrees with the case")
                run(ccommon + ["-c", str(ROOT / "foreign.c"), "-o", str(obj)], work, "C-object", commands)
                provider = None
                if not local:
                    provider = work / ("libArcOriginProvider." + level + ".dylib")
                    exports = work / "provider.exports"
                    exports.write_text(TARGET + "\n")
                    run(["xcrun", "clang", "-dynamiclib", str(obj), "-o", str(provider),
                         "-Xlinker", "-twolevel_namespace", "-Xlinker", "-install_name", "-Xlinker", "@rpath/" + provider.name,
                         "-Xlinker", "-exported_symbols_list", "-Xlinker", str(exports)], work, "C-provider", commands)
                module = "ArcOrigin" + ("Local" if local else "Import") + level
                swift = ROOT / ("local.swift" if local else "imported.swift")
                scommon = ["xcrun", "swiftc", "-parse-as-library", "-" + level, "-module-name", module,
                           "-I", str(ROOT / "include"), "-module-cache-path", str(work / "module-cache"),
                           "-Xcc", "-DARC_ORIGIN_LOCAL=" + str(int(local))]
                sir = work / "client.ll"
                run(scommon + ["-emit-ir", str(swift), "-o", str(sir)], work, "Swift-ir", commands)
                striple = require_arm64_macos(sir.read_text())
                functions = ir_functions(sir.read_text())
                foreign = exact(functions, lambda f: mach_symbol(f["symbol"]) == TARGET, "Clang-imported C declaration")
                foreign_proof = abi(foreign["header"], "C")
                if not foreign["header"].startswith("declare "):
                    raise RuntimeError("Unexpected Swift implementation of the false runtime target")
                entry_name = "arc_origin_" + case + "_probe"
                entry = exact(functions, lambda f: f["symbol"] == entry_name and f["header"].startswith("define "), "C export")
                entry_proof = abi(entry["header"], "C")
                body_calls = [line.strip() for line in entry["body"] if re.search(r"\bcall\b", line)
                              and SYMBOL.search(line) and signature(line)[0].startswith("$s")]
                if len(body_calls) != 1:
                    raise RuntimeError("C export does not retain one Swift body call")
                body_symbol = signature(body_calls[0])[0]
                body = exact(functions, lambda f: f["symbol"] == body_symbol, "Swift body")
                body_proof = abi(body["header"], "swift")
                entry_chain = require_forwarded_call(entry, body_symbol, "swift")
                foreign_chain = require_forwarded_call(body, foreign["symbol"], "C")
                calls = [line for line in sir.read_text().splitlines() if re.search(r"\bcall\b", line)
                         and SYMBOL.search(line) and mach_symbol(signature(line)[0]) == TARGET]
                if len(calls) != 1:
                    raise RuntimeError("Unexpected additional Swift callers of the false target")
                exports = work / "client.exports"
                exports.write_text("_" + entry_name + "\n")
                library = work / ("libArcOrigin" + case.title() + "." + level + ".dylib")
                run(scommon + ["-emit-library", str(swift), str(obj if local else provider), "-o", str(library),
                    "-Xlinker", "-twolevel_namespace", "-Xlinker", "-exported_symbols_list", "-Xlinker", str(exports),
                    "-Xlinker", "-rpath", "-Xlinker", "@loader_path", "-Xlinker", "-install_name",
                    "-Xlinker", "@rpath/" + library.name], work, "Swift-client", commands)
                proof = {"schema": 1, "case": case, "level": level, "compiler_ABI_verified": True,
                    "entry_symbol": entry_name, "expected_arguments": [7, 99], "expected_result": 116,
                    "library_file": library.name, "library_sha256": sha(library),
                    "C_target": cproof, "Clang_import": foreign_proof, "C_entry": entry_proof,
                    "Swift_body": body_proof, "C_entry_to_Swift_body": entry_chain,
                    "Swift_body_to_C_target": foreign_chain, "C_target_triple": ctriple, "Swift_target_triple": striple,
                    "C_IR": cir.read_text(), "Swift_IR": sir.read_text()}
                if provider:
                    proof["provider_file"] = provider.name
                    proof["provider_sha256"] = sha(provider)
                    shutil.copy2(provider, output / provider.name)
                shutil.copy2(library, output / library.name)
                (output / (library.name + ".abi.json")).write_text(json.dumps(proof, indent=2) + "\n")
                published.append(library.name)
    print(json.dumps({"built": published, "native_invocations": 0}, sort_keys=True))


if __name__ == "__main__":
    main()
