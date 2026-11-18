#!/usr/bin/env python3
"""Build distinct Swift tail-result entries and independent native callers."""
from pathlib import Path
import subprocess
import tempfile

for level in ("Onone", "O", "Osize"):
    for module, stem, suffix in (
        ("SwiftTailResults", "swift_integer_tail_results", "TailResults"),
        ("SwiftTailGetters", "swift_integer_tail_getters", "TailGetters"),
    ):
        image = "lib" + module + "." + level + ".dylib"
        with tempfile.TemporaryDirectory(prefix="swift-integer-tail-") as temporary:
            subprocess.run([
                "xcrun", "swiftc", "-" + level, "-parse-as-library", "-emit-library",
                "-emit-module", "-module-name", module, stem + ".swift",
                "-emit-module-path", str(Path(temporary) / (module + ".swiftmodule")),
                "-o", image, "-Xlinker", "-install_name", "-Xlinker", "@rpath/" + image,
            ], check=True)
            subprocess.run([
                "xcrun", "swiftc", "-" + level, "-I", temporary, "-L.",
                "-l" + module + "." + level, stem + "_native.swift",
                "-Xlinker", "-rpath", "-Xlinker", "@executable_path", "-o",
                "narrow-integer-return-" + suffix + "." + level + "-oracle",
            ], check=True)
