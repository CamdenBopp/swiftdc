#!/usr/bin/env python3
"""Authored opaque-boundary controls; native C fixes GP/FP source arity."""
from pathlib import Path
import subprocess
root=Path(__file__).resolve().parent
for level in ['O0','O2','Os']:
    provider=f'libBodyArityEffect.{level}.dylib'
    library=f'libBodyArity.{level}.dylib'
    flags=['xcrun','clang','-arch','arm64','-mmacosx-version-min=15.0','-'+level]
    subprocess.run(flags+['-dynamiclib',str(root/'body_arity_effect.c'),'-Wl,-install_name,@rpath/'+provider,'-o',str(root/provider)],check=True)
    subprocess.run(flags+['-dynamiclib',str(root/'body_arity.s'),str(root/provider),'-Wl,-install_name,@rpath/'+library,'-Wl,-rpath,@loader_path','-o',str(root/library)],check=True)
    subprocess.run(['cp',str(root/library),str(root/(library.replace('.dylib','.stripped.dylib')))],check=True)
    subprocess.run(['strip','-x',str(root/(library.replace('.dylib','.stripped.dylib')))],check=True)
    oracle=root/f'body-arity-{level}-oracle'
    subprocess.run(flags+[str(root/'body_arity_native.c'),str(root/library),str(root/provider),'-Wl,-rpath,@executable_path','-o',str(oracle)],check=True)
    output=subprocess.check_output([str(oracle)],text=True)
    assert output.strip()=='PASS 84 native body-arity observations and 49 opaque effects',output
    print(level+': '+output.strip(),flush=True)
print('PASS 252 native body-arity observations and 147 opaque effects')
