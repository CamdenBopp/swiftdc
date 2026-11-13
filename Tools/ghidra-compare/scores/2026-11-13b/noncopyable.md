# Noncopyable: Ghidra 12.2 vs swiftdc

> Re-scored 2026-11-13b: swiftdc columns only, against `2026-11-13b/renders/`, by `2026-11-13b/scores/RUBRIC.md` and its addendum. Ghidra's columns are copied unchanged. A row whose swiftdc text did not change keeps its old scores. 16 rows changed score, none for the worse; one more (afterBigConsumed, nc2 -Onone) changed text only.

Inputs: `abi2/noncopyable/{ctl,nc,nc2}` at every built level (ctl -O; nc and nc2 at -Onone, -O, -Osize). `rp.swift` has no user-written function (only stored-property getters and the synthesized memberwise init), so it is not scored. Compiler-synthesized stored-property accessors, value witnesses, metadata accessors, outlined helpers and `function signature specialization` clones are skipped; explicit inits are scored. The scoring follows `ghidra/scores/RUBRIC.md`, so the four user deinits (FileDesc, Pair, Big, Handle) are listed in a separate table and kept out of the totals.

## How the rules were applied

- **Interface** is what the tool presents: Ghidra's decompiled parameter list, swiftdc's demangled header plus the `argN`/`self` values its body uses. A raw register (`in_x1`, `unaff_x20`, swiftdc `x20`/`w8`) or a `?` standing for a parameter is DECLINED. A parameter shown that the code never takes (Ghidra's by-value `FileDesc param_1` on a method whose self is x20, its five-word `Big` for an indirect Big) is WRONG.
- **Body:** a call shown with fewer arguments than the callee reads, or with an argument the callee does not take, is WRONG. A call statement where the binary returns that call's result, with no `return` shown, is WRONG (swiftdc's `sub_930 { NC.sink(?) }` at -Osize). A signatureless function that ends `return // x0 = <value>` (addendum) has its body judged on that value and its result DECLINED on the interface axis: `sub_938` at -O. Retain/release and their arguments are ignored for both tools. A result passed through an opaque `_OUTLINED_FUNCTION_n` epilogue (Ghidra at -Osize) is PARTIAL.
- **Folded (ICF) addresses:** a function whose address carries another symbol is scored against what the tool prints at that address. If the tool labels it with a different function's name (Ghidra) or `sub_<addr>` (swiftdc), interface is DECLINED; the body is CORRECT only if the printed body is right for this function too.


## Totals

125 function builds scored.

| tool | axis | CORRECT | PARTIAL | WRONG | DECLINED |
|---|---|---|---|---|---|
| Ghidra | interface | 72 | 0 | 28 | 25 |
| Ghidra | body | 73 | 11 | 39 | 2 |
| swiftdc | interface | 67 | 0 | 0 | 58 |
| swiftdc | body | 47 | 34 | 4 | 40 |

Previous swiftdc totals (2026-11-13): interface 53 / 0 / 0 / 72, body 32 / 38 / 6 / 49.

Body results by build:

| build | rows | Ghidra body C | Ghidra body W | swiftdc body C | swiftdc body W |
|---|---|---|---|---|---|
| ctl -O | 5 | 5 | 0 | 4 | 0 |
| nc -O | 21 | 14 | 6 | 8 | 0 |
| nc -Osize | 21 | 10 | 6 | 5 | 2 |
| nc -Onone | 21 | 14 | 7 | 7 | 1 |
| nc2 -O | 19 | 10 | 8 | 9 | 0 |
| nc2 -Osize | 19 | 7 | 6 | 7 | 0 |
| nc2 -Onone | 19 | 13 | 6 | 7 | 1 |

## Where swiftdc beats Ghidra

