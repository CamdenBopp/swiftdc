#!/usr/bin/env python3
"""Build independent narrow result signatures and their native callers."""
from pathlib import Path
import subprocess
import tempfile

def run(*args):
    subprocess.run(args, check=True)

def build(level, suffix, module, source, native, flag=None):
    image = "lib" + module + "." + suffix + ".dylib"
    with tempfile.TemporaryDirectory(prefix="narrow-integer-return-") as temporary:
        arguments = ["xcrun", "swiftc", "-" + level, "-parse-as-library",
                     "-emit-library", "-emit-module", "-module-name", module, source,
                     "-emit-module-path", str(Path(temporary) / (module + ".swiftmodule")),
                     "-o", image, "-Xlinker", "-install_name", "-Xlinker", "@rpath/" + image]
        if flag:
            arguments += ["-D", flag]
        run(*arguments)
        run("xcrun", "swiftc", "-" + level, "-I", temporary, "-L.",
            "-l" + module + "." + suffix, native, "-Xlinker", "-rpath",
            "-Xlinker", "@executable_path", "-o", "narrow-integer-return-" + suffix + "-oracle")

for level in ("Onone", "O", "Osize"):
    for result in ("Int8", "Int16", "Int32", "UInt8", "UInt16", "UInt32"):
        build(level, result + "." + level, "NarrowIntegerReturn",
              "narrow_integer_return.swift", "narrow_integer_return_native.swift",
              "NARROW_RETURN_" + result.upper())
    build(level, "Paths." + level, "NarrowIntegerReturnPaths",
          "narrow_integer_return_paths.swift", "narrow_integer_return_paths_native.swift")
    build(level, "Fields." + level, "NarrowIntegerReturnFields",
          "narrow_integer_return_fields.swift", "narrow_integer_return_fields_native.swift")
    build(level, "Tail." + level, "NarrowIntegerReturnTail",
          "narrow_integer_return_tail.swift", "narrow_integer_return_tail_native.swift")
