#!/usr/bin/env python3
"""Build the authored indirect-aggregate caller only after checking its ABI."""
from pathlib import Path
import re
import subprocess
import tempfile

root = Path(__file__).resolve().parent
source = root / "resilient_operator.swift"
for level, module in [("Onone", "ResilientOpOnone"), ("O", "ResilientOp"), ("Osize", "ResilientOpSize")]:
    with tempfile.TemporaryDirectory(prefix="swiftdc-resilient-operator-") as temporary:
        work = Path(temporary)
        common = ["xcrun", "swiftc", "-parse-as-library", "-" + level,
                  "-enable-library-evolution", "-module-name", module]
        ir = work / "operator.ll"
        subprocess.run(common + ["-emit-ir", str(source), "-o", str(ir)], check=True)
        prefix = "$s" + str(len(module)) + module
        definitions = [line for line in ir.read_text().splitlines()
                       if line.startswith("define ") and prefix in line and "1poi" in line]
        if len(definitions) != 1:
            raise RuntimeError("Expected one public operator definition: " + repr(definitions))
        definition = definitions[0]
        match = re.search(r'@"([^\"]+)"\(', definition)
        if match is None:
            raise RuntimeError("Cannot read operator symbol: " + definition)
        symbol = match[1]
        start = match.end()
        depth, end = 1, start
        while depth:
            character = definition[end]
            depth += (character == "(") - (character == ")")
            end += 1
        parameters = definition[start:end - 1]
        parts, depth, last = [], 0, 0
        for index, character in enumerate(parameters):
            if character == "(":
                depth += 1
            elif character == ")":
                depth -= 1
            elif character == "," and depth == 0:
                parts.append(parameters[last:index].strip())
                last = index + 1
        parts.append(parameters[last:].strip())
        if not ("swiftcc i64 " in definition[:match.start()] and len(parts) == 2
                and parts[0].startswith("ptr ") and parts[1].startswith("i64 ")):
            raise RuntimeError("Refusing an assembly caller for an unproved ABI: " + definition)
        wrapper = "_$s" + str(len(module)) + module + "12mixedWrapperSiyF"
        assembly = f""".text
.p2align 2
.globl {wrapper}
{wrapper}:
  sub sp, sp, #48
  stp x19, x20, [sp, #16]
  stp x29, x30, [sp, #32]
  add x29, sp, #32
  bl _resilient_operator_make
  mov x19, x0
  mov x1, #99
  mov x2, #7
  bl _{symbol}
  mov x20, x0
  mov x0, x19
  bl _resilient_operator_destroy
  mov x0, x20
  ldp x29, x30, [sp, #32]
  ldp x19, x20, [sp, #16]
  add sp, sp, #48
  ret
"""
        caller = work / "caller.s"
        caller.write_text(assembly)
        object_file = work / "caller.o"
        subprocess.run(["xcrun", "clang", "-arch", "arm64", "-c", str(caller), "-o", str(object_file)], check=True)
        subprocess.run(common + ["-emit-library", str(source), str(object_file), "-o",
                                 str(root / ("libResilientOperator." + level + ".dylib"))], check=True)
