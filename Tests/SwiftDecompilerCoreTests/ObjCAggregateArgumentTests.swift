import Foundation
import Testing
@testable import SwiftDecompilerCore

/// The send each `send…` method makes and the entry stores of each receiving
/// method, as the pseudo view spells them.
private func renders(in path: String) async throws -> [String: String] {
    let functions = try await withStableDependencies {
        try await Disassembler(preset: .default).disassemble(path: path, functionFilter: "SDAggregateProbe")
    }
    var lines: [String: String] = [:]
    for function in functions {
        lines[function.displayName] = function.renderPseudo().components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.hasPrefix("[self ") || $0.hasPrefix("self->") }
            .joined(separator: "; ")
    }
    return lines
}

/// A typed send with a struct parameter rendered every explicit argument
/// `?`, because the layout declined any aggregate (`objc_aggregate_args.m`).
/// The struct itself still has no single value, but every argument after it
/// lands on its true register or stack offset: after an HFA in v registers,
/// a small struct in x registers, a large one passed by address, and a
/// struct that does not fit, which goes on the stack and closes its bank. A
/// struct on the stack is a stack argument of its own, so the merged store
/// of an int and the HFA after it is not read as the int.
@Test(arguments: ["Fixtures/Sample/libObjCAggregateArgs.dylib", "Fixtures/Sample/libObjCAggregateArgs.opt.dylib"])
func objcStructArgumentsKeepLaterArgumentsInPlaceIfPresent(path: String) async throws {
    guard FileManager.default.fileExists(atPath: path) else { return }
    let optimized = path.hasSuffix(".opt.dylib")
    let found = try await renders(in: path)
    let expected: [String: String] = [
        "-[SDAggregateProbe sendPlace]": "[self place:? flags:7 stamp:2.5]",
        "-[SDAggregateProbe sendFrame]": "[self frame:? tag:9]",
        "-[SDAggregateProbe sendSpilledRect]":
            "[self a:1.5 b:2.5 c:3.5 d:4.5 e:5.5 f:6.5 rect:? after:11.5 n:12]",
        "-[SDAggregateProbe sendSpan]": "[self span:? count:5]",
        "-[SDAggregateProbe sendSpilledRange]": "[self a:1 b:2 c:3 d:4 e:5 range:? tail:8]",
        "-[SDAggregateProbe sendBig]": "[self big:? n:4]",
        // -O merges count's store with the HFA's after it: not count alone.
        "-[SDAggregateProbe sendOne]": "[self v0:1.5 v1:2.5 v2:3.5 v3:4.5 v4:5.5 v5:6.5 v6:7.5 v7:8.5"
            + " x2:1 x3:2 x4:3 x5:4 x6:5 x7:6 count:\(optimized ? "?" : "7") one:?]",
        // A method that takes a struct does not seed its own arguments: an
        // untyped send it makes would name pass-through values shifted.
        "-[SDAggregateProbe place:flags:stamp:]": "self->_flags = …; self->_stamp = …",
        "-[SDAggregateProbe frame:tag:]": "self->_tag = …",
    ]
    for (name, line) in expected.sorted(by: { $0.key < $1.key }) {
        #expect(found[name] == line, "\(path) \(name): \(found[name] ?? "no function")")
    }
}

/// NSEvent's `keyEventWithType:location:modifierFlags:timestamp:windowNumber:
/// context:characters:charactersIgnoringModifiers:isARepeat:keyCode:`: the
/// NSPoint takes d0-d1, so the timestamp is d2, the integers and objects fill
/// x2-x7, and the BOOL and the unsigned short pack onto the stack at sp+0 and
/// sp+2 (clang's own lowering of this signature, checked by hand).
@Test func keyEventLayoutPlacesEveryArgumentAfterTheLocation() {
    let encoding = "@96@0:8Q16{CGPoint=dd}24Q40d48q56@64@72@80B88S92"
    #expect(ObjCArgumentABI.locations(encoding: encoding, argumentCount: 10) == [
        "x2": 0, "x3": 2, "v2": 3, "x4": 4, "x5": 5, "x6": 6, "x7": 7,
        "stack@0": 8, "stack@2": 9,
    ])
    #expect(ObjCArgumentABI.stackSlotWidths(encoding: encoding, argumentCount: 10) == ["stack@0": 1, "stack@2": 2])
    #expect(ObjCArgumentABI.stackArgumentStarts(encoding: encoding, argumentCount: 10) == [0, 2])
}

