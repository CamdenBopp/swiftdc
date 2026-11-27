// F4: closures and function values at the machine level (-Onone, -O, -Osize).
//
// Every function under test takes three Ints (a, b, c in x0, x1, x2),
// builds a function value, hands it to an opaque invoker in f4support.swift
// (a different file, compiled without whole-module optimization, so the
// call through the value is a real `blr` with the context in x20), and
// returns one Int that depends on every capture and every argument with a
// distinct weight. All arithmetic wraps. Each comment gives the machine
// shape the function is meant to produce and its exact result.
//
// tNN functions are the hypotheses; cNN functions are the easy controls.

// ---------------------------------------------------------------- captures

// No capture: thin function, context word null (x20 = 0 at the blr).
// a*3 + 1001 + b*5 + c*7
@inline(never) public func t01_noCapture(_ a: Int, _ b: Int, _ c: Int) -> Int {
    invoke1({ x in x &* 3 &+ 1001 }, a) &+ b &* 5 &+ c &* 7
}

// One Int, non-escaping: the context is built on the caller's stack
// (a fake heap header then the Int at +16); closure body takes (x, a).
// b*3 + a*5 + c*7 + 1002
@inline(never) public func t02_oneIntStack(_ a: Int, _ b: Int, _ c: Int) -> Int {
    invoke1({ x in x &* 3 &+ a &* 5 }, b) &+ c &* 7 &+ 1002
}

// Three Ints, non-escaping: stack context with captures at +16, +24, +32.
// (a^c)*2 + a*3 + b*5 + c*7 + 1003
@inline(never) public func t03_threeIntsStack(_ a: Int, _ b: Int, _ c: Int) -> Int {
    invoke1({ x in x &* 2 &+ a &* 3 &+ b &* 5 &+ c &* 7 }, a ^ c) &+ 1003
}

// One Int, escaping: swift_allocObject of 24 bytes, capture at +16, a
// partial-apply forwarder loads it and passes it as the trailing argument.
// b*11 + a*13 + c*17 + 1004
@inline(never) public func t04_oneIntHeap(_ a: Int, _ b: Int, _ c: Int) -> Int {
    invokeEsc({ x in x &* 11 &+ a &* 13 }, b) &+ c &* 17 &+ 1004
}

// Three Ints, escaping: 40-byte box, captures at +16, +24, +32.
// (a-b)*2 + a*11 + b*13 + c*17 + 1005
@inline(never) public func t05_threeIntsHeap(_ a: Int, _ b: Int, _ c: Int) -> Int {
    invokeEsc({ x in x &* 2 &+ a &* 11 &+ b &* 13 &+ c &* 17 }, a &- b) &+ 1005
}

// One class reference and nothing else: no box, the context IS the Cell.
// The forwarder gets the Cell in x20; [x20+16] is Cell.v, not a capture slot.
// a*53 + b*59 + c*61 + 1006
@inline(never) public func t06_classRefOnly(_ a: Int, _ b: Int, _ c: Int) -> Int {
    let o = Cell(a, b)
    return invokeEsc({ x in o.v &* 53 &+ o.w &* 59 &+ x &* 61 }, c) &+ 1006
}

// A class reference and an Int: a real box, Cell at +16, Int at +24.
// a*2 + b*3 + c*15 + (a^b)*7 + 1007
@inline(never) public func t07_classRefAndInt(_ a: Int, _ b: Int, _ c: Int) -> Int {
    let o = Cell(a, b)
    let k = c &* 3
    return invokeEsc({ x in o.v &* 2 &+ o.w &* 3 &+ k &* 5 &+ x &* 7 }, a ^ b) &+ 1007
}

// A two-word struct: box with lo at +16, hi at +24.
// a*19 + b*23 + c*29 + 1008
@inline(never) public func t08_structPair(_ a: Int, _ b: Int, _ c: Int) -> Int {
    let p = Pair(lo: a, hi: b)
    return invokeEsc({ x in p.lo &* 19 &+ p.hi &* 23 &+ x &* 29 }, c) &+ 1008
}

