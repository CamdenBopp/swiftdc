# Collections: Ghidra 12.2 vs swiftdc

> Re-scored 2026-11-13b: swiftdc columns only, against `2026-11-13b/renders/`, by `2026-11-13b/scores/RUBRIC.md` and its addendum. Ghidra's columns are copied unchanged. A row whose swiftdc text did not change keeps its old scores. No row changed score: the only scored function whose text changed is coll3.atU at -Osize (signedness marker), and it stays PARTIAL. swiftdc totals are the same as on 2026-11-13.

Fixtures: coll.swift (O, Onone, Osize), coll2.swift (O, Onone, Osize), coll3.swift (O, Osize), mut.swift (Osize), ovf.swift (O). There are 175 rows: every public user-written function in every build. Synthesized stored-property accessors and `P.init` are skipped.

## Totals

| tool, axis | CORRECT | PARTIAL | WRONG | DECLINED |
|---|---|---|---|---|
| Ghidra interface | 144 | 0 | 29 | 2 |
| Ghidra body | 110 | 7 | 58 | 0 |
| swiftdc interface | 175 | 0 | 0 | 0 |
| swiftdc body | 3 | 114 | 43 | 15 |

swiftdc never shows a wrong signature, but it recovers almost no values: most bodies end in `return ?`. Its 43 WRONG bodies split into two groups. 19 are calls that omit the receiver (mostly at -Onone, plus `_consumeAndCreateNew` in sw/setAt). The rest are dropped overflow traps inside loops, three calls with made-up arguments (`_makeUniqueAndReserveCapacityIfNotUnique` given x0..x2 when it reads only x20) and a tail call shown without `return`. Ghidra recovers most -O/-Osize bodies exactly, vectorised loops and traps included. Its 58 WRONG bodies come from Swift calling-convention plumbing. 28 of them are calls that drop an argument, mostly self in x20. The others are Optional tags read as parameters, inout collections taken by value, stale buffers after reallocation, `void` prototypes at -Onone, and error traps it deletes.

## Where Ghidra beats swiftdc

1. **coll.sumAll, O** (truth: `for x in a { s += x }` traps on overflow, `adds; b.vs brk`).
   Ghidra: `bVar2 = SCARRY8(lVar3,*plVar4); lVar3 = lVar3 + *plVar4; if (bVar2) { SoftwareBreakpoint... } ... return lVar3;`
   swiftdc: `while (true) { if (x9 != 0) { continue } else { break } } return ?`. The trap is gone, so a reader concludes the loop cannot fail. The same drop recurs in sumAbove, dsum, lazyCount, diff, ovf.addT/triT/psum and bsearch.
2. **coll2.diff, O** (truth: traps if i+1 overflows or either index is out of bounds; returns a[i+1] &- a[i]).
   Ghidra: `if (SCARRY8(param_2,1)) trap; ... return *(param_1+0x20+uVar1*8) - *(param_1+0x20+param_2*8);`
   swiftdc: `if (bit 0x3f of x8 set) trap() ... if (x1 >=ᵁ x9) trap() else return ?`. The bounds traps survive but the overflow trap is dropped, and there is no value.
3. **coll3.mod3, O** (truth: count of i in 0..<n with i % 3 == 0).
   Ghidra: `if (lVar7 + (uVar11 / 3) * 3 == 0) lVar6 = lVar6 + 1;` across 4 lanes, with the remainder loop `uVar8 * -0x5555555555555555 < 0x5555555555555556`.
   swiftdc: `while (x5 != 0) { } ... return ?`.

## Where swiftdc beats Ghidra

1. **coll.firstIdx, Osize** (truth: `a.firstIndex(of: v) ?? -1`; the Optional comes back in x0 (value) and w1 (nil tag)).
   Ghidra: `firstIdx(uint param_1,__int64 param_2) { _firstIndex(); if ((param_1 & 0xff) == 1) param_2 = -1; return param_2; }`. It returns the searched value, not the index, and types the array as `uint`.
   swiftdc: `firstIdx(Swift.Array<Swift.Int>, Swift.Int) -> Swift.Int { ...firstIndex(of:)(…) return ? }`. Unfinished, but nothing in it is false.
2. **coll.mx, Osize** (truth: `a.max() ?? Int.min`; the Optional comes back in x0 (value) and w1 (tag)).
   Ghidra: `mx(__int64 param_1,uint param_2) { _max(); _Var1 = INT_MIN; if ((param_2 & 0xff) != 1) _Var1 = param_1; return _Var1; }` returns the array pointer and invents a second parameter.
   swiftdc: `...Sequence.max(arg0)  return ?`. (At -Onone in dbl both are WRONG, but Ghidra's `code * dbl(void)` returning the closure address is worse than swiftdc's `map(closure #1 ...)` with the receiver omitted.)
