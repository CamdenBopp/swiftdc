#!/usr/bin/env python3
"""Own-source x8 ABI controls: data words, buffers, resilience and reabstraction."""
from pathlib import Path
import json,re,subprocess,tempfile,shutil
root=Path(__file__).resolve().parent
rows=[]
def run(cmd):
    p=subprocess.run(cmd,stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
    if p.returncode:raise RuntimeError(p.stdout.decode(errors='replace'))
    return p.stdout.decode()
def native(path,count,message):
    text=run([str(path)])
    assert message in text,text
    return count
with tempfile.TemporaryDirectory(prefix='swiftdc-x8-entry-') as tmp:
    work=Path(tmp)
    run(['xcrun','clang','-arch','arm64','-dynamiclib',str(root/'x8_entry.s'),'-o',str(root/'libX8EntryScratch.dylib')])
    run(['cp',str(root/'libX8EntryScratch.dylib'),str(root/'libX8EntryScratch.stripped.dylib')])
    run(['strip','-x',str(root/'libX8EntryScratch.stripped.dylib')])
    path=root/'x8-entry-scratch-oracle'
    run(['xcrun','clang','-arch','arm64','-O2',str(root/'x8_entry_native.c'),str(root/'x8_entry.s'),'-o',str(path)])
    rows.append({'kind':'scratch','native':native(path,14,'PASS 14 native x8 scratch-word/buffer observations')})
    # Same data-only helper, now preserving x22: after strip -x, preservation
    # alone must not manufacture an ordinary x8 result-buffer contract.
    preserved=['-Wa,-defsym,X8_PRESERVE_CONTEXT=1']
    run(['xcrun','clang','-arch','arm64']+preserved+['-dynamiclib',str(root/'x8_entry.s'),'-o',str(root/'libX8EntryScratchPreserved.dylib')])
    run(['cp',str(root/'libX8EntryScratchPreserved.dylib'),str(root/'libX8EntryScratchPreserved.stripped.dylib')])
    run(['strip','-x',str(root/'libX8EntryScratchPreserved.stripped.dylib')])
    path=root/'x8-entry-scratch-preserved-oracle'
    run(['xcrun','clang','-arch','arm64']+preserved+['-c',str(root/'x8_entry.s'),'-o',str(work/'preserved.o')])
    run(['xcrun','clang','-arch','arm64','-O2',str(root/'x8_entry_native.c'),str(work/'preserved.o'),'-o',str(path)])
    rows.append({'kind':'scratch-preserved','native':native(path,14,'PASS 14 native x8 scratch-word/buffer observations')})
    have_go=shutil.which('go') is not None
    if have_go:
        for stripped in [False,True]:
            path=root/('x8-entry-go-stripped-oracle' if stripped else 'x8-entry-go-oracle')
            flags=['-ldflags=-s -w'] if stripped else []
            run(['go','build']+flags+['-o',str(path),str(root/'x8_entry_go.go')])
            rows.append({'kind':'Go','stripped':stripped,'native':native(path,7,'PASS 7 native Go x8 data observations')})
    else:
        print('==> Go not found; skipping optional x8 Go controls')
    for level in ['Onone','O','Osize']:
        for mode in ['fixed','resilient']:
            name=f'X8EntryResults.{level}.{mode}'
            p=work/name;p.mkdir()
            flags=['xcrun','swiftc','-parse-as-library','-'+level,'-module-name','EntryResults','-Xfrontend','-disable-llvm-merge-functions-pass','-Xllvm','-enable-machine-outliner=never']
            if mode=='resilient':flags+=['-enable-library-evolution']
            run(flags+['-emit-library','-emit-module','-emit-module-path',str(p/'EntryResults.swiftmodule'),'-Xlinker','-install_name','-Xlinker','@rpath/lib'+name+'.dylib',str(root/'x8_entry_results.swift'),'-o',str(root/('lib'+name+'.dylib'))])
            run(flags+['-emit-ir',str(root/'x8_entry_results.swift'),'-o',str(p/'abi.ll')])
            definitions=[s for s in (p/'abi.ll').read_text().splitlines() if s.startswith('define ') and any('$s12EntryResults'+str(len(n))+n in s for n in ['wide','wideForward','small','scalar','generic','mixed','wideAndInt'])]
            assert len(definitions)==7,(level,mode,definitions)
            for definition in definitions:
                n=next(n for n in ['wideForward','wideAndInt','generic','scalar','small','mixed','wide'] if '$s12EntryResults'+str(len(n))+n in definition)
                indirect=n in ['wide','wideForward','generic'] or (n=='small' and mode=='resilient') or (n=='wideAndInt' and mode=='fixed')
                assert ('sret(' in definition)==indirect,(level,mode,definition)
            oracle=root/f'x8-entry-{level}-{mode}-oracle'
            run(['xcrun','swiftc','-parse-as-library','-'+level,'-I',str(p),'-L',str(root),'-l'+name,'-Xlinker','-rpath','-Xlinker','@executable_path',str(root/'x8_entry_results_native.swift'),'-o',str(oracle)])
            rows.append({'kind':'Swift','level':level,'mode':mode,'native':native(oracle,49,'PASS 49 native entry-result observations'),'signatures':definitions})
        name=f'X8EntryReabstract.{level}';p=work/name;p.mkdir()
        flags=['xcrun','swiftc','-parse-as-library','-'+level,'-module-name','ReabstractResult','-Xfrontend','-disable-llvm-merge-functions-pass','-Xllvm','-enable-machine-outliner=never']
        run(flags+['-emit-library','-emit-module','-emit-module-path',str(p/'ReabstractResult.swiftmodule'),'-Xlinker','-install_name','-Xlinker','@rpath/lib'+name+'.dylib',str(root/'x8_entry_reabstract.swift'),'-o',str(root/('lib'+name+'.dylib'))])
        run(flags+['-emit-ir',str(root/'x8_entry_reabstract.swift'),'-o',str(p/'abi.ll')])
        definitions=[s for s in (p/'abi.ll').read_text().splitlines() if s.startswith('define ') and re.search(r'sret\((?:%TSi|i64)\)',s)]
        if level=='Onone':assert len(definitions)==2,definitions
        oracle=root/f'x8-entry-reabstract-{level}-oracle'
        run(['xcrun','swiftc','-parse-as-library','-'+level,'-I',str(p),'-L',str(root),'-l'+name,'-Xlinker','-rpath','-Xlinker','@executable_path',str(root/'x8_entry_reabstract_native.swift'),'-o',str(oracle)])
        rows.append({'kind':'reabstract','level':level,'native':native(oracle,7,'PASS 7 native reabstracted result observations'),'signatures':definitions})
    for level in ['O0','O2','Os']:
        name='X8EntryObjC.'+level;p=work/name;p.mkdir()
        flags=['xcrun','clang','-arch','arm64','-'+level,'-fobjc-arc']
        run(flags+['-dynamiclib','-framework','Foundation',str(root/'x8_entry_objc.m'),'-o',str(root/('lib'+name+'.dylib'))])
        run(flags+['-S','-emit-llvm',str(root/'x8_entry_objc.m'),'-o',str(p/'abi.ll')])
        definitions=[s for s in (p/'abi.ll').read_text().splitlines() if s.startswith('define ') and '-[EntryResultObject ' in s]
        assert len(definitions)==3,definitions
        assert sum('sret(' in s for s in definitions)==1
        assert all(('sret(' in s)==('-[EntryResultObject wide:' in s) for s in definitions)
        oracle=root/f'x8-entry-objc-{level}-oracle'
        run(flags+['-DBUILD_DRIVER','-framework','Foundation',str(root/'x8_entry_objc.m'),'-o',str(oracle)])
        rows.append({'kind':'Objective-C','level':level,'native':native(oracle,21,'PASS 21 native Objective-C entry-result observations'),'signatures':definitions})
native_count=sum(r['native'] for r in rows)
assert native_count==(420 if have_go else 406)
assert sum(len(r.get('signatures',[])) for r in rows)==53
(root/'x8entry.abi.json').write_text(json.dumps(rows,indent=2)+'\n')
print(f'PASS 53 compiler result signatures and {native_count} native observations')