// A five-word struct: box with the fields at +16 … +48.
// a*2 + b*3 + c*5 + (a+1)*7 + (b+2)*11 + (c^9)*13 + 1009
@inline(never) public func t09_structFive(_ a: Int, _ b: Int, _ c: Int) -> Int {
    let f = Five(a: a, b: b, c: c, d: a &+ 1, e: b &+ 2)
    return invokeEsc({ x in f.a &* 2 &+ f.b &* 3 &+ f.c &* 5 &+ f.d &* 7 &+ f.e &* 11 &+ x &* 13 }, c ^ 9) &+ 1009
}

// One mutable Int shared by two escaping closures: a heap box for n, each
// closure's context is that box (single refcounted capture). Order matters.
// n1 = a*9 + b; n2 = (n1^c)*5; n3 = n2*9 + c
// n1 + n2*7 + n3*11 + n3*13 + 1010
@inline(never) public func t10_sharedBox(_ a: Int, _ b: Int, _ c: Int) -> Int {
    var n = a
    let add: (Int) -> Int = { x in n = n &* 9 &+ x; return n }
    let mul: (Int) -> Int = { x in n = (n ^ x) &* 5; return n }
    let r1 = invokeEsc(add, b)
    let r2 = invokeEsc(mul, c)
    let r3 = invokeEsc(add, c)
    return r1 &+ r2 &* 7 &+ r3 &* 11 &+ n &* 13 &+ 1010
}

// A mutable Int shared by two non-escaping closure literals: captured by
// address, n stays on the caller's stack and each context holds &n.
// n1 = a*7 - b; n2 = n1*5 + c
// (n1^1)*3 + (n2^2)*5 + n2 + 1011
@inline(never) public func t11_inoutStack(_ a: Int, _ b: Int, _ c: Int) -> Int {
    var n = a
    let r1 = invoke1({ x in n = n &* 7 &- x; return n ^ 1 }, b)
    let r2 = invoke1({ x in n = n &* 5 &+ x; return n ^ 2 }, c)
    return r1 &* 3 &+ r2 &* 5 &+ n &+ 1011
}

// self of a class: the closure made by Cell.makeAdder has the Cell as its
// context. a*11 + b*13 + c + 1012
@inline(never) public func t12_selfClass(_ a: Int, _ b: Int, _ c: Int) -> Int {
    let f = Cell(a, b).makeAdder()
    return invokeEsc(f, c) &+ 1012
}

// self of a struct: Scale.makeMixer boxes a copy (m at +16, n at +24).
// a*17 + b*19 + c*23 + 1013
@inline(never) public func t13_selfStruct(_ a: Int, _ b: Int, _ c: Int) -> Int {
    let f = Scale(m: a, n: b).makeMixer()
    return invokeEsc(f, c) &+ 1013
}

// A weak capture: the box holds a weak reference (swift_weakInit), the
// body does swift_weakLoadStrong and branches on nil. Called once with
// the Cell alive and once after it is released.
// (a*3 + b*5 + c)*3 + (c*7 - 1) + 1014
@inline(never) public func t14_weak(_ a: Int, _ b: Int, _ c: Int) -> Int {
    var o: Cell? = Cell(a, b)
    let f: (Int) -> Int = { [weak o] x in
        if let o { return o.v &* 3 &+ o.w &* 5 &+ x }
        return x &* 7 &- 1
    }
    var r1 = 0
    withExtendedLifetime(o) { r1 = invokeEsc(f, c) }
    o = nil
    let r2 = invokeEsc(f, c)
    return r1 &* 3 &+ r2 &+ 1014
}

// An unowned capture: the box holds an unowned reference
// (swift_unownedRetain / swift_unownedRetainStrong in the body).
// a*23 + b*29 + c*31 + 1015
@inline(never) public func t15_unowned(_ a: Int, _ b: Int, _ c: Int) -> Int {
    let o = Cell(a, b)
    let f: (Int) -> Int = { [unowned o] x in o.v &* 23 &+ o.w &* 29 &+ x &* 31 }
    let r = withExtendedLifetime(o) { invokeEsc(f, c) }
    return r &+ 1015
}

