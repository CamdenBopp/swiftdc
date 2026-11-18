#!/usr/bin/env python3
"""Keep each Swift lowering and its native oracle together."""
from pathlib import Path
import subprocess
import tempfile

def run(*args):
    subprocess.run(args, check=True)

for level in ("Onone", "O", "Osize"):
    with tempfile.TemporaryDirectory(prefix="c-narrow-arguments-") as temporary:
        module = str(Path(temporary) / "CNarrowArguments.swiftmodule")
        image = "libCNarrowArguments." + level + ".dylib"
        run("xcrun", "swiftc", "-" + level, "-parse-as-library", "-emit-library", "-emit-module",
            "-module-name", "CNarrowArguments", "c_narrow_arguments.swift",
            "-emit-module-path", module, "-o", image,
            "-Xlinker", "-install_name", "-Xlinker", "@rpath/" + image)
        run("xcrun", "swiftc", "-" + level, "-I", temporary, "-L.",
            "-lCNarrowArguments." + level, "c_narrow_arguments_native.swift",
            "-Xlinker", "-rpath", "-Xlinker", "@executable_path",
            "-o", "c-narrow-arguments-" + level + "-oracle")
