#!/usr/bin/env python3
"""Foreign Swift sret versus bound SDK direct results, including GOT calls."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parent

def run(*args):
    subprocess.run(args, cwd=root, check=True)

with tempfile.TemporaryDirectory(prefix=".named-buffer-", dir=root) as directory:
    temporary = Path(directory)
    for kind in ["provider", "foreign", "system"]:
        run("xcrun", "clang", "-arch", "arm64", "-mmacosx-version-min=15.0", "-c",
            f"named_buffer_{kind}.s", "-o", str(temporary / (kind + ".o")))
    for level, swift_option, c_option in [("Onone", "-Onone", "-O0"), ("O", "-O", "-O2"), ("Osize", "-Osize", "-Os")]:
        provider = f"libNamedBufferProvider.{level}.dylib"
        client = f"libNamedBufferClient.{level}.dylib"
        system = f"libNamedBufferSystem.{level}.dylib"
        print(f"==> bound and foreign named result-buffer contracts ({level})", flush=True)
        common = [swift_option, "-target", "arm64-apple-macosx15.0", "-parse-as-library"]
        run("xcrun", "swiftc", *common, "-emit-library", "-module-name", "BufferProvider",
            "named_buffer_provider.swift", str(temporary / "provider.o"), "-Xlinker", "-install_name", "-Xlinker", "@rpath/" + provider, "-o", provider)
        for kind, module, library, extra in [
            ("foreign", "BufferClient", client, ["-L", ".", "-lNamedBufferProvider." + level]),
            ("system", "BufferSystem", system, ["-D", "BUFFER_SYSTEM"]),
        ]:
            run("xcrun", "swiftc", *common, "-emit-library", "-module-name", module,
                "named_buffer_client.swift", str(temporary / (kind + ".o")), *extra,
                "-Xlinker", "-install_name", "-Xlinker", "@rpath/" + library,
                "-Xlinker", "-rpath", "-Xlinker", "@loader_path", "-o", library)
            stripped = library.removesuffix(".dylib") + ".stripped.dylib"
            run("cp", library, stripped)
            run("strip", "-x", stripped)
        for source, module, role, extra in [
            ("named_buffer_provider.swift", "BufferProvider", "provider", []),
            ("named_buffer_client.swift", "BufferClient", "client", []),
            ("named_buffer_client.swift", "BufferSystem", "system", ["-D", "BUFFER_SYSTEM"]),
        ]:
            run("xcrun", "swiftc", *common, "-emit-ir", "-module-name", module, *extra,
                source, "-o", f"named-buffer-{level}-{role}.ll")
        native = f"named-buffer-{level}-oracle"
        run("xcrun", "clang", "-arch", "arm64", "-mmacosx-version-min=15.0", c_option,
            "named_buffer_native.c", "-L", ".", "-lNamedBufferClient." + level,
            "-lNamedBufferSystem." + level, "-Wl,-rpath,@executable_path", "-o", native)
        run(str(root / native))