// ------------------------------------------------- argument and result types

// Returns a two-register struct: lo in x0, hi in x1 after the blr.
// lo = c*3 + a, hi = c*5 - b;  lo*7 + hi*11 + 1016
@inline(never) public func t16_returnsPair(_ a: Int, _ b: Int, _ c: Int) -> Int {
    let p = invokePair({ x in Pair(lo: x &* 3 &+ a, hi: x &* 5 &- b) }, c)
    return p.lo &* 7 &+ p.hi &* 11 &+ 1016
}

// Takes a two-register struct: lo in x0, hi in x1, the capture after them.
// b*3 + c*5 + a*7 + 1017
@inline(never) public func t17_takesPair(_ a: Int, _ b: Int, _ c: Int) -> Int {
    invokeWithPair({ p in p.lo &* 3 &+ p.hi &* 5 &+ a &* 7 }, Pair(lo: b, hi: c)) &+ 1017
}

// Returns five words through x8.
// f = (c, c+a, c*b, a-b, c^a);  f.a*2 + f.b*3 + f.c*5 + f.d*7 + f.e*11 + 1018
@inline(never) public func t18_returnsFive(_ a: Int, _ b: Int, _ c: Int) -> Int {
    let f = invokeFive({ x in Five(a: x, b: x &+ a, c: x &* b, d: a &- b, e: x ^ a) }, c)
    return f.a &* 2 &+ f.b &* 3 &+ f.c &* 5 &+ f.d &* 7 &+ f.e &* 11 &+ 1018
}

// Takes five words by address in x0.
// a*13 + b*11 + c*7 + (a^b)*5 + (b^c)*3 + a + 1019
@inline(never) public func t19_takesFive(_ a: Int, _ b: Int, _ c: Int) -> Int {
    invokeWithFive({ f in f.a &* 13 &+ f.b &* 11 &+ f.c &* 7 &+ f.d &* 5 &+ f.e &* 3 &+ a },
                   Five(a: a, b: b, c: c, d: a ^ b, e: b ^ c)) &+ 1019
}

// Returns Int?: payload in x0, tag in w1 (1 = nil).
// b odd: (b*3 + a)*5 + c + 1020.  b even: c*7 - a + 20.
@inline(never) public func t20_returnsOptional(_ a: Int, _ b: Int, _ c: Int) -> Int {
    let r = invokeOpt({ x in x & 1 == 0 ? nil : x &* 3 &+ a }, b)
    if let r { return r &* 5 &+ c &+ 1020 }
    return c &* 7 &- a &+ 20
}

// Takes Int?: payload in x0, tag in w1, the capture in x2.
// b odd: c*3 + a*5 + 1021.  b even: a*7 - 21 + 1021.
@inline(never) public func t21_takesOptional(_ a: Int, _ b: Int, _ c: Int) -> Int {
    invokeWithOpt({ o in
        if let o { return o &* 3 &+ a &* 5 }
        return a &* 7 &- 21
    }, b & 1 == 0 ? nil : c) &+ 1021
}

// ------------------------------------------------------ partial application

// `o.scale` on a final class: the context is the Cell, the forwarder can
// tail-jump to the method with x20 untouched. a*3 + b*5 + c*7 + 1022
@inline(never) public func t22_methodFinal(_ a: Int, _ b: Int, _ c: Int) -> Int {
    let o = Cell(a, b)
    let f = o.scale
    return invokeEsc(f, c) &+ 1022
}

// `o.combine`, two arguments: x in x0, y in x1 must stay in order through
// the forwarder. a*2 + b*3 + c*5 + (c^a)*7 + 1023
@inline(never) public func t23_methodTwoArgs(_ a: Int, _ b: Int, _ c: Int) -> Int {
    let o = Cell(a, b)
    let f = o.combine
    return invokeEsc2(f, c, c ^ a) &+ 1023
}

// `n.weigh` on a non-final class: the forwarder loads the vtable entry.
// a even (Node): b*17 + c*19 + 1024.  a odd (SubNode): b*23 - c*29 + 1024.
@inline(never) public func t24_methodVTable(_ a: Int, _ b: Int, _ c: Int) -> Int {
    let n: Node = a & 1 == 0 ? Node(k: b) : SubNode(k: b)
    let f = n.weigh
    return invokeEsc(f, c) &+ 1024
}