3. **coll2.dput, O** (truth: `d[k] = v`; setValue mutates a stack copy, which is then stored back to `*d`).
   Ghidra: `uVar2 = *(undefined8 *)param_1.unknown; setValue(param_3,param_2,uVar1); *(undefined8 *)param_1.unknown = uVar2;` writes back the pre-call dictionary, and the inout is shown by value.
   swiftdc: `setValue(self: local_38, …)` then `mem64[arg0] = x8`. Raw, but the store is right.

## Scoring rules applied

- Ghidra's interface is its decompiled C prototype. A `void` result on a value-returning function is WRONG on both axes. `undefinedN` is typeless and counts as CORRECT when the position is right. A narrow result typed wider (`int` for Int8/UInt16) is a WRONG interface when values leave the narrow range; the body is then judged on the machine bits.
- Comparisons are read in each tool's own type system. Ghidra follows its C types and casts. swiftdc's `<ᵁ`/`>>ˢ` markers say the signedness outright. A plain operator follows the Swift types swiftdc itself declared: plain `<` with a UInt-typed operand is unsigned, which is what its renderer documents (`renderUnsignedComparison`: "proven `UInt` operand → a plain `<`"). It also prints that same plain `<` for a signed machine compare on UInt-typed operands, and those rows are WRONG.
- A dropped trap is WRONG. The one exception is a trap the function's own code proves unreachable from its argument types: an Int8 range after `sxtb`, a masked shift count, `count - 1` on an Array count, the overflow of `endIndex - startIndex` on a valid slice. A trap whose reachability rests on a callee's behaviour (the error-register check after a rethrowing call) still counts.
- This follows the shared RUBRIC.md. A call that omits an argument the callee takes, such as the receiver/self or `insert()` with no value, is WRONG for either tool. An argument shown as `?` or `…` is PARTIAL. A made-up or misbound argument is WRONG. Metadata and witness-table arguments are not required.
- A raw register in a swiftdc body condition (`if (x1 >=ᵁ x8)`) is a PARTIAL body piece. It does not make the interface DECLINED, because the header already names every parameter. Ghidra reading a parameter it left out of its prototype (`in_x4`) is DECLINED or WRONG for its interface.
- swiftdc body PARTIAL needs at least one trap, call, store or returned value recovered correctly. A body that keeps only control-flow shape over raw registers plus `return ?` is DECLINED. A function absent from a tool's output, or shown as a bare `sub_XXX`/parameterless C header, is DECLINED.

## Table

