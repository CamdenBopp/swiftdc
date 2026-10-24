import Testing
import Foundation
@testable import SwiftDecompilerCore

/// A call to an SDK C function carries no signature in the binary. Laid out
/// by position from the x registers it found, with x0 after it taken as its
/// result, `c_prototypes.c` (-O2) rendered its OpenGL drawing
/// `glEnd(glVertex3f(glTexCoord2f(glBegin(7))))`, `glVertex3f(1.0f, 2.0f,
/// 0.5f)` as `glVertex3f()`, `strchr(j->s, j->c)` as `strchr()`, and
/// `glFlush(); notifyDone();` as `notifyDone(glFlush())`. The SDK's
/// declarations (`SDKCPrototypes`) say each function's parameter banks and
/// which register, if any, its result is in.
@Test func anSDKCCallIsLaidOutFromItsDeclarationIfPresent() async throws {
    let path = "Fixtures/Sample/libCPrototypes.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
    func statements(_ name: String) throws -> [String] {
        let text = try #require(functions.first { $0.displayName == name }).renderPseudo()
        return text.components(separatedBy: "\n").dropFirst().dropLast()
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty && $0 != "}" }
    }
    #expect(try statements("_drawQuad") == ["glBegin(7)", "glTexCoord2f(?, ?)", "glVertex3f(?, ?, ?)", "glEnd()"])
    #expect(try statements("_drawConstant") == ["glVertex3f(1.0, 2.0, 0.5)"])
    #expect(try statements("_findChar") == ["strchr(?, ?)"])
    #expect(try statements("_flushThenNotify") == ["glFlush()", "notifyDone()"])
    // CGRectInset's CGRect comes back in d0-d3: d0 is its origin.x, not the
    // call (`glVertex2d(CGRectInset(), ?)`).
    #expect(try statements("_insetVertex").last == "glVertex2d(?, ?)")
    // strtod's double is in d0; x0 after it is not its result.
    #expect(try statements("_parseThenNotify") == ["strtod(?, 0)", "notifyDone()"])
    // A struct parameter is placed by how it is passed, so it and what
    // follows it are `?`; what precedes it is placed (`CGRectInset()` took
    // nothing, and `CGContextFillRect` only x0).
    #expect(try statements("_insetVertex").first == "CGRectInset(?, ?, ?)")
    #expect(try statements("_fillNull") == ["CGContextFillRect(0, ?)"])
    #expect(try statements("_offsetConstant") == ["CGRectOffset(?, ?, ?)"])
}

/// A table entry: the result, each parameter's bank, and `...` for a
/// variadic one.
@Test func anSDKCPrototypeReadsItsBanksAndVariadics() {
    let vertex = DisassembledFunction.cPrototype(of: "glVertex3f")
    #expect(vertex == DisassembledFunction.CPrototype(result: "v", parameters: ["f", "f", "f"], isVariadic: false))
    #expect(DisassembledFunction.cPrototype(of: "printf")?.isVariadic == true)
    #expect(DisassembledFunction.cPrototype(of: "printf")?.parameters == ["i"])
    #expect(DisassembledFunction.cPrototype(of: "glEnd")?.parameters == [])
    #expect(DisassembledFunction.cPrototype(of: "CGRectGetHeight")?.parameters == ["s"])
    #expect(DisassembledFunction.cPrototype(of: "noSuchFunction_ZZ") == nil)
    // `void (*signal(int, void (*)(int)))(int)` returns a function pointer:
    // read up to its first parenthesis, it looked like a void function.
    #expect(DisassembledFunction.cPrototype(of: "signal") == DisassembledFunction.CPrototype(result: "i", parameters: ["i", "i"], isVariadic: false))
    // clang prints `DISPATCH_RETURNS_RETAINED dispatch_queue_t`: the macro
    // is no part of the type, which is a pointer.
    #expect(DisassembledFunction.cPrototype(of: "dispatch_queue_create")?.result == "i")
    #expect(DisassembledFunction.cPrototype(of: "CGRectInset")?.result == "s")
    #expect(DisassembledFunction.cPrototype(of: "CMTimeMake")?.result == "s")
    // A result the generator could not classify claims no register.
    #expect(ValueTracer.CallFacts.result(of: .init(result: "x", parameters: [], isVariadic: false)) == nil)
    #expect(ValueTracer.CallFacts.result(of: .init(result: "s", parameters: [], isVariadic: false)) == "s")
    // Only all-integer, fixed parameters become a known arity; a struct or
    // a float parameter, or a variadic tail, does not.
    #expect(DisassembledFunction.knownCArity(of: "strchr") == 2)
    #expect(DisassembledFunction.knownCArity(of: "glVertex3f") == nil)
    #expect(DisassembledFunction.knownCArity(of: "CGRectGetHeight") == nil)
    #expect(DisassembledFunction.knownCArity(of: "printf") == nil)
    // A declaration whose parameters the dump did not show (`SMJobBless`
    // takes four) must not become an arity of zero; one that takes nothing
    // prints `(void)`. `MPSGetPreferredDevice` takes one.
    #expect(DisassembledFunction.knownCArity(of: "SMJobBless") != 0)
    #expect(DisassembledFunction.knownCArity(of: "MPSGetPreferredDevice") == 1)
}
