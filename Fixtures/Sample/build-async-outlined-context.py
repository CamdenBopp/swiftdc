#!/usr/bin/env python3
"""Build own-source outlined async context setup with default compiler options."""
from pathlib import Path
import subprocess
import tempfile
for level in ("Onone", "O", "Osize"):
    module = "AsyncOutlinedContext"
    image = "lib" + module + "." + level + ".dylib"
    with tempfile.TemporaryDirectory(prefix="async-outlined-context-") as temporary:
        subprocess.run([
            "xcrun", "swiftc", "-" + level, "-parse-as-library", "-emit-library", "-emit-module",
            "-module-name", module, "async_outlined_context.swift", "-emit-module-path",
            str(Path(temporary) / (module + ".swiftmodule")), "-o", image,
            "-Xlinker", "-install_name", "-Xlinker", "@rpath/" + image,
        ], check=True)
        subprocess.run([
            "xcrun", "swiftc", "-" + level, "-parse-as-library", "-I", temporary, "-L.",
            "-l" + module + "." + level, "async_outlined_context_native.swift",
            "-Xlinker", "-rpath", "-Xlinker", "@executable_path", "-o",
            "async-outlined-context-" + level + "-oracle",
        ], check=True)