// `s.mix` on a two-word struct: a box holding m and n; the forwarder passes
// x in x0 and self's two words after it. a*3 - b*5 + c*11 + 1025
@inline(never) public func t25_methodStruct(_ a: Int, _ b: Int, _ c: Int) -> Int {
    let s = Scale(m: a, n: b)
    let f = s.mix
    return invokeEsc(f, c) &+ 1025
}

// `Cell.weight` unapplied: (Cell) -> (Int) -> Int, a thin curry thunk that
// returns the bound method. a*43 + b*47 + c + 1026
@inline(never) public func t26_methodUnapplied(_ a: Int, _ b: Int, _ c: Int) -> Int {
    let u = Cell.weight
    return invokeUnapplied(u, Cell(a, b), c) &+ 1026
}

// p*31 + q*37 + r*41, one argument at a time.
@inline(never) func curry3(_ p: Int) -> (Int) -> (Int) -> Int {
    return { q in { r in p &* 31 &+ q &* 37 &+ r &* 41 } }
}
// A curried function applied in three steps: each step boxes one more Int.
// a*31 + b*37 + c*41 + 1027
@inline(never) public func t27_curried(_ a: Int, _ b: Int, _ c: Int) -> Int {
    let f = curry3(a)
    let g = invokeMake(f, b)
    return invokeEsc(g, c) &+ 1027
}

// A closure made in an unspecialized generic function: its box carries the
// type metadata and witness table beside the value.
// (a*2 + b*7 + c*13)*3 + 29 + 1028
@inline(never) public func t28_genericClosure(_ a: Int, _ b: Int, _ c: Int) -> Int {
    let f = makeWeigher(Scale(m: a, n: b))
    return invokeEsc(f, c) &+ 1028
}

// A witness method partially applied to a generic value.
// a*2 + b*7 + c*13 + 1029
@inline(never) public func t29_genericWitness(_ a: Int, _ b: Int, _ c: Int) -> Int {
    let f = bindWitness(Scale(m: a, n: b))
    return invokeEsc(f, c) &+ 1029
}

// A protocol method partially applied to an existential.
// a even (Scale): a*2 + b*7 + c*13 + 1030.  a odd (Cell): a*43 + b*47 + c + 1030.
@inline(never) public func t30_existentialMethod(_ a: Int, _ b: Int, _ c: Int) -> Int {
    let w: any Weighted = a & 1 == 0 ? Scale(m: a, n: b) : Cell(a, b)
    let f = w.weight
    return invokeEsc(f, c) &+ 1030
}

// ------------------------------------------------------------- conversions

// x*3 + 31
@inline(never) func plainTriple(_ x: Int) -> Int { x &* 3 &+ 31 }
// p*11 + q*13
@inline(never) func twoArg(_ p: Int, _ q: Int) -> Int { p &* 11 &+ q &* 13 }

// A named function as a thick value: its address and a null context.
// a*3 + 31 + b*3 + c*5 + 1031
@inline(never) public func t31_thinToThick(_ a: Int, _ b: Int, _ c: Int) -> Int {
    invoke1(plainTriple, a) &+ b &* 3 &+ c &* 5 &+ 1031
}

// A closure literal as a C function pointer: a `To`-style C entry.
// a*3 - b*5 + c*7 + 1032
@inline(never) public func t32_cPointerLiteral(_ a: Int, _ b: Int, _ c: Int) -> Int {
    invokeC({ x, y in x &* 3 &- y &* 5 }, a, b) &+ c &* 7 &+ 1032
}

// A named Swift function as a C function pointer, through its C thunk.
// b*11 + c*13 + a*3 + 1033
@inline(never) public func t33_cPointerNamed(_ a: Int, _ b: Int, _ c: Int) -> Int {
    invokeC(twoArg, b, c) &+ a &* 3 &+ 1033
}

