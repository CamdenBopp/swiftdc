#!/usr/bin/env python3
"""Build own-source receiver/type-list alignment and its native value oracle."""
from pathlib import Path
import subprocess
import tempfile

for level in ("Onone", "O", "Osize"):
    module = "SwiftReceiverTypeList"
    image = "lib" + module + "." + level + ".dylib"
    with tempfile.TemporaryDirectory(prefix="swift-receiver-types-") as temporary:
        subprocess.run([
            "xcrun", "swiftc", "-" + level, "-parse-as-library", "-emit-library", "-emit-module",
            "-module-name", module, "swift_receiver_type_list.swift", "-emit-module-path",
            str(Path(temporary) / (module + ".swiftmodule")), "-o", image,
            "-Xlinker", "-install_name", "-Xlinker", "@rpath/" + image,
        ], check=True)
        subprocess.run([
            "xcrun", "swiftc", "-" + level, "-I", temporary, "-L.", "-l" + module + "." + level,
            "swift_receiver_type_list_native.swift", "-Xlinker", "-rpath", "-Xlinker", "@executable_path",
            "-o", "narrow-integer-return-" + module + "." + level + "-oracle",
        ], check=True)
