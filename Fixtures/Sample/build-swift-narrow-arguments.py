#!/usr/bin/env python3
"""Build own-source scalar argument boundaries and independent native drivers."""
from pathlib import Path
import subprocess
import tempfile

for level in ("Onone", "O", "Osize"):
    provider = "ArgumentOpaqueProvider." + level
    subprocess.run([
        "xcrun", "clang", "-arch", "arm64", "-O2", "-dynamiclib",
        "swift_narrow_argument_provider.c", "-o", "lib" + provider + ".dylib",
        "-Wl,-install_name,@rpath/lib" + provider + ".dylib",
    ], check=True)
    for module, stem in (
        ("SwiftArgumentBoundary", "swift_narrow_arguments"),
        ("SwiftArgumentRoles", "swift_narrow_argument_roles"),
        ("SwiftArgumentOpaque", "swift_narrow_argument_opaque"),
    ):
        image = "lib" + module + "." + level + ".dylib"
        links = ["-L.", "-l" + provider] if module == "SwiftArgumentOpaque" else []
        with tempfile.TemporaryDirectory(prefix="swift-narrow-argument-") as temporary:
            subprocess.run([
                "xcrun", "swiftc", "-" + level, "-parse-as-library", "-emit-library",
                "-emit-module", "-module-name", module, stem + ".swift",
                "-emit-module-path", str(Path(temporary) / (module + ".swiftmodule")),
                "-o", image, "-Xlinker", "-install_name", "-Xlinker", "@rpath/" + image,
                "-Xlinker", "-rpath", "-Xlinker", "@loader_path", *links,
            ], check=True)
            subprocess.run([
                "xcrun", "swiftc", "-" + level, "-I", temporary, "-L.",
                "-l" + module + "." + level, stem + "_native.swift", *links,
                "-Xlinker", "-rpath", "-Xlinker", "@executable_path", "-o",
                "narrow-integer-return-" + module + "." + level + "-oracle",
            ], check=True)
