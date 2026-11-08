// A one-case enum is zero-sized and takes no register (-Onone, so the
// parameter is not specialized away). True behaviour: oneMid returns
// a * 7 - b with a in x0 and b in x1; callOneMid passes x and y there.
public enum One { case only }
@inline(never) public func oneMid(_ a: Int, _ o: One, _ b: Int) -> Int { a &* 7 &- b }
public func callOneMid(_ x: Int, _ y: Int) -> Int { oneMid(x, .only, y) }
