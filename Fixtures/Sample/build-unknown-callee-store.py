#!/usr/bin/env python3
"""Own-source unknown-pointer stores and disjoint private-frame controls."""
from pathlib import Path
import subprocess
root=Path(__file__).resolve().parent
for level in ['O0','O2','Os']:
    flags=['xcrun','clang','-arch','arm64','-mmacosx-version-min=15.0','-'+level]
    library=root/f'libUnknownCalleeStore.{level}.dylib'
    subprocess.run(flags+['-dynamiclib',str(root/'unknown_callee_store.s'),'-Wl,-install_name,@rpath/'+library.name,'-o',str(library)],check=True)
    stripped=library.with_name(library.name.replace('.dylib','.stripped.dylib'))
    subprocess.run(['cp',str(library),str(stripped)],check=True)
    subprocess.run(['strip','-x',str(stripped)],check=True)
    oracle=root/f'unknown-store-{level}-oracle'
    subprocess.run(flags+[str(root/'unknown_callee_store_native.c'),str(library),'-Wl,-rpath,@executable_path','-o',str(oracle)],check=True)
    output=subprocess.check_output([str(oracle)],text=True)
    assert output.strip()=='PASS 35 native unknown-store context/buffer/frame observations',output
    print(level+': '+output.strip(),flush=True)
print('PASS 105 native unknown-store context/buffer/frame observations')