/// A struct that does not fit in the registers left goes on the stack, and
/// no later argument of its bank takes a register (clang leaves d6-d7, or x7,
/// unused). A float HFA on the stack keeps its four-byte alignment, and its
/// start counts as a stack argument: an eight-byte store at sp+0 is the int
/// there and the HFA's first member, not the int alone.
@Test func aStructThatDoesNotFitClosesItsBank() {
    let rect = "v112@0:8d16d24d32d40d48d56{CGRect={CGPoint=dd}{CGSize=dd}}64d96q104"
    #expect(ObjCArgumentABI.locations(encoding: rect, argumentCount: 9) == [
        "v0": 0, "v1": 1, "v2": 2, "v3": 3, "v4": 4, "v5": 5, "stack@32": 7, "x2": 8,
    ])
    #expect(ObjCArgumentABI.stackArgumentStarts(encoding: rect, argumentCount: 9) == [0, 32])

    let range = "v72@0:8q16q24q32q40q48{_NSRange=QQ}56q72"
    #expect(ObjCArgumentABI.locations(encoding: range, argumentCount: 7) == [
        "x2": 0, "x3": 1, "x4": 2, "x5": 3, "x6": 4, "stack@16": 6,
    ])
    #expect(ObjCArgumentABI.stackArgumentStarts(encoding: range, argumentCount: 7) == [0, 16])

    let floats = "v@:qqqqqqiddddddd{F2=ff}i"
    #expect(ObjCArgumentABI.locations(encoding: floats, argumentCount: 16)["stack@12"] == 15)
    let starts = ObjCArgumentABI.stackArgumentStarts(encoding: floats, argumentCount: 16)
    #expect(starts == [0, 4, 12])
    #expect(!ObjCArgumentABI.storeHoldsOnlyArgument(at: 0, bytes: 4, storedBytes: 8, stackStarts: starts))

    // Six integers fill x2-x7, so a large struct's address goes on the
    // stack like one more pointer, and the integer after it follows.
    let big = "v@:qqqqqq{Big=qqq}q"
    #expect(ObjCArgumentABI.locations(encoding: big, argumentCount: 8)["stack@8"] == 7)
    #expect(ObjCArgumentABI.stackArgumentStarts(encoding: big, argumentCount: 8) == [0, 8])
}

@Test func structArgumentsAreClassifiedByTheirMembers() {
    #expect(ObjCArgumentABI.aggregate("{CGPoint=dd}") == .homogeneousFloat(members: 2, memberSize: 8))
    #expect(ObjCArgumentABI.aggregate("{CGRect={CGPoint=dd}{CGSize=dd}}") == .homogeneousFloat(members: 4, memberSize: 8))
    #expect(ObjCArgumentABI.aggregate("{One=f}") == .homogeneousFloat(members: 1, memberSize: 4))
    #expect(ObjCArgumentABI.aggregate("{_NSRange=QQ}") == .composite(size: 16))
    #expect(ObjCArgumentABI.aggregate("{Mixed=fd}") == .composite(size: 16))
    #expect(ObjCArgumentABI.aggregate("{Bytes=cc}") == .composite(size: 2))
    #expect(ObjCArgumentABI.aggregate("{Ptr=^{Opaque=}q}") == .composite(size: 16))
    #expect(ObjCArgumentABI.aggregate("{Pad=cd}") == .composite(size: 16))
    #expect(ObjCArgumentABI.aggregate("{Nest={In=ci}c}") == .composite(size: 12))
    #expect(ObjCArgumentABI.aggregate("{Five=ddddd}") == .byReference)
    #expect(ObjCArgumentABI.aggregate("{Big=qqq}") == .byReference)
    // Not modelled: the whole layout declines.
    for unmodelled in ["{Bits=b1b7}", "{Array=[4f]}", "{Long=DD}", "{Wide=t}", "{Union=(U=if)}",
                       "{Opaque}", "{Empty=}", "{Named=\"x\"d\"y\"d}", "{Complex=jd}", "{Long32=l}"] {
        #expect(ObjCArgumentABI.aggregate(unmodelled) == nil, "\(unmodelled)")
        #expect(ObjCArgumentABI.locations(encoding: "v@:q\(unmodelled)q", argumentCount: 3).isEmpty, "\(unmodelled)")
    }
    #expect(ObjCArgumentABI.locations(encoding: "v@:q(U=if)q", argumentCount: 3).isEmpty)
}
