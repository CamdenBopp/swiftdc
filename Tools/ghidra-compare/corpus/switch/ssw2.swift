// Swift -Osize table switches. Truth per function.
@inline(never) public func s(_ x: Int) { print(x) }
@inline(never) public func t(_ x: String) { print(x) }
// holes/shared: 0,2 -> t("A") ; 1 -> t("B") ; 3 -> default ; 4,6 -> t("C") ; 5 -> t("D") ; 7 -> t("E") ; default t("Z")
public func holes(_ x: Int) {
  switch x {
  case 0, 2: t("A")
  case 1: t("B")
  case 4, 6: t("C")
  case 5: t("D")
  case 7: t("E")
  default: t("Z")
  }
}
// case that does nothing: 0 -> nothing, 1 -> t("one"), 2 -> t("two"), 3 -> nothing, 4 -> t("four"), 5 -> t("five") ; default t("dflt")
public func empties(_ x: Int) {
  switch x {
  case 0, 3: break
  case 1: t("one")
  case 2: t("two")
  case 4: t("four")
  case 5: t("five")
  default: t("dflt")
  }
  s(99)
}
// big arms to force 2-byte entries: each case prints many strings
public func big(_ x: Int) {
  switch x {
  case 0: t("a0"); t("a1"); t("a2"); t("a3"); t("a4"); t("a5"); t("a6"); t("a7"); t("a8"); t("a9"); t("a10"); t("a11"); t("a12"); t("a13"); t("a14"); t("a15"); t("a16"); t("a17"); t("a18"); t("a19"); t("a20"); t("a21"); t("a22"); t("a23"); t("a24"); t("a25"); t("a26"); t("a27"); t("a28"); t("a29"); t("a30"); t("a31"); t("a32"); t("a33"); t("a34"); t("a35"); t("a36"); t("a37"); t("a38"); t("a39"); t("a40"); t("a41"); t("a42"); t("a43"); t("a44"); t("a45"); t("a46"); t("a47"); t("a48"); t("a49")
  case 1: t("b0"); t("b1"); t("b2"); t("b3"); t("b4"); t("b5"); t("b6"); t("b7"); t("b8"); t("b9"); t("b10"); t("b11"); t("b12"); t("b13"); t("b14"); t("b15"); t("b16"); t("b17"); t("b18"); t("b19"); t("b20"); t("b21"); t("b22"); t("b23"); t("b24"); t("b25"); t("b26"); t("b27"); t("b28"); t("b29"); t("b30"); t("b31"); t("b32"); t("b33"); t("b34"); t("b35"); t("b36"); t("b37"); t("b38"); t("b39")
  case 2: t("c0"); t("c1"); t("c2"); t("c3"); t("c4"); t("c5"); t("c6"); t("c7"); t("c8"); t("c9"); t("c10"); t("c11"); t("c12"); t("c13"); t("c14"); t("c15"); t("c16"); t("c17"); t("c18"); t("c19"); t("c20"); t("c21"); t("c22"); t("c23"); t("c24"); t("c25"); t("c26"); t("c27"); t("c28"); t("c29"); t("c30"); t("c31"); t("c32"); t("c33"); t("c34"); t("c35"); t("c36"); t("c37"); t("c38"); t("c39")
  case 3: t("d0")
  case 4: t("e0")
  default: t("zz")
  }
}
public enum Tok { case num(Int), ident(String), plus, minus, star, slash, lparen, rparen, eof }
// payload enum -Osize: num(n) -> n ; ident(s) -> s.count ; plus -> 1, minus -> 2, star -> 3, slash -> 4, lparen -> 5, rparen -> 6, eof -> 0
public func tokValue(_ k: Tok) -> Int {
  switch k {
  case let .num(n): return n
  case let .ident(s): return s.count
  case .plus: return 1
  case .minus: return 2
  case .star: return 3
  case .slash: return 4
  case .lparen: return 5
  case .rparen: return 6
  case .eof: return 0
  }
}
// nested payload: Outer.a(Tok) / .b(Int) / .c ; a(.plus) -> 10, a(_) -> 11, b(n) where n > 5 -> 12, b -> 13, c -> 14
public enum Outer { case a(Tok), b(Int), c }
public func nested(_ o: Outer) -> Int {
  switch o {
  case .a(.plus): return 10
  case .a: return 11
  case let .b(n) where n > 5: return 12
  case .b: return 13
  case .c: return 14
  }
}