1. **Indirect (five-word) noncopyable `Big`.** Ghidra types it as a by-value struct in x0..x4, so the Int after it lands in "field b". `afterInoutBig` (-O): Ghidra `*(__int64 *)param_1.a = param_1.b; return param_1.b + 1;` swiftdc `mem64[arg0] = arg1; return (arg1 + 1)`. Truth: `str x1, [x0]; add x0, x1, #1` (big.a = k; return k + 1). The same mislabel makes `bigField`, `afterBig` and `afterBigConsumed` WRONG at every level (`return param_1.b * 5` for k*5).
2. **Noncopyable enum payload.** `Token.value()` (-O, -Osize, -Onone): Ghidra `uVar1 = (ulong)(byte)param_1.value;` so `.num(n)` returns n & 0xff. swiftdc declines (`return ?`). Truth: `ands w8, w2, #0xff; b.eq ret` returns x0 whole.
3. **Self in x20.** `Big.plusD` (-O): Ghidra `plusD(__int64 param_1, Big param_2) { long unaff_x20; return *(long *)(unaff_x20 + 0x18) + param_1; }` (an invented by-value Big, self raw). swiftdc `return (self.d + arg0)`. Truth: `ldr x8, [x20, #0x18]; add x0, x8, x0`. Same pattern on `FileDesc.bump`, `Pair.setB`, `Big.minusE`.

## Where Ghidra beats swiftdc

1. **Optional noncopyable.** `optFD` (-O): Ghidra `if ((in_x0 & 0xff00000000) == 0x100000000) _Var1 = -1; return _Var1;` (raw in_x0 but the right logic). swiftdc `return ?`. Truth: `and x8, x0, #0xff00000000; cmp x8, #0x100000000; csinv w0, w0, wzr, ne`.
2. **Load through a class reference.** `handleN` (-O): Ghidra `_swift_beginAccess(param_1.unknown + 0x10, …); return *(__int64 *)(param_1.unknown + 0x10);` swiftdc `return ?`. Truth: `ldr x0, [x19, #0x10]`. swiftdc still declines the bodies that are not a plain field of a by-value struct: the folded bare-`ret` inits and `take`, `Token.value`, `tokenKind`, `optFD`, `bigField`, `handleN`, `readView` and the generic `Box` functions account for 39 of its 40 DECLINED bodies.
3. **Folded function with a dropped return, -Osize only.** `makeAndClose`/`FileDesc.close` (one address): Ghidra `_OUTLINED_FUNCTION_6(unaff_w19 + 1)` (PARTIAL), swiftdc `sub_930 { NC.sink(?) }` with no return. Truth: `bl _OUTLINED_FUNCTION_0; add w0, w19, #1`. At -O the same pair is now right: `sub_938 { NC.sink(…)  return // x0 = (((arg0 & 0xffffffff) + 1) & 0xffffffff) }`.

Fixed since 2026-11-13: the single-value leaves (`peek`, `take`, `borrowFD`, `borrowCD2`, `consumeFD`) now show the field, e.g. `borrowFD` (-O) `return ((((arg0.fd & 0xffffffff) + 7) << 32) >>ˢ 32)` for `add w0, w0, #7`.


## Per-function scores

