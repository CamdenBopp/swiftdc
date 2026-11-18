#!/usr/bin/env python3
"""Own-source foreign SDK spellings with GP/FP/error ABIs and real C controls."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parent

def run(*args):
    subprocess.run(args, cwd=root, check=True)

with tempfile.TemporaryDirectory(prefix=".named-abi-contracts-", dir=root) as directory:
    temporary = Path(directory)
    for source, name in [("named_abi_indirect.s", "foreign"), ("named_abi_system_indirect.s", "system")]:
        run("xcrun", "clang", "-arch", "arm64", "-mmacosx-version-min=15.0", "-c", source,
            "-o", str(temporary / (name + ".o")))
    for level, swift_option, c_option in [("Onone", "-Onone", "-O0"), ("O", "-O", "-O2"), ("Osize", "-Osize", "-Os")]:
        provider = f"libNamedABIProvider.{level}.dylib"
        client = f"libNamedABIClient.{level}.dylib"
        system = f"libNamedABISystem.{level}.dylib"
        native = f"named-abi-{level}-oracle"
        print(f"==> named ABI provider/client and real C contracts ({level})", flush=True)
        run("xcrun", "swiftc", swift_option, "-target", "arm64-apple-macosx15.0", "-parse-as-library", "-emit-library", "-module-name", "NamedABIProvider",
            "named_abi_provider.swift", "-Xlinker", "-install_name", "-Xlinker", "@rpath/" + provider, "-o", provider)
        run("xcrun", "swiftc", swift_option, "-target", "arm64-apple-macosx15.0", "-parse-as-library", "-emit-library", "-module-name", "NamedABIClient",
            "named_abi_calls.swift", str(temporary / "foreign.o"), "-L", ".", "-lNamedABIProvider." + level,
            "-Xlinker", "-install_name", "-Xlinker", "@rpath/" + client,
            "-Xlinker", "-rpath", "-Xlinker", "@loader_path", "-o", client)
        run("xcrun", "clang", "-arch", "arm64", "-mmacosx-version-min=15.0", c_option, "-dynamiclib",
            "named_abi_system.c", str(temporary / "system.o"), "-framework", "CoreGraphics",
            "-Wl,-install_name,@rpath/" + system, "-o", system)
        for source, module, role in [("named_abi_provider.swift", "NamedABIProvider", "provider"),
                                     ("named_abi_calls.swift", "NamedABIClient", "client")]:
            run("xcrun", "swiftc", swift_option, "-target", "arm64-apple-macosx15.0", "-parse-as-library", "-emit-ir", "-module-name", module,
                source, "-o", f"named-abi-{level}-{role}.ll")
        run("xcrun", "clang", "-arch", "arm64", "-mmacosx-version-min=15.0", c_option, "-S", "-emit-llvm",
            "named_abi_system.c", "-o", f"named-abi-{level}-system.ll")
        for library in [client, system]:
            stripped = library.removesuffix(".dylib") + ".stripped.dylib"
            run("cp", library, stripped)
            run("strip", "-x", stripped)
        # The native executable never links the provider directly. Its SDK
        # stdio bindings must not resolve to the foreign printf definition.
        run("xcrun", "clang", "-arch", "arm64", "-mmacosx-version-min=15.0", c_option,
            "named_abi_native.c", "-L", ".", "-lNamedABIClient." + level, "-lNamedABISystem." + level,
            "-Wl,-rpath,@executable_path", "-o", native)
        run(str(root / native))
