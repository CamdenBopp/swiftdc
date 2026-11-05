#!/usr/bin/env python3
"""Generate andsoverlap.s on stdout; native CSET supplies the oracle."""
import itertools
import sys
codes=['eq','ne','hs','lo','mi','pl','vs','vc','hi','ls','ge','lt','gt','le']
rows=[];asm=['// Authored ANDS overlap oracle: expected results come from native CSET.','.text','.p2align 2']
def constant(reg,value,width):
 value&=(1<<width)-1
 lines=[f'  movz {reg}, #{value&0xffff}']
 for offset in range(16,width,16):
  part=value>>offset&0xffff
  if part:lines.append(f'  movk {reg}, #{part}, lsl #{offset}')
 return lines
for width in [32,64]:
 prefix='w' if width==32 else 'x';mask=(1<<width)-1;sign=1<<(width-1)
 patterns=[(3,3),(sign|3,sign|1),(mask,0xf0f0f0f0f0f0f0f0&mask),(0,mask)]
 # Keep the pattern index paired with its constants.
 for (pattern,(a,b)),overlap,shift,cc in itertools.product(enumerate(patterns),['none','lhs','rhs','both'],['lsl','lsr','asr','ror'],codes):
  name=f'case_{prefix}_{pattern}_{shift}_{overlap}_{cc}';symbol=f'$s11ANDSOverlap{len(name)}{name}s6UInt64VyF'
  if overlap=='rhs':lhs,rhs,dest=prefix+'1',prefix+'0',prefix+'0'
  elif overlap=='both':lhs=rhs=dest=prefix+'0'
  else:lhs,rhs,dest=prefix+'0',prefix+'1',prefix+('0' if overlap=='lhs' else '8')
  asm+=['.p2align 2','.globl _'+symbol,'_'+symbol+':',*constant(lhs,a,width)]
  if rhs!=lhs:asm+=constant(rhs,b,width)
  asm += [f'  ands {dest}, {lhs}, {rhs}, {shift} #1',f'  cset {prefix}0, {cc}','  ret']
  rows.append({'symbol':symbol,'width':width,'pattern':pattern,'lhs':a,'rhs':a if overlap=='both' else b,'overlap':overlap,'shift':shift,'condition':cc})
assert len(rows)==1792
sys.stdout.write('\n'.join(asm)+'\n')