| function | build | Ghidra interface | Ghidra body | swiftdc interface | swiftdc body | note |
|---|---|---|---|---|---|---|
| CD.init(fd:) | ctl -O | DECLINED | CORRECT | DECLINED | DECLINED | folded with fd.getter (bare ret); Ghidra labels it init and returns fd; swiftdc prints sub_5d8 with no body |
| CD.peek() | ctl -O | CORRECT | CORRECT | CORRECT | CORRECT | now `return (self.fd << 1)` sign-extended, self in x0: matches `lsl w0,w0,#1` (was `return ?`) |
| borrowCD(_:) | ctl -O | CORRECT | CORRECT | CORRECT | CORRECT | now `return CT.plainI(arg0.fd)`: the tail call passes x0 through (was `plainI(?)`) |
| borrowCD2(_:) | ctl -O | CORRECT | CORRECT | CORRECT | CORRECT | now `return (arg0.fd + 9)` sign-extended: matches `add w0,w0,#9` (was `return ?`) |
| plainI(_:) | ctl -O | CORRECT | CORRECT | CORRECT | CORRECT |  |
| sink(_:) | nc -O | CORRECT | WRONG | CORRECT | CORRECT | Ghidra: `_print(SVar2,separator)`, terminator dropped and separator built from wrong words |
| FileDesc.init(fd:) | nc -O | DECLINED | CORRECT | DECLINED | DECLINED | folded bare ret (10 symbols); Ghidra labels it boxInt; swiftdc sub_914 empty |
| FileDesc.close() | nc -O | DECLINED | CORRECT | DECLINED | CORRECT | folded with makeAndClose; swiftdc sub_938 now ends `return // x0 = (arg0 + 1) & 0xffffffff` after sink(sext arg0): right value (`add w0,w19,#1`), no result claim, name still sub_ (was: return omitted) |
| FileDesc.take() | nc -O | DECLINED | CORRECT | DECLINED | DECLINED | folded bare ret |
| FileDesc.peek() | nc -O | CORRECT | CORRECT | CORRECT | CORRECT | now `return (self.fd << 1)` sign-extended, self in x0 (was `return ?`) |
| FileDesc.bump() | nc -O | WRONG | CORRECT | CORRECT | CORRECT | Ghidra shows a by-value FileDesc param_1 never read; self is unaff_x20 |
| borrowFD(_:) | nc -O | CORRECT | CORRECT | CORRECT | CORRECT | now `return (arg0.fd + 7)` sign-extended: matches `add w0,w0,#7` (was `return ?`) |
| consumeFD(_:) | nc -O | CORRECT | CORRECT | CORRECT | CORRECT | now `NC.sink(sext arg0.fd)`, `return arg0.fd`: matches `sxtw x0,w19; bl sink; mov x0,x19` (was `sink(?)`, `return ?`) |
| inoutFD(_:) | nc -O | CORRECT | CORRECT | CORRECT | PARTIAL | swiftdc `mem32[arg0] = w8`: load and +3 not recovered |
| makeAndClose(_:) | nc -O | CORRECT | CORRECT | DECLINED | CORRECT | folded with close; swiftdc sub_938 now shows sink(sext arg0) and `return // x0 = (arg0 + 1) & 0xffffffff`: x+1 right, no result claim (was: return omitted) |
| moveIt(_:) | nc -O | CORRECT | CORRECT | DECLINED | PARTIAL | tail call; swiftdc `return NC.consumeFD(?)` |
| Token.value() | nc -O | DECLINED | WRONG | DECLINED | DECLINED | Ghidra truncates payload to a byte: `(byte)param_1.value`, num(n) returns n&0xff; in_x1/in_w2 |
| tokenKind(_:) | nc -O | DECLINED | PARTIAL | DECLINED | DECLINED | Ghidra in_x2, table DAT_1128 not resolved to -1/1/2 |
| Box.init(_:) | nc -O | DECLINED | WRONG | DECLINED | DECLINED | folded with genericConsume; Ghidra puts metadata in param_3 and calls the witness with (src,meta) instead of (dest=x8,src,meta) |
| Box.unwrap() | nc -O | DECLINED | WRONG | DECLINED | DECLINED | Ghidra calls initializeWithTake with no arguments |
| boxInt(_:) | nc -O | CORRECT | CORRECT | DECLINED | DECLINED | folded bare ret; Ghidra chose this name; swiftdc sub_914 empty |
| genericConsume(_:) | nc -O | WRONG | WRONG | DECLINED | DECLINED | Ghidra: metadata as param_3 (is x1), witness called with wrong args |
| optFD(_:) | nc -O | DECLINED | CORRECT | DECLINED | DECLINED | Ghidra `(void)` with in_x0 but logic right; swiftdc `return ?` |
| sendIt(_:) | nc -O | CORRECT | WRONG | CORRECT | CORRECT | Ghidra calls the specialization with no argument |
| View.init(p:) | nc -O | DECLINED | CORRECT | DECLINED | DECLINED | folded bare ret |
| readView(_:) | nc -O | CORRECT | CORRECT | DECLINED | DECLINED | swiftdc `return ?` for `ldrb w0,[x0]` |
| sink(_:) | nc -Osize | CORRECT | WRONG | CORRECT | CORRECT | Ghidra print call garbled as at -O |
| FileDesc.init(fd:) | nc -Osize | DECLINED | CORRECT | DECLINED | DECLINED | folded bare ret; Ghidra labels it boxInt |
| FileDesc.close() | nc -Osize | DECLINED | PARTIAL | DECLINED | WRONG | folded with makeAndClose; Ghidra `_OUTLINED_FUNCTION_6(unaff_w19 + 1)`, sink hidden in outlined call; swiftdc sub_930 `NC.sink(?)` with no return |
| FileDesc.take() | nc -Osize | DECLINED | CORRECT | DECLINED | DECLINED | folded bare ret |
| FileDesc.peek() | nc -Osize | CORRECT | CORRECT | CORRECT | CORRECT | now `return (self.fd << 1)` sign-extended, self in x0 (was `return ?`) |
| FileDesc.bump() | nc -Osize | WRONG | CORRECT | CORRECT | CORRECT | Ghidra by-value param_1 never read; self is unaff_x20 |
| borrowFD(_:) | nc -Osize | CORRECT | CORRECT | CORRECT | CORRECT | now `return (arg0.fd + 7)` sign-extended (was `return ?`) |
| consumeFD(_:) | nc -Osize | CORRECT | WRONG | CORRECT | CORRECT | Ghidra `_OUTLINED_FUNCTION_0()` drops the fd argument and returns a void outlined epilogue; swiftdc now `NC.sink(sext arg0.fd)`, `return arg0.fd`, right through the outlined `mov x19,x0; sxtw; b sink` (was `sink(?)`, `return ?`) |
| inoutFD(_:) | nc -Osize | CORRECT | CORRECT | CORRECT | PARTIAL | swiftdc `mem32[arg0] = w8` |
| makeAndClose(_:) | nc -Osize | CORRECT | PARTIAL | DECLINED | WRONG | Ghidra unaff_w19 + 1 via outlined epilogue; swiftdc sub_930 drops the return |
| moveIt(_:) | nc -Osize | CORRECT | PARTIAL | DECLINED | PARTIAL | Ghidra inlines consumeFD into opaque outlined calls; swiftdc `return NC.consumeFD(?)` |
| Token.value() | nc -Osize | DECLINED | WRONG | DECLINED | DECLINED | Ghidra byte-truncates the num payload |
| tokenKind(_:) | nc -Osize | DECLINED | PARTIAL | DECLINED | DECLINED | Ghidra unresolved table |
| Box.init(_:) | nc -Osize | DECLINED | WRONG | DECLINED | PARTIAL | folded; Ghidra wrong witness args; swiftdc sub_a14 `OUTLINED_FUNCTION_1(arg0, arg1)` (x8 result not shown) |
| Box.unwrap() | nc -Osize | DECLINED | WRONG | DECLINED | DECLINED | Ghidra calls witness with no arguments |
| boxInt(_:) | nc -Osize | CORRECT | CORRECT | DECLINED | DECLINED | folded bare ret |
| genericConsume(_:) | nc -Osize | WRONG | WRONG | DECLINED | PARTIAL | Ghidra metadata as param_3; swiftdc sub_a14 outlined call only |
| optFD(_:) | nc -Osize | DECLINED | CORRECT | DECLINED | DECLINED | Ghidra in_x0; swiftdc `return ?` |
| sendIt(_:) | nc -Osize | CORRECT | PARTIAL | CORRECT | DECLINED | Ghidra returns count through opaque outlined epilogue; swiftdc `return ?` |
| View.init(p:) | nc -Osize | DECLINED | CORRECT | DECLINED | DECLINED | folded bare ret |
| readView(_:) | nc -Osize | CORRECT | CORRECT | DECLINED | DECLINED | swiftdc `return ?` |
| sink(_:) | nc -Onone | CORRECT | WRONG | DECLINED | PARTIAL | Ghidra renders three `_print` calls (the two default-argument calls mislabelled); swiftdc `print([…], ?, ?)` |
| FileDesc.init(fd:) | nc -Onone | CORRECT | CORRECT | DECLINED | DECLINED | swiftdc `return ?` |
| FileDesc.close() | nc -Onone | CORRECT | CORRECT | CORRECT | PARTIAL | swiftdc now `deinit(self.fd & 0xffffffff)` (right: `ldur w0; bl deinit`), still `return ?` for fd+1 (was `deinit(?)`) |
| FileDesc.take() | nc -Onone | CORRECT | CORRECT | CORRECT | CORRECT | now `return self.fd`, self in x0 (was `return ?`) |
| FileDesc.peek() | nc -Onone | CORRECT | CORRECT | CORRECT | CORRECT | now `return (2 * self.fd)` sign-extended: matches `mul w0,w8,w0` (was `return ?`) |
| FileDesc.bump() | nc -Onone | WRONG | CORRECT | CORRECT | CORRECT | Ghidra by-value param_1 never read; self is unaff_x20 |
| borrowFD(_:) | nc -Onone | CORRECT | CORRECT | CORRECT | CORRECT | now `return (arg0.fd + 7)` sign-extended (was `return ?`) |
| consumeFD(_:) | nc -Onone | CORRECT | CORRECT | CORRECT | CORRECT | now `deinit(arg0.fd & 0xffffffff)`, `return sext(arg0.fd)`: matches the spilled w0 reloaded around `bl deinit` (was `deinit(?)`, `return ?`) |
| inoutFD(_:) | nc -Onone | CORRECT | CORRECT | CORRECT | CORRECT |  |
| makeAndClose(_:) | nc -Onone | CORRECT | CORRECT | CORRECT | PARTIAL | swiftdc `return close(self: ?)` |
| moveIt(_:) | nc -Onone | CORRECT | CORRECT | CORRECT | PARTIAL | swiftdc `return consumeFD(?)` |
| Token.value() | nc -Onone | DECLINED | WRONG | DECLINED | DECLINED | Ghidra byte-truncates the num payload; swiftdc `return ?` |
| tokenKind(_:) | nc -Onone | DECLINED | CORRECT | DECLINED | DECLINED | Ghidra right via in_w2; swiftdc `return ?` |
| Box.init(_:) | nc -Onone | WRONG | WRONG | DECLINED | DECLINED | Ghidra takes metadata from param_3 (x2), truth x1; swiftdc three unresolved calls |
| Box.unwrap() | nc -Onone | DECLINED | WRONG | DECLINED | DECLINED | Ghidra drops the metadata argument of initializeWithTake |
| boxInt(_:) | nc -Onone | CORRECT | WRONG | DECLINED | PARTIAL | Ghidra `Box::_init(auStack_38, param_1, Int)`: x1 is the metadata, not x; swiftdc `init(local_40)`, unwrap(), `return ?` |
| genericConsume(_:) | nc -Onone | WRONG | WRONG | DECLINED | PARTIAL | Ghidra metadata from param_3; swiftdc recovers src=arg0 in the first witness call |
| optFD(_:) | nc -Onone | DECLINED | CORRECT | DECLINED | PARTIAL | swiftdc `if (w8 != 0) take(self: ?)`, `return ?` |
| sendIt(_:) | nc -Onone | CORRECT | CORRECT | CORRECT | CORRECT |  |
| View.init(p:) | nc -Onone | CORRECT | CORRECT | DECLINED | DECLINED | swiftdc `return ?` |
| readView(_:) | nc -Onone | CORRECT | WRONG | DECLINED | WRONG | Ghidra two `_load` calls with metadata as arguments; swiftdc `load<A>(fromByteOffset:as:)()` with no arguments |
| sink(_:) | nc2 -O | CORRECT | WRONG | CORRECT | CORRECT | Ghidra print call garbled |
| Res.init() | nc2 -O | CORRECT | CORRECT | DECLINED | PARTIAL | swiftdc `mem64[x20 + 0x10] = 0`, `return ?` |
| Pair.init(a:b:) | nc2 -O | DECLINED | DECLINED | DECLINED | DECLINED | folded bare ret; Ghidra shows it as Handle.init returning one word; swiftdc sub_ empty |
| Big.init(_:) | nc2 -O | CORRECT | CORRECT | CORRECT | CORRECT |  |
| Handle.init(_:) | nc2 -O | CORRECT | CORRECT | DECLINED | DECLINED | folded bare ret; swiftdc sub_ empty |
| bigField(_:_:) | nc2 -O | WRONG | WRONG | DECLINED | DECLINED | Ghidra passes Big by value: `*(param_1.a + 0x10) + param_1.b` labels k as big.b; swiftdc `return ?` |
| afterInoutBig(_:_:) | nc2 -O | WRONG | WRONG | CORRECT | CORRECT | Ghidra `*(param_1.a) = param_1.b`: k labelled big.b |
| handleN(_:) | nc2 -O | CORRECT | CORRECT | DECLINED | DECLINED | swiftdc `return ?` |
| dropHandle(_:_:) | nc2 -O | CORRECT | CORRECT | DECLINED | PARTIAL | swiftdc `mem64[x20 + 0x10] = x8`, `return arg1` |
| Pair.twice(_:) | nc2 -O | CORRECT | CORRECT | CORRECT | CORRECT |  |
| Big.plusD(_:) | nc2 -O | WRONG | CORRECT | CORRECT | CORRECT | Ghidra adds a by-value Big param_2 never read; self is unaff_x20 |
| Pair.setB(_:) | nc2 -O | WRONG | CORRECT | CORRECT | PARTIAL | Ghidra by-value Pair param_2 not taken; swiftdc `sub_b00(arg0)` (folded setter unnamed) |
| sink(_:) | nc2 -Osize | CORRECT | WRONG | CORRECT | CORRECT | Ghidra print call garbled |
| Res.init() | nc2 -Osize | CORRECT | CORRECT | DECLINED | PARTIAL | swiftdc `mem64[x20 + 0x10] = 0`, `return ?` |
| Pair.init(a:b:) | nc2 -Osize | DECLINED | DECLINED | DECLINED | DECLINED | folded bare ret; Ghidra shows it as Handle.init returning one word; swiftdc sub_ empty |
| Big.init(_:) | nc2 -Osize | CORRECT | CORRECT | CORRECT | CORRECT |  |
| Handle.init(_:) | nc2 -Osize | CORRECT | CORRECT | DECLINED | DECLINED | folded bare ret; swiftdc sub_ empty |
| bigField(_:_:) | nc2 -Osize | WRONG | WRONG | DECLINED | DECLINED | Ghidra passes Big by value: `*(param_1.a + 0x10) + param_1.b` labels k as big.b; swiftdc `return ?` |
| afterInoutBig(_:_:) | nc2 -Osize | WRONG | WRONG | CORRECT | CORRECT | Ghidra `*(param_1.a) = param_1.b`: k labelled big.b |
| handleN(_:) | nc2 -Osize | CORRECT | PARTIAL | DECLINED | DECLINED | swiftdc `return ?` |
| dropHandle(_:_:) | nc2 -Osize | CORRECT | PARTIAL | DECLINED | PARTIAL | swiftdc `mem64[x20 + 0x10] = x8`, `return arg1` |
| Pair.twice(_:) | nc2 -Osize | CORRECT | CORRECT | CORRECT | CORRECT |  |
| Big.plusD(_:) | nc2 -Osize | WRONG | CORRECT | CORRECT | CORRECT | Ghidra adds a by-value Big param_2 never read; self is unaff_x20 |
| Pair.setB(_:) | nc2 -Osize | WRONG | CORRECT | CORRECT | PARTIAL | Ghidra by-value Pair param_2 not taken; swiftdc `sub_b00(arg0)` (folded setter unnamed) |
| afterPair(_:_:) | nc2 -O | CORRECT | WRONG | CORRECT | CORRECT | Ghidra ignores the dead-arg specialization: builds `Pair(a: k, b: p.b)` and calls `_afterPair(PVar2, k)`; swiftdc `return specialization(arg1)` |
| afterBig(_:_:) | nc2 -O | WRONG | WRONG | CORRECT | CORRECT | Ghidra passes Big as five words; result reads as big.b*5 |
| afterBigConsumed(_:_:) | nc2 -O | WRONG | WRONG | CORRECT | PARTIAL | Ghidra `return param_1.b * 7` (k labelled big.b); swiftdc `NC2.sink(?)`, k*7 right |
| callPair(_:_:) | nc2 -O | CORRECT | WRONG | CORRECT | CORRECT | Ghidra `_afterPair(Pair(a: 11, b: y), in_x2)`: 11 placed in the pair |
| callBig(_:) | nc2 -O | CORRECT | WRONG | CORRECT | CORRECT | Ghidra builds a Big from in_x1..in_x5 with a = 13 |
| Pair.sum(_:) | nc2 -O | CORRECT | CORRECT | CORRECT | PARTIAL | swiftdc `return ?` |
| Big.minusE(_:) | nc2 -O | WRONG | CORRECT | CORRECT | PARTIAL | Ghidra by-value Big param_2 not taken; swiftdc `return ?` |
| afterPair(_:_:) | nc2 -Osize | CORRECT | CORRECT | CORRECT | CORRECT |  |
| afterBig(_:_:) | nc2 -Osize | WRONG | WRONG | CORRECT | CORRECT | Ghidra `return param_1.b * 5` (k labelled big.b) |
| afterBigConsumed(_:_:) | nc2 -Osize | WRONG | WRONG | CORRECT | PARTIAL | Ghidra `param_1.b * 7`; swiftdc `NC2.sink(?)` |
| callPair(_:_:) | nc2 -Osize | CORRECT | PARTIAL | CORRECT | PARTIAL | Ghidra afterPair args right but sink hidden in outlined call and result discarded for an opaque epilogue; swiftdc `afterPair(?, 11)` |
| callBig(_:) | nc2 -Osize | CORRECT | WRONG | CORRECT | PARTIAL | Ghidra Big by value with b = 13 and k = in_x5; swiftdc `afterBig(?, 13)` |
| Pair.sum(_:) | nc2 -Osize | CORRECT | PARTIAL | CORRECT | PARTIAL | Ghidra sum through outlined epilogue; swiftdc `return ?` |
| Big.minusE(_:) | nc2 -Osize | WRONG | PARTIAL | CORRECT | PARTIAL | Ghidra by-value Big param_2 not taken, return through outlined epilogue; swiftdc `return ?` |
| sink(_:) | nc2 -Onone | CORRECT | WRONG | DECLINED | PARTIAL | Ghidra three `_print` calls; swiftdc `print([…], ?, ?)` |
| Res.init() | nc2 -Onone | CORRECT | CORRECT | DECLINED | PARTIAL | swiftdc `mem64[x0 + 0x10] = 0`, `return ?` |
| Pair.init(a:b:) | nc2 -Onone | CORRECT | CORRECT | DECLINED | DECLINED | swiftdc `return ?` |
| Big.init(_:) | nc2 -Onone | CORRECT | CORRECT | CORRECT | CORRECT |  |
| Handle.init(_:) | nc2 -Onone | CORRECT | CORRECT | DECLINED | DECLINED | swiftdc `return ?` |
| afterPair(_:_:) | nc2 -Onone | CORRECT | CORRECT | CORRECT | CORRECT |  |
| afterBig(_:_:) | nc2 -Onone | WRONG | WRONG | CORRECT | CORRECT | Ghidra `return param_1.b * 5` |
| afterBigConsumed(_:_:) | nc2 -Onone | WRONG | WRONG | CORRECT | PARTIAL | Ghidra `param_1.b * 7`; swiftdc now `memcpy(local_48, arg0, 40)` (right, was `?`), but `Big.deinit()` still shows no self (x20 = &local_48); score unchanged |
| bigField(_:_:) | nc2 -Onone | WRONG | WRONG | DECLINED | DECLINED | Ghidra labels k as big.b; swiftdc `return ?` |
| afterInoutBig(_:_:) | nc2 -Onone | WRONG | WRONG | CORRECT | CORRECT | Ghidra labels k as big.b |
| callPair(_:_:) | nc2 -Onone | CORRECT | CORRECT | CORRECT | PARTIAL | swiftdc `afterPair(?, 11)`, `Pair.deinit(?, ?)` |
| callBig(_:) | nc2 -Onone | CORRECT | WRONG | CORRECT | PARTIAL | Ghidra `afterBig(Big{a: &copy, b: 13, c: 40, …}, in_x5)`; swiftdc `afterBig(?, 13)` |
| handleN(_:) | nc2 -Onone | CORRECT | CORRECT | DECLINED | DECLINED | swiftdc `return ?` |
| dropHandle(_:_:) | nc2 -Onone | CORRECT | CORRECT | CORRECT | PARTIAL | swiftdc `Handle.deinit(?)` |
| Pair.sum(_:) | nc2 -Onone | CORRECT | CORRECT | CORRECT | WRONG | swiftdc `Pair.deinit(self.a, self.b, self.b)`: a third argument deinit does not take; `return ?` |
| Pair.twice(_:) | nc2 -Onone | CORRECT | CORRECT | CORRECT | CORRECT |  |
| Pair.setB(_:) | nc2 -Onone | WRONG | CORRECT | CORRECT | CORRECT | Ghidra by-value Pair param_2 not taken |
| Big.plusD(_:) | nc2 -Onone | WRONG | CORRECT | CORRECT | CORRECT | Ghidra by-value Big param_2 not taken |
| Big.minusE(_:) | nc2 -Onone | WRONG | CORRECT | CORRECT | PARTIAL | Ghidra by-value Big param_2 not taken; swiftdc `return ?` |