// A block with captures: a stack block literal whose invoke function
// reaches the Swift closure through the block's captured context.
// c*3 + a*5 + b*7 + 1034
@inline(never) public func t34_blockCapture(_ a: Int, _ b: Int, _ c: Int) -> Int {
    let blk: @convention(block) (Int) -> Int = { x in x &* 3 &+ a &* 5 &+ b &* 7 }
    return invokeBlock(blk, c) &+ 1034
}

// A block with no capture. a*37 + 35 + b*3 + c*5 + 1035
@inline(never) public func t35_blockNoCapture(_ a: Int, _ b: Int, _ c: Int) -> Int {
    invokeBlock({ x in x &* 37 &+ 35 }, a) &+ b &* 3 &+ c &* 5 &+ 1035
}

// ----------------------------------------------------------------- storage

// A closure in a struct field: Holder is three words (fn, context, k).
// (c*3 + a)*5 + b*7 + 1036
@inline(never) public func t36_structField(_ a: Int, _ b: Int, _ c: Int) -> Int {
    let h = Holder(f: { x in x &* 3 &+ a }, k: b)
    return runHolder(h, c) &+ 1036
}

// A closure in an enum payload; the case is picked by a & 3.
// 0: b*2 + c + 1037.  1: (c*9 + b)*3 + 1037.  2, 3: (c*5 - a*7 + b)*5 + 1037.
@inline(never) public func t37_enumPayload(_ a: Int, _ b: Int, _ c: Int) -> Int {
    let op: Op
    switch a & 3 {
    case 0: op = .const(b)
    case 1: op = .unary({ x in x &* 9 &+ b })
    default: op = .binary({ x, y in x &* 5 &- y &* 7 &+ b })
    }
    return runOp(op, c, a) &+ 1037
}

// Three closures in an array, applied in order to a + b.
// (((a + b)*13 + a) ^ b)*5 - c + 1038
@inline(never) public func t38_array(_ a: Int, _ b: Int, _ c: Int) -> Int {
    let fs: [(Int) -> Int] = [
        { x in x &* 13 &+ a },
        { x in x ^ b },
        { x in x &* 5 &- c },
    ]
    return runAll(fs, a &+ b) &+ 1038
}

// A closure returning a closure: the inner box holds x and a.
// b*3 + c*5 + a*7 + 1039
@inline(never) public func t39_returnsClosure(_ a: Int, _ b: Int, _ c: Int) -> Int {
    let g = invokeMake({ x in { y in x &* 3 &+ y &* 5 &+ a &* 7 } }, b)
    return invokeEsc(g, c) &+ 1039
}

// withoutActuallyEscaping: the non-escaping value is wrapped in a context
// that swift_isEscapingClosureAtFileLocation checks afterwards.
@inline(never) func escapeBriefly(_ f: (Int) -> Int, _ x: Int) -> Int {
    withoutActuallyEscaping(f) { g in invokeEsc(g, x) }
}
// b*43 + a*47 + c*7 + 1040
@inline(never) public func t40_withoutActuallyEscaping(_ a: Int, _ b: Int, _ c: Int) -> Int {
    escapeBriefly({ x in x &* 43 &+ a &* 47 }, b) &+ c &* 7 &+ 1040
}

// A throwing closure: the error leaves in x21 and passes through the
// invoker. b odd: throws Fault(b*3 + a), result code*13 + c.
// b even: (b*5 + a*7 + 1) + c*11 + 1041.
@inline(never) public func t41_throwing(_ a: Int, _ b: Int, _ c: Int) -> Int {
    do {
        let r = try invokeThrowing({ x in
            if x & 1 == 1 { throw Fault(code: x &* 3 &+ a) }
            return x &* 5 &+ a &* 7
        }, b)
        return r &+ c &* 11 &+ 1041
    } catch let e as Fault {
        return e.code &* 13 &+ c
    } catch {
        return -41
    }
}

