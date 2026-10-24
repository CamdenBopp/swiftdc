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
    // What precedes a struct parameter is placed (`CGRectInset()` took
    // nothing, and `CGContextFillRect` only x0). A CGRect is an HFA in four
    // v registers, so what follows it is placed too.
    #expect(try statements("_insetVertex").first == "CGRectInset(?, 0.5, 0.5)")
    #expect(try statements("_fillNull") == ["CGContextFillRect(0, ?)"])
    #expect(try statements("_offsetConstant") == ["CGRectOffset(?, 5.0, 6.0)"])
    #expect(try statements("_drawNull") == ["CGContextDrawImage(0, ?, 0)"])
}

/// A table entry: the result, each parameter's bank, and `...` for a
/// variadic one.
@Test func anSDKCPrototypeReadsItsBanksAndVariadics() {
    let vertex = DisassembledFunction.cPrototype(of: "glVertex3f")
    #expect(vertex == DisassembledFunction.CPrototype(result: "v", parameters: ["f", "f", "f"], isVariadic: false))
    #expect(DisassembledFunction.cPrototype(of: "printf")?.isVariadic == true)
    #expect(DisassembledFunction.cPrototype(of: "printf")?.parameters == ["i"])
    #expect(DisassembledFunction.cPrototype(of: "glEnd")?.parameters == [])
    #expect(DisassembledFunction.cPrototype(of: "CGRectGetHeight")?.parameters == ["D4"])
    #expect(DisassembledFunction.cPrototype(of: "noSuchFunction_ZZ") == nil)
    // `void (*signal(int, void (*)(int)))(int)` returns a function pointer:
    // read up to its first parenthesis, it looked like a void function.
    #expect(DisassembledFunction.cPrototype(of: "signal") == DisassembledFunction.CPrototype(result: "i", parameters: ["i", "i"], isVariadic: false))
    // clang prints `DISPATCH_RETURNS_RETAINED dispatch_queue_t`: the macro
    // is no part of the type, which is a pointer.
    #expect(DisassembledFunction.cPrototype(of: "dispatch_queue_create")?.result == "i")
    #expect(DisassembledFunction.cPrototype(of: "CGRectInset")?.result == "s")
    #expect(DisassembledFunction.cPrototype(of: "CMTimeMake")?.result == "s")
    // CGRect's four CGFloats, through CGPoint and CGSize, are an HFA;
    // CGAffineTransform's six are not.
    #expect(DisassembledFunction.cPrototype(of: "NSDivideRect")?.parameters == ["D4", "i", "i", "d", "i"])
    #expect(DisassembledFunction.cPrototype(of: "CGPointApplyAffineTransform")?.parameters == ["D2", "s"])
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

/// A send returning a struct leaves it in several v registers, so a C
/// argument holding one of them is a field of the result, not the send:
/// `objc_struct_lanes.m` (-O2) rendered `glVertex2d(r0, ?)` for
/// `glVertex2d(r.origin.x, r.origin.y)`, r0 the whole `[self rect]` (and
/// Chess `gluOrtho2D([self bounds], ?, ?, ?)`). A send whose method returns
/// a double is whole in d0.
@Test func aCArgumentTakesOnlyAWholeFloatResultIfPresent() async throws {
    let path = "Fixtures/Sample/libObjCStructLanes.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
    func rendered(_ name: String) throws -> String {
        try #require(functions.first { $0.displayName == name }).renderPseudo()
    }
    let lanes = try rendered("-[SDLanes vertexFromRect]")
    #expect(lanes.contains("glVertex2d(?, ?)"), Comment(rawValue: lanes))
    let scaled = try rendered("-[SDLanes vertexScaled]")
    #expect(scaled.contains("glVertex2d([self scale], 0.5)"), Comment(rawValue: scaled))
    // After an HFA too: CGRectOffset's offsets are [self rect]'s lanes, and
    // CGRectInset's dx the whole [self scale].
    let offset = try rendered("-[SDLanes offsetFrame]")
    #expect(offset.contains("CGRectOffset(?, ?, ?)"), Comment(rawValue: offset))
    let inset = try rendered("-[SDLanes scaledFrame]")
    #expect(inset.contains("CGRectInset(?, [self scale], 0.5)"), Comment(rawValue: inset))
    // Only Foundation declares timeIntervalSinceNow, a double; the image's
    // own `size` returns a double, but NSImage's an NSSize.
    let interval = try rendered("-[SDLanes vertexInterval:]")
    #expect(interval.contains("timeIntervalSinceNow], 0.5)"), Comment(rawValue: interval))
    let size = try rendered("-[SDLanes vertexSize:]")
    #expect(size.contains("glVertex2d(?, 0.5)"), Comment(rawValue: size))
    // Two of the image's own declarations disagree: a double and a CGPoint.
    let lane = try rendered("-[SDLanes vertexLane:]")
    #expect(lane.contains("glVertex2d(?, 0.5)"), Comment(rawValue: lane))
}

/// An HFA takes its member count of v registers, and one that does not fit
/// in those left goes on the stack (AAPCS64), so it and what follows are not
/// placed. No SDK declaration overflows, so the case is built by hand.
@Test func anHFAParameterIsPlacedOnlyWhereItFits() throws {
    let fits = try #require(Disassembler.cPrototypeLayout(
        prototype: .init(result: "v", parameters: ["i", "D4", "d", "i"], isVariadic: false)))
    #expect(fits.slots.map(\.registers) == [1, 4, 1, 1])
    #expect(fits.unplaced == 0)
    let overflows = try #require(Disassembler.cPrototypeLayout(
        prototype: .init(result: "v", parameters: ["d", "d", "d", "d", "d", "D4", "i"], isVariadic: false)))
    #expect(overflows.slots.count == 5)
    #expect(overflows.unplaced == 2)
}

/// The SDK's float and float-aggregate returns. NSFont's getters are
/// implemented in a private framework (AppKit holds only a category on
/// NSFont), and NSImage's `size` is an NSSize.
@Test func theSDKSelectorReturnsHoldFloatsAndAggregates() {
    #expect(SDKSelectorReturns.table["underlinePosition"] == "f")
    #expect(SDKSelectorReturns.table["timeIntervalSinceNow"] == "f")
    #expect(SDKSelectorReturns.table["size"] == "h")
    #expect(SDKSelectorReturns.table["frame"] == "h")
    #expect(SDKSelectorReturns.table["count"] == nil)
}