| function | level | Ghidra interface | Ghidra body | swiftdc interface | swiftdc body | note |
|---|---|---|---|---|---|---|
| coll.at | O | CORRECT | CORRECT | CORRECT | PARTIAL | swiftdc: both traps right, loaded element returned as ? |
| coll.cnt | O | CORRECT | CORRECT | CORRECT | DECLINED | swiftdc: return ? |
| coll.cap | O | CORRECT | CORRECT | CORRECT | DECLINED | swiftdc: return ? |
| coll.sumAll | O | CORRECT | CORRECT | CORRECT | WRONG | swiftdc drops the loop's b.vs overflow trap; sum is ? |
| coll.sumAbove | O | WRONG | WRONG | CORRECT | WRONG | Ghidra invents params 3-4 and keeps writing the old empty storage after _createNewBuffer reallocates; swiftdc drops the summing loop's overflow trap |
| coll.firstIdx | O | CORRECT | CORRECT | CORRECT | DECLINED | swiftdc: shape only, both results ? |
| coll.firstAbove | O | CORRECT | CORRECT | CORRECT | DECLINED | swiftdc: shape only, both results ? |
| coll.strideSum | O | CORRECT | CORRECT | CORRECT | PARTIAL | swiftdc: induction and overflow exit right, accumulator ? |
| coll.rangeSum | O | CORRECT | CORRECT | CORRECT | CORRECT |  |
| coll.closedSum | O | CORRECT | CORRECT | CORRECT | PARTIAL | swiftdc: trap right, closed-form sum ? |
| coll.push | O | CORRECT | WRONG | CORRECT | PARTIAL | Ghidra omits the 5th arg (x4 release fn) of merged _consumeAndCreateNew; swiftdc leaves count/buffer args ?; Ghidra WRONG under the shared rubric: a call drops an argument the callee takes |
| coll.sw | O | CORRECT | CORRECT | CORRECT | WRONG | swiftdc: traps right; _consumeAndCreateNew receiver omitted, swapped values raw; swiftdc WRONG under the shared rubric: a call drops an argument the callee takes |
| coll.setAt | O | CORRECT | CORRECT | CORRECT | WRONG | swiftdc: traps right; _consumeAndCreateNew receiver omitted; swiftdc WRONG under the shared rubric: a call drops an argument the callee takes |
| coll.rep | O | CORRECT | WRONG | CORRECT | PARTIAL | Ghidra passes v (param_1) as _allocateBufferUninitialized's count; true arg is n |
| coll.dbl | O | WRONG | WRONG | CORRECT | PARTIAL | Ghidra: void return plus invented params; keeps writing the empty-storage constant after reallocation |
| coll.dget | O | CORRECT | CORRECT | CORRECT | PARTIAL | swiftdc: find key arg ?, value ? |
| coll.scontains | O | CORRECT | PARTIAL | CORRECT | PARTIAL | Ghidra passes a raw in_x2 third arg to Hasher._hash; swiftdc: probe loop raw, result ? |
| coll.dsum | O | CORRECT | CORRECT | CORRECT | WRONG | swiftdc drops the word-index overflow trap; sum ? |
| coll.dot | O | CORRECT | CORRECT | CORRECT | PARTIAL | swiftdc: only the count==0 -> 0 path; sum ? |
| coll.wsum | O | CORRECT | CORRECT | CORRECT | PARTIAL | swiftdc: only count==0 -> 0; loops empty, sum ? |
| coll.sliceSum | O | CORRECT | CORRECT | CORRECT | PARTIAL | swiftdc: all five traps right, sum ? |
| coll.clast | O | CORRECT | CORRECT | CORRECT | PARTIAL | swiftdc: empty -> -1 right, last element ? |
| coll.bsum | O | CORRECT | CORRECT | CORRECT | DECLINED | swiftdc: shape only, sum ? |
| coll.sdesc | O | WRONG | WRONG | CORRECT | PARTIAL | Ghidra: void sdesc(void), drops sort's args, the error trap and the result; swiftdc: sort + error trap, result ? |
| coll.lazyCount | O | CORRECT | CORRECT | CORRECT | WRONG | swiftdc drops the index and count overflow traps in the counting loop |
| coll.build | O | CORRECT | WRONG | CORRECT | PARTIAL | Ghidra omits x4 of merged _consumeAndCreateNew; swiftdc: second call args ?, result ?; Ghidra WRONG under the shared rubric: a call drops an argument the callee takes |
| coll.empty | O | CORRECT | CORRECT | CORRECT | DECLINED | swiftdc: return ? |
| coll.byteAt | O | CORRECT | CORRECT | CORRECT | PARTIAL | swiftdc: traps right, byte ? |
| coll.i32At | O | CORRECT | CORRECT | CORRECT | PARTIAL | swiftdc: traps right, element ? |
| coll.mx | O | CORRECT | CORRECT | CORRECT | PARTIAL | swiftdc: empty -> Int.min right, max ? |
| coll.rsum | O | CORRECT | CORRECT | CORRECT | WRONG | swiftdc: `var i = 0` is set only on the count<=1 path; the count>1 entry jumps into the loop past it, so the rendered induction misstates the start (count-1) |
| coll.at | Osize | CORRECT | CORRECT | CORRECT | PARTIAL | swiftdc: traps right, element ? |
| coll.cnt | Osize | CORRECT | CORRECT | CORRECT | DECLINED | swiftdc: return ? |
| coll.cap | Osize | CORRECT | CORRECT | CORRECT | DECLINED | swiftdc: return ? |
| coll.sumAll | Osize | CORRECT | CORRECT | CORRECT | WRONG | swiftdc drops the loop's overflow trap |
| coll.sumAbove | Osize | CORRECT | WRONG | CORRECT | WRONG | Ghidra keeps writing the old empty storage after reallocation (and omits self); swiftdc drops the summing loop's overflow trap |
| coll.firstIdx | Osize | WRONG | WRONG | CORRECT | PARTIAL | Ghidra aliases firstIndex's tag (w1) onto param_1 (typed uint) and returns param_2, the searched value, as the index; swiftdc: call args elided, result ? |
| coll.firstAbove | Osize | CORRECT | CORRECT | CORRECT | DECLINED | swiftdc: shape only |
| coll.strideSum | Osize | CORRECT | CORRECT | CORRECT | PARTIAL | swiftdc: overflow exit constant right, sum ? |
| coll.rangeSum | Osize | CORRECT | CORRECT | CORRECT | PARTIAL | swiftdc: a==b path (outlined zero) returns ? |
| coll.closedSum | Osize | CORRECT | CORRECT | CORRECT | PARTIAL | swiftdc: trap right, sum ? |
| coll.push | Osize | CORRECT | WRONG | CORRECT | WRONG | Ghidra omits self (x20) on both calls; swiftdc passes arg0, arg1 to _makeUniqueAndReserveCapacityIfNotUnique, which reads only self; Ghidra WRONG under the shared rubric: a call drops an argument the callee takes |
| coll.sw | Osize | CORRECT | CORRECT | CORRECT | WRONG | swiftdc: _consumeAndCreateNew receiver omitted; swiftdc WRONG under the shared rubric: a call drops an argument the callee takes |
| coll.setAt | Osize | CORRECT | CORRECT | CORRECT | WRONG | swiftdc: _consumeAndCreateNew receiver omitted; swiftdc WRONG under the shared rubric: a call drops an argument the callee takes |
| coll.rep | Osize | CORRECT | WRONG | CORRECT | PARTIAL | Ghidra passes v as _allocateBufferUninitialized's count |
| coll.dbl | Osize | WRONG | WRONG | CORRECT | PARTIAL | Ghidra: void return plus invented params; stale buffer after reallocation |
| coll.dget | Osize | CORRECT | CORRECT | CORRECT | PARTIAL | swiftdc: key arg ?, value ? |
| coll.scontains | Osize | CORRECT | CORRECT | CORRECT | PARTIAL | swiftdc: tail call with args elided and no return statement |
| coll.dsum | Osize | CORRECT | CORRECT | CORRECT | WRONG | swiftdc drops the word-index overflow trap |
| coll.dot | Osize | CORRECT | CORRECT | CORRECT | PARTIAL | swiftdc: bounds trap kept but its condition is `cond >=ᵁ` without operands; sum ? |
| coll.wsum | Osize | CORRECT | CORRECT | CORRECT | DECLINED | swiftdc: shape only |
| coll.sliceSum | Osize | CORRECT | CORRECT | CORRECT | PARTIAL | swiftdc: traps right, sum ? |
| coll.clast | Osize | CORRECT | CORRECT | CORRECT | PARTIAL | swiftdc: empty -> -1, last ? |
| coll.bsum | Osize | CORRECT | CORRECT | CORRECT | DECLINED | swiftdc: shape only |
| coll.sdesc | Osize | WRONG | WRONG | CORRECT | PARTIAL | Ghidra: void sdesc(void), drops args, error trap and result |
| coll.lazyCount | Osize | CORRECT | CORRECT | CORRECT | WRONG | swiftdc drops the count and index overflow traps |
| coll.build | Osize | WRONG | WRONG | CORRECT | PARTIAL | Ghidra: void return, the built array is lost |
| coll.empty | Osize | CORRECT | CORRECT | CORRECT | DECLINED | swiftdc: return ? |
| coll.byteAt | Osize | CORRECT | CORRECT | CORRECT | PARTIAL | swiftdc: traps right, byte ? |
| coll.i32At | Osize | CORRECT | CORRECT | CORRECT | PARTIAL | swiftdc: traps right, element ? |
| coll.mx | Osize | WRONG | WRONG | CORRECT | PARTIAL | Ghidra invents uint param_2 (really max()'s tag) and returns the array pointer when non-nil; swiftdc: max(arg0), result ? |
| coll.rsum | Osize | CORRECT | CORRECT | CORRECT | PARTIAL | swiftdc: bounds trap kept, everything raw, sum ? |
| coll.at | Onone | CORRECT | CORRECT | CORRECT | WRONG | swiftdc: subscript.getter(arg1) omits the array receiver; result ?; swiftdc WRONG under the shared rubric: a call drops an argument the callee takes |
| coll.cnt | Onone | CORRECT | CORRECT | CORRECT | CORRECT |  |
| coll.cap | Onone | CORRECT | CORRECT | CORRECT | CORRECT |  |
| coll.sumAll | Onone | CORRECT | WRONG | CORRECT | WRONG | Ghidra: makeIterator/next receivers omitted, sum and trap right; swiftdc drops the accumulate and its overflow trap; Ghidra WRONG under the shared rubric: a call drops an argument the callee takes |
| coll.sumAbove | Onone | CORRECT | WRONG | CORRECT | WRONG | Ghidra drops both error traps and takes filter's result to be the closure address; swiftdc: filter/reduce with closures and traps, receiver omitted, result ?; swiftdc WRONG under the shared rubric: a call drops an argument the callee takes |
| coll.firstIdx | Onone | WRONG | WRONG | CORRECT | PARTIAL | Ghidra: firstIdx(void); firstIndex() args omitted, Optional handling right; swiftdc result ?; Ghidra WRONG under the shared rubric: a call drops an argument the callee takes |
| coll.firstAbove | Onone | WRONG | WRONG | CORRECT | PARTIAL | Ghidra: firstAbove(void), drops the error trap |
| coll.strideSum | Onone | CORRECT | WRONG | CORRECT | PARTIAL | Ghidra passes the iterator buffer as stride's `from` (true: address of 0); swiftdc: stride args right, sum ? |
| coll.rangeSum | Onone | CORRECT | WRONG | CORRECT | WRONG | both: makeIterator receiver omitted; Ghidra sum right, swiftdc sum ?; both WRONG under the shared rubric: a call drops an argument the callee takes |
| coll.closedSum | Onone | CORRECT | WRONG | CORRECT | WRONG | both: makeIterator receiver omitted; Ghidra sum right, swiftdc sum ?; both WRONG under the shared rubric: a call drops an argument the callee takes |
| coll.push | Onone | CORRECT | WRONG | CORRECT | PARTIAL | Ghidra omits append's self; swiftdc append(?); Ghidra WRONG under the shared rubric: a call drops an argument the callee takes |
| coll.sw | Onone | CORRECT | WRONG | CORRECT | WRONG | Ghidra swapAt() with no args; swiftdc swapAt(&i, &j), receiver omitted; both WRONG under the shared rubric: a call drops an argument the callee takes |
| coll.setAt | Onone | CORRECT | WRONG | CORRECT | PARTIAL | Ghidra stores v through param_2 (the index) and calls the buffer as the continuation; swiftdc: modify(buf, i), store via raw x1 |
| coll.rep | Onone | WRONG | WRONG | CORRECT | PARTIAL | Ghidra: void return, Array.init result dropped; swiftdc return init(?, ?) |
| coll.dbl | Onone | WRONG | WRONG | CORRECT | WRONG | Ghidra: dbl(void) returns the closure pointer, error trap dropped; swiftdc: map + trap + return r0, receiver omitted; swiftdc WRONG under the shared rubric: a call drops an argument the callee takes |
| coll.dget | Onone | CORRECT | CORRECT | CORRECT | PARTIAL | swiftdc: subscript.getter(?), result ? |
| coll.scontains | Onone | CORRECT | CORRECT | CORRECT | PARTIAL | swiftdc: contains(?) & 1 |
| coll.dsum | Onone | CORRECT | WRONG | CORRECT | WRONG | both omit makeIterator's dictionary; Ghidra sum right, swiftdc sum ?; both WRONG under the shared rubric: a call drops an argument the callee takes |
| coll.dot | Onone | CORRECT | WRONG | CORRECT | PARTIAL | Ghidra's zip gets type metadata as the first sequence; swiftdc zip args right (result buffer labelled self), sum ? |
| coll.wsum | Onone | CORRECT | WRONG | CORRECT | WRONG | both omit enumerated/makeIterator receivers; Ghidra sum right, swiftdc sum ?; both WRONG under the shared rubric: a call drops an argument the callee takes |
| coll.sliceSum | Onone | CORRECT | WRONG | CORRECT | PARTIAL | Ghidra passes hi-lo to the Range subscript getter (true: lo, hi, array); swiftdc subscript(?) |
| coll.clast | Onone | CORRECT | WRONG | CORRECT | WRONG | both: last getter receiver omitted; Ghidra result right, swiftdc ?; both WRONG under the shared rubric: a call drops an argument the callee takes |
| coll.bsum | Onone | CORRECT | WRONG | CORRECT | PARTIAL | Ghidra drops the x21 error trap; swiftdc keeps it, result ? |
| coll.sdesc | Onone | WRONG | WRONG | CORRECT | PARTIAL | Ghidra: sdesc(void) returns the closure pointer, trap dropped; swiftdc sorted(closure) + trap + return r0 |
| coll.lazyCount | Onone | CORRECT | WRONG | CORRECT | WRONG | both omit receivers; swiftdc names the map/filter closures, Ghidra passes none; both return count; both WRONG under the shared rubric: a call drops an argument the callee takes |
| coll.build | Onone | CORRECT | PARTIAL | CORRECT | PARTIAL | Ghidra appends with an uninitialised metadata arg; swiftdc result ? |
| coll.empty | Onone | WRONG | WRONG | CORRECT | WRONG | Ghidra: empty(void); both omit isEmpty's receiver; both WRONG under the shared rubric: a call drops an argument the callee takes |
| coll.byteAt | Onone | CORRECT | CORRECT | CORRECT | WRONG | swiftdc: receiver omitted, result ?; swiftdc WRONG under the shared rubric: a call drops an argument the callee takes |
| coll.i32At | Onone | CORRECT | CORRECT | CORRECT | WRONG | swiftdc: receiver omitted, result ?; swiftdc WRONG under the shared rubric: a call drops an argument the callee takes |
| coll.mx | Onone | WRONG | WRONG | CORRECT | PARTIAL | Ghidra: mx(void), max() args omitted; swiftdc result ?; Ghidra WRONG under the shared rubric: a call drops an argument the callee takes |
| coll.rsum | Onone | CORRECT | WRONG | CORRECT | WRONG | Ghidra gives count getter the memset buffer and stride `from` = count (true: count-1); swiftdc drops the count-1 overflow trap |
| coll2.py | O | CORRECT | CORRECT | CORRECT | PARTIAL | swiftdc: traps right, `return ?` |
| coll2.pz | O | CORRECT | CORRECT | CORRECT | PARTIAL | swiftdc: traps right, `return ?` |
| coll2.diff | O | CORRECT | CORRECT | CORRECT | WRONG | swiftdc drops the i+1 overflow trap (b.vs, reachable at Int.max) |
| coll2.incPairs | O | CORRECT | CORRECT | CORRECT | PARTIAL | swiftdc: empty vector loop, raw regs, `return ?` |
| coll2.hasByte | O | CORRECT | CORRECT | CORRECT | PARTIAL | swiftdc: loop condition `?`, `return ?` |
| coll2.dput | O | WRONG | WRONG | CORRECT | PARTIAL | Ghidra: inout shown by value; writes back the pre-call dictionary, not the slot setValue mutated |
| coll2.sins | O | WRONG | WRONG | CORRECT | PARTIAL | Ghidra: inout Set by value; insert() shown without self and value; Ghidra WRONG under the shared rubric: a call drops an argument the callee takes |
| coll2.sliceAt | O | WRONG | PARTIAL | CORRECT | PARTIAL | Ghidra: param_2 is really x1 (base), index read as raw in_x4 |
| coll2.sliceCount | O | DECLINED | PARTIAL | CORRECT | DECLINED | Ghidra: in_x2/in_x3 raw; swiftdc only `return ?` (its dropped subs overflow trap is unreachable for any valid slice, so not counted) |
| coll2.lastLE | O | CORRECT | CORRECT | CORRECT | PARTIAL | swiftdc: raw regs, `return ?` |
| coll2.u32sum | O | CORRECT | CORRECT | CORRECT | PARTIAL | swiftdc: empty vector loops, `return ?` |
| coll2.firstOr7 | O | CORRECT | CORRECT | CORRECT | PARTIAL | swiftdc: 7 path right, else `?` |
| coll2.evens | O | CORRECT | CORRECT | CORRECT | PARTIAL | swiftdc: bounds trap kept, `return ?` |
| coll2.evIdx | O | CORRECT | CORRECT | CORRECT | PARTIAL | swiftdc: bounds trap kept, `return ?` |
| coll2.i8At | O | CORRECT | CORRECT | CORRECT | PARTIAL | swiftdc: traps right, `return ?` |
| coll2.dropK | O | CORRECT | CORRECT | CORRECT | PARTIAL | swiftdc: traps and -1 right, else `?` |
| coll2.popL | O | CORRECT | CORRECT | CORRECT | PARTIAL | swiftdc: both empty traps right, `return ?` |
| coll2.py | Osize | CORRECT | CORRECT | CORRECT | PARTIAL | swiftdc `return ?` |
| coll2.pz | Osize | CORRECT | CORRECT | CORRECT | PARTIAL | swiftdc `return ?` |
| coll2.diff | Osize | CORRECT | CORRECT | CORRECT | WRONG | swiftdc drops the i+1 overflow trap |
| coll2.incPairs | Osize | CORRECT | CORRECT | CORRECT | PARTIAL | swiftdc: loop trap right, `return ?` |
| coll2.hasByte | Osize | WRONG | WRONG | CORRECT | WRONG | Ghidra `hasByte(void)`, contains() without args; swiftdc renders the tail call with no return; Ghidra WRONG under the shared rubric: a call drops an argument the callee takes |
| coll2.dput | Osize | WRONG | WRONG | CORRECT | PARTIAL | Ghidra keeps using the pre-ensureUnique storage (re-find, insert, write-back); swiftdc find/ensureUnique/insert/store right with `?` args (dropped count+1 trap is unreachable) |
| coll2.sins | Osize | WRONG | WRONG | CORRECT | PARTIAL | Ghidra: inout by value, insert() without self/value; Ghidra WRONG under the shared rubric: a call drops an argument the callee takes |
| coll2.sliceAt | Osize | WRONG | PARTIAL | CORRECT | PARTIAL | Ghidra: index raw in_x4, param_2 is x1; swiftdc trap condition `?` |
| coll2.sliceCount | Osize | DECLINED | PARTIAL | CORRECT | DECLINED | Ghidra: in_x2/in_x3 raw; swiftdc only `return ?` (its dropped subs overflow trap is unreachable for any valid slice, so not counted) |
| coll2.lastLE | Osize | CORRECT | CORRECT | CORRECT | PARTIAL | swiftdc raw regs, `return ?` |
| coll2.u32sum | Osize | CORRECT | CORRECT | CORRECT | PARTIAL | swiftdc empty loop, `return ?` |
| coll2.firstOr7 | Osize | CORRECT | CORRECT | CORRECT | PARTIAL | swiftdc else `?` |
| coll2.evens | Osize | CORRECT | CORRECT | CORRECT | PARTIAL | swiftdc `return ?` |
| coll2.evIdx | Osize | CORRECT | CORRECT | CORRECT | PARTIAL | swiftdc `return ?` |
| coll2.i8At | Osize | CORRECT | CORRECT | CORRECT | PARTIAL | swiftdc `return ?` |
| coll2.dropK | Osize | WRONG | WRONG | CORRECT | PARTIAL | Ghidra: 4 params; dropFirst's results read as params, element loaded from a+i*8 (base off by 0x20) |
| coll2.popL | Osize | CORRECT | WRONG | CORRECT | WRONG | Ghidra returns param_1 / count-1 instead of the callee results; swiftdc passes a fabricated arg0 to _customRemoveLast |
| coll2.py | Onone | CORRECT | CORRECT | CORRECT | WRONG | swiftdc `subscript.getter(arg1)` without array, `return ?`; swiftdc WRONG under the shared rubric: a call drops an argument the callee takes |
| coll2.pz | Onone | CORRECT | CORRECT | CORRECT | PARTIAL | swiftdc `return ?` |
| coll2.diff | Onone | CORRECT | CORRECT | CORRECT | WRONG | swiftdc drops the i+1 overflow trap |
| coll2.incPairs | Onone | CORRECT | WRONG | CORRECT | WRONG | Ghidra: second count getter given fabricated args (count-2, count); swiftdc drops the i-1 overflow trap |
| coll2.hasByte | Onone | WRONG | WRONG | CORRECT | PARTIAL | Ghidra `hasByte(void)`, contains() without args; Ghidra WRONG under the shared rubric: a call drops an argument the callee takes |
| coll2.dput | Onone | WRONG | CORRECT | CORRECT | WRONG | Ghidra: inout by value; swiftdc setter without self; swiftdc WRONG under the shared rubric: a call drops an argument the callee takes |
| coll2.sins | Onone | WRONG | WRONG | CORRECT | PARTIAL | Ghidra insert() without self; swiftdc `insert(?)`; Ghidra WRONG under the shared rubric: a call drops an argument the callee takes |
| coll2.sliceAt | Onone | WRONG | PARTIAL | CORRECT | PARTIAL | Ghidra index raw in_x4 |
| coll2.sliceCount | Onone | CORRECT | CORRECT | CORRECT | PARTIAL | swiftdc `count.getter(?, ?, ?, ?)` |
| coll2.lastLE | Onone | CORRECT | CORRECT | CORRECT | PARTIAL | swiftdc: count/subscript calls, `if (?)`, `return ?` (dropped count-1 and i-1 traps are unreachable) |
| coll2.u32sum | Onone | CORRECT | WRONG | CORRECT | PARTIAL | Ghidra makeIterator/retain without args; swiftdc loop without sum; Ghidra WRONG under the shared rubric: a call drops an argument the callee takes |
| coll2.firstOr7 | Onone | WRONG | WRONG | CORRECT | PARTIAL | Ghidra `firstOr7(void)`, first getter without self; Ghidra WRONG under the shared rubric: a call drops an argument the callee takes |
| coll2.evens | Onone | CORRECT | WRONG | CORRECT | PARTIAL | Ghidra deletes the reduce error trap as "unreachable" and passes metadata as the witness table |
| coll2.evIdx | Onone | CORRECT | WRONG | CORRECT | PARTIAL | Ghidra count getter without self; Ghidra WRONG under the shared rubric: a call drops an argument the callee takes |
| coll2.i8At | Onone | CORRECT | CORRECT | CORRECT | PARTIAL | swiftdc `return ?` |
| coll2.dropK | Onone | CORRECT | WRONG | CORRECT | PARTIAL | Ghidra dropFirst/first without self; Ghidra WRONG under the shared rubric: a call drops an argument the callee takes |
| coll2.popL | Onone | CORRECT | WRONG | CORRECT | PARTIAL | Ghidra removeLast without self; Ghidra WRONG under the shared rubric: a call drops an argument the callee takes |
| coll3.atU | O | CORRECT | CORRECT | CORRECT | PARTIAL | swiftdc `return ?` |
| coll3.at32 | O | CORRECT | CORRECT | CORRECT | PARTIAL | swiftdc `return ?` |
| coll3.closedRange | O | CORRECT | CORRECT | CORRECT | PARTIAL | swiftdc: all five traps right, empty loops, `return ?` |
| coll3.revSq | O | CORRECT | CORRECT | CORRECT | PARTIAL | swiftdc: raw x9 test before `i -= 1`, sum missing, `return ?` |
| coll3.lastBang | O | CORRECT | CORRECT | CORRECT | PARTIAL | swiftdc `return ?` |
| coll3.mod3 | O | CORRECT | CORRECT | CORRECT | PARTIAL | swiftdc empty loops, `return ?` |
| coll3.mid | O | CORRECT | CORRECT | CORRECT | PARTIAL | swiftdc `return ?` |
| coll3.isSorted | O | CORRECT | CORRECT | CORRECT | PARTIAL | swiftdc `if (?)`, `return ?` |
| coll3.bsearch | O | CORRECT | CORRECT | CORRECT | WRONG | swiftdc drops the lo+hi overflow trap (b.vs) |
| coll3.u16At | O | CORRECT | CORRECT | CORRECT | PARTIAL | swiftdc `return ?` |
| coll3.prefixCount | O | CORRECT | WRONG | CORRECT | PARTIAL | Ghidra passes the cast result (or empty storage) as the copy's owner arg; machine passes the array |
| coll3.m2 | O | CORRECT | CORRECT | CORRECT | PARTIAL | swiftdc: four traps right, `return ?` |
| coll3.atU | Osize | CORRECT | CORRECT | CORRECT | PARTIAL | Ghidra via OUTLINED_FUNCTION_0(addr); swiftdc sign test now `arg1 <ˢ 0` (right for `tbnz x1,#63`; was a plain `<` on a UInt), still `return ?`; score unchanged |
| coll3.at32 | Osize | CORRECT | CORRECT | CORRECT | PARTIAL | swiftdc `return ?` |
| coll3.closedRange | Osize | CORRECT | CORRECT | CORRECT | PARTIAL | swiftdc empty loop, `return ?` |
| coll3.revSq | Osize | CORRECT | CORRECT | CORRECT | PARTIAL | swiftdc as -O |
| coll3.lastBang | Osize | CORRECT | CORRECT | CORRECT | PARTIAL | swiftdc `return ?` |
| coll3.mod3 | Osize | CORRECT | CORRECT | CORRECT | PARTIAL | swiftdc empty loop, `return ?` |
| coll3.mid | Osize | CORRECT | CORRECT | CORRECT | PARTIAL | swiftdc `return ?` |
| coll3.isSorted | Osize | CORRECT | CORRECT | CORRECT | DECLINED | swiftdc: loop shape over raw registers and `return ?` only |
| coll3.bsearch | Osize | CORRECT | CORRECT | CORRECT | WRONG | swiftdc keeps one trap as `if (?)`, drops the other (lo+hi overflow) |
| coll3.u16At | Osize | CORRECT | CORRECT | CORRECT | PARTIAL | swiftdc `return ?` |
| coll3.prefixCount | Osize | WRONG | WRONG | CORRECT | PARTIAL | Ghidra: 4 params; prefix() given only k, Array.init given k and garbage, count read from k+0x10 |
| coll3.m2 | Osize | CORRECT | CORRECT | CORRECT | PARTIAL | swiftdc `return ?` |
| mut.push2 | Osize | CORRECT | WRONG | CORRECT | WRONG | Ghidra calls omit self (x20); swiftdc passes fabricated arg0..arg2 to _makeUniqueAndReserveCapacityIfNotUnique; Ghidra WRONG under the shared rubric: a call drops an argument the callee takes |
| mut.reserve | Osize | CORRECT | CORRECT | CORRECT | PARTIAL | swiftdc raw regs, `…` args |
| mut.clear | Osize | CORRECT | WRONG | CORRECT | PARTIAL | Ghidra malloc_size() and replaceSubrange without self/arg; Ghidra WRONG under the shared rubric: a call drops an argument the callee takes |
| mut.insertFront | Osize | CORRECT | WRONG | CORRECT | PARTIAL | Ghidra replaceSubrange without self; swiftdc `…` args; Ghidra WRONG under the shared rubric: a call drops an argument the callee takes |
| ovf.addT | O | CORRECT | CORRECT | CORRECT | WRONG | swiftdc `return (arg0 + arg1)` drops the overflow trap |
| ovf.triT | O | CORRECT | CORRECT | CORRECT | WRONG | swiftdc: loop bodies and all four overflow traps silently omitted |
| ovf.psum | O | CORRECT | CORRECT | CORRECT | WRONG | swiftdc: loop body and overflow trap silently omitted |