// A typed-throws closure: the Fault's code comes back in x0 with x21 set.
// b < 0: throws Fault(a - b), result code*7 + c*3.
// b >= 0: (b*3 + a + 2)*5 + c + 1042.
@inline(never) public func t42_throwingTyped(_ a: Int, _ b: Int, _ c: Int) -> Int {
    do {
        let r = try invokeTyped({ (x: Int) throws(Fault) -> Int in
            if x < 0 { throw Fault(code: a &- x) }
            return x &* 3 &+ a
        }, b)
        return r &* 5 &+ c &+ 1042
    } catch {
        return error.code &* 7 &+ c &* 3
    }
}

// An autoclosure capturing two Ints on the stack; called only when a is odd.
// a odd: (b*3 + c*5)*7 + 1 + a*2 + 1043.  a even: -43 + a*2 + 1043.
@inline(never) public func t43_autoclosure(_ a: Int, _ b: Int, _ c: Int) -> Int {
    pick(a & 1 == 1, b &* 3 &+ c &* 5) &+ a &* 2 &+ 1043
}

// An autoclosure with an effect on a captured variable: n changes only
// when b is odd. b odd: n = a*3 + c, result (n*7 + 1) + n*11 + 1044.
// b even: -43 + a*11 + 1044.
@inline(never) public func t44_autoclosureEffect(_ a: Int, _ b: Int, _ c: Int) -> Int {
    var n = a
    func bump() -> Int { n = n &* 3 &+ c; return n }
    let r = pick(b & 1 == 1, bump())
    return r &+ n &* 11 &+ 1044
}

// A boxed counter called three times: the order of the calls is visible.
// n1 = a*3 + b; n2 = n1*3 + c; n3 = n2*3 + (b^c)
// n1 + n2*5 + n3*7 + 1045
@inline(never) public func t45_counter(_ a: Int, _ b: Int, _ c: Int) -> Int {
    let f = makeCounter(a)
    let r1 = invokeEsc(f, b)
    let r2 = invokeEsc(f, c)
    let r3 = invokeEsc(f, b ^ c)
    return r1 &+ r2 &* 5 &+ r3 &* 7 &+ 1045
}

// A closure whose captures are two closures (four words in the box).
// ((c-b)*17 + a) + 46 + 1046
@inline(never) public func t46_compose(_ a: Int, _ b: Int, _ c: Int) -> Int {
    let h = compose({ x in x &* 17 &+ a }, { x in x &- b })
    return invokeEsc(h, c) &+ 1046
}

// Two class references: a real box with both at +16 and +24.
// a*2 + b*3 + c*5 + (a^b)*7 + (b-c)*11 + 1047
@inline(never) public func t47_twoClassRefs(_ a: Int, _ b: Int, _ c: Int) -> Int {
    let o1 = Cell(a, b)
    let o2 = Cell(c, a ^ b)
    return invokeEsc({ x in o1.v &* 2 &+ o1.w &* 3 &+ o2.v &* 5 &+ o2.w &* 7 &+ x &* 11 }, b &- c) &+ 1047
}

// Five arguments and one capture: the capture is the sixth argument of
// the body. a*2 + b*3 + c*5 + (a^b)*7 + (b^c)*11 + a*13 + 1048
@inline(never) public func t48_fiveArgs(_ a: Int, _ b: Int, _ c: Int) -> Int {
    invoke5({ p, q, r, s, t in p &* 2 &+ q &* 3 &+ r &* 5 &+ s &* 7 &+ t &* 11 &+ a &* 13 },
            a, b, c, a ^ b, b ^ c) &+ 1048
}

// Nine arguments and one capture: x9 arrives on the stack, and the body's
// tenth argument (the capture) is a second stack word.
// a*2 + b*3 + c*5 + (a+1)*7 + (b+2)*11 + (c+3)*13 + (a^b)*17 + (b^c)*19
//   + (a^c)*23 + a*29 + 1049
@inline(never) public func t49_nineArgs(_ a: Int, _ b: Int, _ c: Int) -> Int {
    invoke9({ x1, x2, x3, x4, x5, x6, x7, x8, x9 in
        x1 &* 2 &+ x2 &* 3 &+ x3 &* 5 &+ x4 &* 7 &+ x5 &* 11 &+ x6 &* 13 &+ x7 &* 17 &+ x8 &* 19 &+ x9 &* 23 &+ a &* 29
    }, a, b, c, a &+ 1, b &+ 2, c &+ 3, a ^ b, b ^ c, a ^ c) &+ 1049
}

