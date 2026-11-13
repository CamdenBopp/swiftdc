// LEVELS: O Osize Onone
// Async functions: split into funclets at each suspension point; the callee
// context goes in x22 and each await stores (parent context, resume funclet)
// into the new context before tail-calling the async callee.
// TRUE behaviour:
//   fetch(i) never suspends and returns 3i.
//   sumFetched(n): hops to the executor, traps if n < 0, returns 0 if n == 0,
//   otherwise awaits fetch(0), and the await-resume funclet adds the result
//   and, while i + 1 != n, awaits fetch(i + 1) again with ITSELF as the resume
//   funclet: the loop's await is inside the resume funclet, so that funclet is
//   entered from two awaits (the first and its own).
//   twoFetches: let a = await fetch(5); let b = await fetch(a); return a + b.
//   Two suspension points at every level.
// EXPECT structured * fetch(Swift.Int) :: no suspension point
// EXPECT structured O,Onone twoFetches :: let awaited1 = await Asyncs.fetch(5)
// EXPECT structured O,Onone twoFetches :: let awaited2 = await Asyncs.fetch(awaited1)
// EXPECT structured * twoFetches :: 2 resume funclet(s)
// FORBID structured * Asyncs.twoFetches :: no suspension point
// EXPECT structured O sumFetched :: let awaited2 = await Asyncs.fetch(0)
// EXPECT structured Osize sumFetched :: await Asyncs.fetch(0)
// EXPECT structured O,Osize sumFetched :: 2 resume funclet(s)
// The await inside the loop (resume funclet #2 at -O/-Osize, #3 at -Onone):
// EXPECT structured O,Osize (2) await resume partial function for Asyncs.sumFetched :: await Asyncs.fetch(
// EXPECT structured Onone (3) suspend resume partial function for Asyncs.sumFetched :: await Asyncs.fetch(
// FORBID structured O,Osize (2) await resume partial function for Asyncs.sumFetched :: re:entered when the await in 0x[0-9a-f]+ returns
// -Osize outlines the context setup. OUTLINED_FUNCTION_2 (str x22, [sp, #8];
// add x29, sp, #0x10; ret) does not write x0, so x0 after it is still the
// awaited value: it is not a result of OUTLINED_FUNCTION_2.
// FORBID structured Osize (1) await resume partial function for Asyncs.twoFetches :: let r0 = OUTLINED_FUNCTION_2()
// FORBID structured Osize (1) await resume partial function for Asyncs.twoFetches :: fetch(r0)
// OUTLINED_FUNCTION_3 (stp x22, x8, [x0]; mov x22, x0; ret) is not a Swift
// function: its callers put the resume funclet's address in x8, not an
// indirect-result address.
// FORBID structured Osize _OUTLINED_FUNCTION_3 :: &result
@inline(never) public func fetch(_ i: Int) async -> Int { i &* 3 }
public func sumFetched(_ n: Int) async -> Int { var t = 0; for i in 0..<n { t &+= await fetch(i) }; return t }
public func twoFetches() async -> Int { let a = await fetch(5); let b = await fetch(a); return a &+ b }
