#!/usr/bin/env python3
"""Own-source Swift error ABI under raw names, with a real system C control."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parent

def run(*args):
    subprocess.run(args, cwd=root, check=True)

with tempfile.TemporaryDirectory(prefix=".plain-error-abi-", dir=root) as temp:
    modules = Path(temp)
    run("xcrun", "clang", "-arch", "arm64", "-c", "plain_error_system.s",
        "-o", str(modules / "system.o"))
    for level, option in [("Onone", "-Onone"), ("O", "-O"), ("Osize", "-Osize")]:
        provider = f"libPlainErrorProvider.{level}.dylib"
        caller = f"libPlainErrorABI.{level}.dylib"
        system = f"libPlainErrorSystem.{level}.dylib"
        native = f"plain-error-abi-{level}-oracle"
        print(f"==> plain-name Swift errors and system C control ({level})", flush=True)
        run("xcrun", "swiftc", option, "-parse-as-library", "-emit-library",
            "-module-name", "PlainErrorProvider", "plain_error_provider.swift",
            "-Xlinker", "-install_name", "-Xlinker", "@rpath/" + provider, "-o", provider)
        run("xcrun", "swiftc", option, "-parse-as-library", "-emit-library", "-emit-module",
            "-module-name", "PlainErrorABI", "plain_error_calls.swift",
            "-emit-module-path", str(modules / "PlainErrorABI.swiftmodule"),
            "-L", ".", "-lPlainErrorProvider." + level,
            "-Xlinker", "-install_name", "-Xlinker", "@rpath/" + caller,
            "-Xlinker", "-rpath", "-Xlinker", "@loader_path", "-o", caller)
        # No custom provider is linked here: the identical getpid spelling
        # must resolve to libSystem in this image.
        run("xcrun", "swiftc", option, "-parse-as-library", "-emit-library", "-emit-module",
            "-module-name", "PlainErrorSystem", "plain_error_system.swift", str(modules / "system.o"),
            "-emit-module-path", str(modules / "PlainErrorSystem.swiftmodule"),
            "-Xlinker", "-install_name", "-Xlinker", "@rpath/" + system, "-o", system)
        for source, module, role in [("plain_error_provider.swift", "PlainErrorProvider", "provider"),
                                     ("plain_error_calls.swift", "PlainErrorABI", "caller")]:
            run("xcrun", "swiftc", option, "-parse-as-library", "-emit-ir", "-module-name", module,
                source, "-o", f"plain-error-abi-{level}-{role}.ll")
        for library in [caller, system]:
            stripped = library.removesuffix(".dylib") + ".stripped.dylib"
            run("cp", library, stripped)
            run("strip", "-x", stripped)
        run("xcrun", "swiftc", option, "plain_error_native.swift", "-I", str(modules), "-L", ".",
            "-lPlainErrorABI." + level, "-lPlainErrorSystem." + level,
            "-lPlainErrorProvider." + level, "-Xlinker", "-rpath", "-Xlinker", "@executable_path",
            "-o", native)
        run(str(root / native))
