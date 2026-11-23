#!/usr/bin/env python3
"""Foreign and body-proven projection contracts; assembly plus C native controls."""
from pathlib import Path
import shutil
import subprocess

root = Path(__file__).resolve().parent


def run(*args):
    subprocess.run(args, cwd=root, check=True)


run("xcrun", "clang", "-arch", "arm64", "-dynamiclib", "boxed_projection_provider.s",
    "-Wl,-install_name,@rpath/libBoxedProjectionForeignProvider.dylib",
    "-o", "libBoxedProjectionForeignProvider.dylib")
run("xcrun", "clang", "-arch", "arm64", "-dynamiclib", "boxed_projection_client.s",
    "-L.", "-lBoxedProjectionForeignProvider", "-Wl,-rpath,@loader_path",
    "-Wl,-install_name,@rpath/libBoxedProjectionClient.dylib",
    "-o", "libBoxedProjectionClient.dylib")
shutil.copy2(root / "libBoxedProjectionClient.dylib", root / "libBoxedProjectionClient.stripped.dylib")
run("xcrun", "strip", "-x", "libBoxedProjectionClient.stripped.dylib")
run("xcrun", "clang", "-arch", "arm64", "-dynamiclib", "boxed_projection_controls.s",
    "-Wl,-install_name,@rpath/libBoxedProjectionControls.dylib",
    "-o", "libBoxedProjectionControls.dylib")
for level in ["O0", "O2", "Os"]:
    run("xcrun", "clang", "-arch", "arm64", "-" + level, "boxed_projection_native.c",
        "-L.", "-lBoxedProjectionClient", "-lBoxedProjectionForeignProvider",
        "-Wl,-rpath,@executable_path", "-o", "boxed-projection-" + level + "-oracle")
    run("xcrun", "clang", "-arch", "arm64", "-" + level, "boxed_projection_control_native.c",
        "-L.", "-lBoxedProjectionControls", "-Wl,-rpath,@executable_path",
        "-o", "boxed-projection-control-" + level + "-oracle")