// A closure with an inout parameter (an address in x0), applied twice.
// (a*3 + b)*3 + b + c*5 + 1050
@inline(never) public func t50_inoutParam(_ a: Int, _ b: Int, _ c: Int) -> Int {
    var n = a
    let f: (inout Int) -> Void = { v in v = v &* 3 &+ b }
    invokeInout(f, &n)
    invokeInout(f, &n)
    return n &+ c &* 5 &+ 1050
}

// A closure passed where a generic function type is expected: a
// reabstraction thunk takes the argument by address and stores the result
// through x8 (here x0 is the result address). b*53 + a*59 + c*7 + 1051
@inline(never) public func t51_reabstraction(_ a: Int, _ b: Int, _ c: Int) -> Int {
    invokeGeneric({ (x: Int) in x &* 53 &+ a &* 59 }, b) &+ c &* 7 &+ 1051
}

// A local function with captures, passed as a non-escaping value.
// c*7 + a*11 - b*13 + 1052
@inline(never) public func t52_localFunc(_ a: Int, _ b: Int, _ c: Int) -> Int {
    func local(_ x: Int) -> Int { x &* 7 &+ a &* 11 &- b &* 13 }
    return invoke1(local, c) &+ 1052
}

// An initializer as a function value: a thin thunk that jumps to it.
// lo = b + 53, hi = a - 53;  lo*3 + hi*5 + c*7 + 1053
@inline(never) public func t53_initRef(_ a: Int, _ b: Int, _ c: Int) -> Int {
    let mk = Pair.init(swapped:and:)
    let p = invokeMakePair(mk, a, b)
    return p.lo &* 3 &+ p.hi &* 5 &+ c &* 7 &+ 1053
}

// A closure stored in a global and called later, twice with two closures.
// (b*9 + a*5)*2 + (c*7 - a) + 1054
@inline(never) public func t54_stash(_ a: Int, _ b: Int, _ c: Int) -> Int {
    stash({ x in x &* 9 &+ a &* 5 })
    let r1 = runStash(b)
    stash({ x in x &* 7 &- a })
    let r2 = runStash(c)
    return r1 &* 2 &+ r2 &+ 1054
}

// A Double capture beside an Int capture: the forwarder loads d into d0
// and the Int into x1. d = Double(a & 0xffff)
// (a & 0xffff)*2 + c*3 + b + 1055
@inline(never) public func t55_doubleCapture(_ a: Int, _ b: Int, _ c: Int) -> Int {
    let d = Double(a & 0xffff)
    return invokeEsc({ x in Int(d * 2) &+ x &* 3 &+ b }, c) &+ 1055
}

// A closure built inside a closure, capturing the outer argument and the
// outer capture. b*9 + c*5 + a*7 + c + 1056
@inline(never) public func t56_nested(_ a: Int, _ b: Int, _ c: Int) -> Int {
    invoke1({ x in invoke1({ y in y &* 9 &+ x &* 5 &+ a &* 7 }, b) &+ x }, c) &+ 1056
}

// A captured struct made by a callee that does NOT return its arguments:
// Pair(swapped:and:) gives lo = b + 53, hi = a - 53, so the box's slots
// hold the call's results, not a and b. (t08 is the same shape with the
// memberwise init, whose body is a bare `ret`.)
// (b+53)*3 + (a-53)*5 + c*7 + 1057
@inline(never) public func t57_capturedCallPair(_ a: Int, _ b: Int, _ c: Int) -> Int {
    let p = Pair(swapped: a, and: b)
    return invokeEsc({ x in p.lo &* 3 &+ p.hi &* 5 &+ x &* 7 }, c) &+ 1057
}

// x*4 - 58
@inline(never) func plainQuad(_ x: Int) -> Int { x &* 4 &- 58 }