## User-written deinits (outside the totals)

RUBRIC.md skips deinits, so these rows are not counted above. They are user code in this area (each states the sink call it makes), so they are listed for reference.

| function | build | Ghidra interface | Ghidra body | swiftdc interface | swiftdc body | note |
|---|---|---|---|---|---|---|
| FileDesc.deinit | nc -O | CORRECT | CORRECT | DECLINED | PARTIAL | swiftdc `NC.sink(?)` |
| FileDesc.deinit | nc -Osize | CORRECT | CORRECT | DECLINED | PARTIAL | swiftdc `NC.sink(?)` |
| FileDesc.deinit | nc -Onone | CORRECT | CORRECT | DECLINED | PARTIAL | swiftdc `NC.sink(?)` |
| Pair.deinit | nc2 -O | DECLINED | DECLINED | DECLINED | PARTIAL | Ghidra emits no function for the tail call; swiftdc `NC2.sink(?)` |
| Big.deinit | nc2 -O | DECLINED | CORRECT | CORRECT | CORRECT | Ghidra `(void)` with unaff_x20 |
| Handle.deinit | nc2 -O | CORRECT | CORRECT | DECLINED | PARTIAL | swiftdc `mem64[x19 + 0x10] = x8` |
| Pair.deinit | nc2 -Osize | DECLINED | DECLINED | DECLINED | PARTIAL | Ghidra emits no function for the tail call; swiftdc `NC2.sink(?)` |
| Big.deinit | nc2 -Osize | DECLINED | CORRECT | CORRECT | CORRECT | Ghidra `(void)` with unaff_x20 |
| Handle.deinit | nc2 -Osize | CORRECT | CORRECT | DECLINED | PARTIAL | swiftdc `mem64[x19 + 0x10] = x8` |
| Pair.deinit | nc2 -Onone | WRONG | CORRECT | DECLINED | PARTIAL | Ghidra shows one param, self is x0,x1; swiftdc `NC2.sink(?)` |
| Big.deinit | nc2 -Onone | DECLINED | CORRECT | CORRECT | PARTIAL | Ghidra unaff_x20; swiftdc `memcpy(local_38, self, 40)`, `sink(?)` |
| Handle.deinit | nc2 -Onone | CORRECT | CORRECT | DECLINED | PARTIAL | swiftdc `mem64[x9 + 0x10] = x8` |
