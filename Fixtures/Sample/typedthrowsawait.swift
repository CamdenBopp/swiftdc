// A typed-throws async callee whose error fits in a register delivers the
// error payload in x0 (with x20 = 1) when it throws. The caller's catch block
// then reads x0 as the error.
public struct Code: Error { public var raw: Int }

@inline(never) public func codeAsync(_ x: Int) async throws(Code) -> Int {
    await Task.yield()
    if x < 0 { throw Code(raw: x &* 7) }
    return x &+ 100
}

@inline(never) public func onValue(_ x: Int) { print("value", x) }
@inline(never) public func onError(_ x: Int) { print("error", x) }

public func useCode(_ x: Int) async {
    do {
        let v = try await codeAsync(x)
        onValue(v)
    } catch {
        onError(error.raw &+ 1000)
    }
}