// One of two named functions picked at run time and called through the
// value in this function: the blr reaches plainTriple for an even a and
// plainQuad for an odd a, never one of them unconditionally.
// a even: b*3 + 31 + c*3 + 1058.  a odd: b*4 - 58 + c*3 + 1058.
@inline(never) public func t58_pickNamed(_ a: Int, _ b: Int, _ c: Int) -> Int {
    let f: (Int) -> Int = a & 1 == 0 ? plainTriple : plainQuad
    return f(b) &+ c &* 3 &+ 1058
}

// A function value that comes back from an opaque call and is called
// twice here: each blr takes the context (x1 of the result) in x20.
// (b*7 + a*3) + (c*7 + a*3)*5 + 1059
@inline(never) public func t59_callReturnedValue(_ a: Int, _ b: Int, _ c: Int) -> Int {
    let g = launder({ x in x &* 7 &+ a &* 3 })
    return g(b) &+ g(c) &* 5 &+ 1059
}

// A captured Int that is a call's result: the slot holds plainTriple(a),
// not a. (a*3 + 31)*5 + b + c*3 + 1060
@inline(never) public func t60_capturedCallResult(_ a: Int, _ b: Int, _ c: Int) -> Int {
    let v = plainTriple(a)
    return invokeEsc({ x in v &* 5 &+ x }, b) &+ c &* 3 &+ 1060
}

// ---------------------------------------------------------------- controls

// Direct call of the function t31 passes as a value.
// a*3 + 31 + b*3 + c*5 + 2001
@inline(never) public func c01_directCall(_ a: Int, _ b: Int, _ c: Int) -> Int {
    plainTriple(a) &+ b &* 3 &+ c &* 5 &+ 2001
}

// Direct call of the method t22 binds. a*3 + b*5 + c*7 + 2002
@inline(never) public func c02_directMethod(_ a: Int, _ b: Int, _ c: Int) -> Int {
    Cell(a, b).scale(c) &+ 2002
}

// Direct call returning two registers. a*21 + b*55 + c + 2003
@inline(never) public func c03_directPair(_ a: Int, _ b: Int, _ c: Int) -> Int {
    let p = makePairDirect(a, b)
    return p.lo &* 7 &+ p.hi &* 11 &+ c &+ 2003
}

// Direct call returning through x8.
// a*2 + b*3 + c*5 + (a^b)*7 + (b^c)*11 + 2004
@inline(never) public func c04_directFive(_ a: Int, _ b: Int, _ c: Int) -> Int {
    let f = makeFiveDirect(a, b, c)
    return f.a &* 2 &+ f.b &* 3 &+ f.c &* 5 &+ f.d &* 7 &+ f.e &* 11 &+ 2004
}

// Direct call returning Int?. a odd: a*3 + c + 2005.  a even: b + c + 2005.
@inline(never) public func c05_directOptional(_ a: Int, _ b: Int, _ c: Int) -> Int {
    (optDirect(a) ?? b) &+ c &+ 2005
}

// No call at all. a*3 + b*5 + c*7 + 2006
@inline(never) public func c06_arithmetic(_ a: Int, _ b: Int, _ c: Int) -> Int {
    a &* 3 &+ b &* 5 &+ c &* 7 &+ 2006
}

// Direct throwing call. a odd: a*5*3 + c.  a even: a*7 + b + 2007.
@inline(never) public func c07_directThrow(_ a: Int, _ b: Int, _ c: Int) -> Int {
    do {
        return try failIfOdd(a) &+ b &+ 2007
    } catch let e as Fault {
        return e.code &* 3 &+ c
    } catch {
        return -7
    }
}

// A two-register result of a callee that changes both registers, handed
// straight to another direct call. (b+53)*3 + (a-53)*5 + c*11 + 2009
@inline(never) public func c09_directSwappedPair(_ a: Int, _ b: Int, _ c: Int) -> Int {
    sumPair(Pair(swapped: a, and: b), c) &+ 2009
}

// Direct field reads of a Cell, no closure. a*3 + b*5 + c + 2008
@inline(never) public func c08_directField(_ a: Int, _ b: Int, _ c: Int) -> Int {
    let o = Cell(a, b)
    return o.v &* 3 &+ o.w &* 5 &+ c &+ 2008
}
