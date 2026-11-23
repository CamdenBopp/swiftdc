#!/usr/bin/env python3
"""Own-source projection-result aliases; native C drivers at O0/O2/Os."""
from pathlib import Path
import shutil
import subprocess

root = Path(__file__).resolve().parent


def run(*args):
    subprocess.run(args, cwd=root, check=True)


run("xcrun", "clang", "-arch", "arm64", "-dynamiclib", "projection_return_alias.s",
    "-Wl,-install_name,@rpath/libProjectionReturnAlias.dylib",
    "-o", "libProjectionReturnAlias.dylib")
shutil.copy2(root / "libProjectionReturnAlias.dylib", root / "libProjectionReturnAlias.stripped.dylib")
run("xcrun", "strip", "-x", "libProjectionReturnAlias.stripped.dylib")
for level in ["O0", "O2", "Os"]:
    run("xcrun", "clang", "-arch", "arm64", "-" + level, "projection_return_alias_native.c",
        "-L.", "-lProjectionReturnAlias", "-Wl,-rpath,@executable_path",
        "-o", "projection-return-alias-" + level + "-oracle")
