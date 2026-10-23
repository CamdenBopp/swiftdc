/// Darwin arm64 uses independent integer and floating-point argument banks.
/// Recovered from the pre-merge stash (d921fc1, improve/source-findings).
/// Type-encoding offsets describe the runtime method frame, not register slots.
/// A struct argument is classified by the AAPCS64 rules as Apple's clang
/// applies them (see `aggregate(_:)`). Any other argument (a union, an array,
/// a vector, or a struct holding a bitfield, array, long double or
/// over-aligned member) declines the whole layout rather than shift later
/// arguments into the wrong registers.
enum ObjCArgumentABI {
    static func returnType(encoding: String) -> String? {
        var parser = Parser(Array(encoding))
        return parser.type()
    }

    static func parameterTypes(encoding: String, argumentCount: Int) -> [String]? {
        var parser = Parser(Array(encoding))
        var types: [String] = []
        while !parser.atEnd {
            guard let type = parser.type() else { return nil }
            types.append(type)
            parser.skipOffsets()
        }
        guard types.count == argumentCount + 3,
              types[1] == "@", types[2] == ":" else { return nil }
        return Array(types.dropFirst(3))
    }

    /// Whether an argument of this type travels in one x register (or one
    /// stack slot once they run out): an integer, pointer, object, class or
    /// selector. A floating-point scalar takes a v register, and a struct
    /// takes several registers or the address of a copy.
    static func takesOneXRegister(_ type: String) -> Bool {
        guard let code = type.first else { return false }
        return "cCsSiIlLqQB@#:*^".contains(code)
    }

    /// Where each explicit scalar argument arrives: `x<n>`, `v<n>` or
    /// `stack@<offset>`. A struct argument has no entry, because its value is
    /// several registers or the address of a copy, but it still uses up its
    /// registers or stack bytes, so every later argument lands where the
    /// callee reads it.
    static func locations(encoding: String, argumentCount: Int) -> [String: Int] {
        guard let types = parameterTypes(encoding: encoding, argumentCount: argumentCount),
              let placements = placements(types) else { return [:] }
        var result: [String: Int] = [:]
        for (argument, placement) in placements.enumerated() {
            if case .scalar(let location) = placement { result[location] = argument }
        }
        return result
    }

    /// The stack offset of every explicit argument passed on the stack,
    /// struct arguments included, so a store that also covers a struct's
    /// bytes is never read as the argument before it.
    static func stackArgumentStarts(encoding: String, argumentCount: Int) -> [Int] {
        guard let types = parameterTypes(encoding: encoding, argumentCount: argumentCount),
              let placements = placements(types) else { return [] }
        return placements.compactMap { placement in
            switch placement {
            case .scalar(let location):
                location.hasPrefix("stack@") ? Int(location.dropFirst("stack@".count)) : nil
            case .aggregate(let stack): stack
            }
        }.sorted()
    }

    /// How one explicit argument travels.
    private enum Placement: Equatable {
        /// A scalar in one register (`x2`, `v0`) or at `stack@<offset>`.
        case scalar(String)
        /// A struct: in registers, as the address of a copy, or on the stack
        /// starting at `stack`.
        case aggregate(stack: Int?)
    }

    /// Lays the explicit arguments out across x2-x7, v0-v7 and the stack.
    /// Nil when any argument cannot be classified.
    private static func placements(_ types: [String]) -> [Placement]? {
        var gp = 2, fp = 0, stack = 0
        // Apple arm64 packs stack arguments to their natural alignment,
        // unlike generic AAPCS64's minimum eight-byte slots.
        func onStack(size: Int, alignment: Int) -> Int {
            stack = (stack + alignment - 1) / alignment * alignment
            defer { stack += size }
            return stack
        }
        var result: [Placement] = []
        for type in types {
            guard let code = type.first else { return nil }
            if code == "{" {
                guard let kind = aggregate(type) else { return nil }
                switch kind {
                case .homogeneousFloat(let members, let memberSize):
                    // AAPCS64 C.2-C.3: consecutive v registers, one per
                    // member, if enough remain; otherwise the stack, and no
                    // later floating argument goes in a v register.
                    if fp + members <= maxRegisters {
                        fp += members
                        result.append(.aggregate(stack: nil))
                    } else {
                        fp = maxRegisters
                        result.append(.aggregate(stack: onStack(size: members * memberSize, alignment: memberSize)))
                    }
                case .composite(let size):
                    // C.10-C.11: one or two consecutive x registers if they
                    // fit; otherwise the stack, eight-byte aligned and rounded
                    // to whole words (clang coerces it to i64 or [2 x i64]),
                    // and no later argument goes in an x register.
                    let words = (size + 7) / 8
                    if gp + words <= maxRegisters {
                        gp += words
                        result.append(.aggregate(stack: nil))
                    } else {
                        gp = maxRegisters
                        result.append(.aggregate(stack: onStack(size: words * 8, alignment: 8)))
                    }
                case .byReference:
                    // B.3: the address of a copy the caller makes, in an x
                    // register like any pointer, or on the stack once they
                    // run out.
                    if gp < maxRegisters {
                        gp += 1
                        result.append(.aggregate(stack: nil))
                    } else {
                        result.append(.aggregate(stack: onStack(size: 8, alignment: 8)))
                    }
                }
                continue
            }
            let floating = code == "f" || code == "d" || code == "D"
            guard floating || "cCsSiIlLqQB@#:*^".contains(code),
                  let layout = ObjCTypeLayoutDecoder.layout(of: type) else { return nil }
            if floating && fp < maxRegisters {
                result.append(.scalar("v\(fp)"))
                fp += 1
            } else if !floating && gp < maxRegisters {
                result.append(.scalar("x\(gp)"))
                gp += 1
            } else {
                result.append(.scalar("stack@\(onStack(size: layout.size, alignment: layout.alignment))"))
            }
        }
        return result
    }

    /// Eight argument registers in each bank.
    private static let maxRegisters = 8
    /// AAPCS64's largest homogeneous floating-point aggregate.
    private static let maxHFAMembers = 4
    /// The largest struct passed by value in x registers.
    private static let maxRegisterCompositeBytes = 16

    /// The AAPCS64 class of a struct argument.
    enum AggregateKind: Equatable {
        /// One to four members of one floating type (nested structs
        /// flattened), each `memberSize` bytes.
        case homogeneousFloat(members: Int, memberSize: Int)
        /// Any other struct of at most 16 bytes, passed by value.
        case composite(size: Int)
        /// A larger struct, passed as the address of a copy.
        case byReference
    }

    /// Classifies a struct encoding (`{CGPoint=dd}`), or nil when it holds
    /// anything this layout does not model: a union, bitfield or array
    /// member, a long double, 128-bit integer, complex or vector member, an
    /// opaque or empty struct, or quoted field names. The size comes from
    /// the members themselves, laid out at their natural alignment.
    static func aggregate(_ type: String) -> AggregateKind? {
        guard !type.contains("\"") else { return nil }
        var parser = Parser(Array(type))
        guard let shape = parser.flattenStruct(), parser.atEnd else { return nil }
        if let first = shape.members.first, first == "f" || first == "d",
           shape.members.count <= maxHFAMembers, shape.members.allSatisfy({ $0 == first }) {
            return .homogeneousFloat(members: shape.members.count, memberSize: first == "f" ? 4 : 8)
        }
        return shape.size <= maxRegisterCompositeBytes ? .composite(size: shape.size) : .byReference
    }

    /// Exact byte extents for the stack locations produced by `locations`.
    /// The final packed scalar may occupy fewer than eight bytes, so its upper
    /// bytes cannot be inferred merely because no later argument follows it.
    static func stackSlotWidths(encoding: String, argumentCount: Int) -> [String: Int] {
        guard let types = parameterTypes(encoding: encoding, argumentCount: argumentCount) else { return [:] }
        let slots = locations(encoding: encoding, argumentCount: argumentCount)
        var widths: [String: Int] = [:]
        for (location, index) in slots where location.hasPrefix("stack@") {
            guard index < types.count,
                  let layout = ObjCTypeLayoutDecoder.layout(of: types[index]),
                  (1...8).contains(layout.size) else { return [:] }
            widths[location] = layout.size
        }
        return widths
    }

    /// Whether a store of `storedBytes` at a stack argument's offset is that
    /// argument (`bytes` wide) alone: it covers the argument, and no other
    /// stack argument starts inside it. Apple arm64 packs stack arguments, and
    /// at -O clang merges two packed ints' stores into one eight-byte store,
    /// which is not the first int. `storedBytes` 0 is an unknown store.
    static func storeHoldsOnlyArgument(at offset: Int, bytes: Int, storedBytes: Int, stackStarts: [Int]) -> Bool {
        storedBytes >= bytes && !stackStarts.contains { $0 > offset && $0 < offset + storedBytes }
    }

    static func floatingStackSlots(encoding: String, argumentCount: Int) -> Set<String> {
        guard let types = parameterTypes(encoding: encoding, argumentCount: argumentCount) else { return [] }
        return Set(locations(encoding: encoding, argumentCount: argumentCount).compactMap { location, index in
            guard location.hasPrefix("stack@"), index < types.count,
                  ["f", "d", "D"].contains(types[index]) else { return nil }
            return location
        })
    }

    private struct Parser {
        let chars: [Character]
        var index = 0
        init(_ chars: [Character]) { self.chars = chars }
        var atEnd: Bool { index == chars.count }
        var current: Character? { index < chars.count ? chars[index] : nil }
        mutating func skipOffsets() {
            while let c = current, c.isNumber || c == "+" || c == "-" { index += 1 }
        }
        mutating func quoted() -> Bool {
            guard current == "\"" else { return true }
            index += 1
            while let c = current, c != "\"" { index += 1 }
            guard current == "\"" else { return false }
            index += 1
            return true
        }
        mutating func type(depth: Int = 0) -> String? {
            guard depth < 64 else { return nil }
            while let c = current, "rnNoORVA".contains(c) { index += 1 }
            let start = index
            guard let c = current else { return nil }
            index += 1
            switch c {
            case "@":
                if current == "?" { index += 1 }
                else if !quoted() { return nil }
            case "^", "j":
                guard type(depth: depth + 1) != nil else { return nil }
            case "{", "(", "[":
                let closing: Character = c == "{" ? "}" : c == "(" ? ")" : "]"
                var closers = [closing]
                while let next = current, !closers.isEmpty {
                    if next == "\"" { guard quoted() else { return nil }; continue }
                    index += 1
                    if next == "{" { closers.append("}") }
                    else if next == "(" { closers.append(")") }
                    else if next == "[" { closers.append("]") }
                    else if "})]".contains(next) {
                        guard closers.last == next else { return nil }
                        closers.removeLast()
                    }
                }
                guard closers.isEmpty else { return nil }
            case "b":
                while let next = current, next.isNumber { index += 1 }
            default:
                guard "v?cCsSiIlLqQtTBfdD#:*%".contains(c) else { return nil }
            }
            return String(chars[start..<index])
        }
        /// The scalar members of the struct at `index`, nested structs
        /// flattened, with its size and alignment; moves past it. Nil for
        /// any member `aggregate(_:)` declines.
        mutating func flattenStruct(depth: Int = 0) -> (members: [Character], size: Int, alignment: Int)? {
            guard depth < 64, current == "{" else { return nil }
            index += 1
            while let c = current, c != "=", c != "}" { index += 1 }
            guard current == "=" else { return nil }
            index += 1
            var members: [Character] = []
            var size = 0, alignment = 1
            while current != nil, current != "}" {
                while let q = current, "rnNoORVA".contains(q) { index += 1 }
                let member: (members: [Character], size: Int, alignment: Int)
                if current == "{" {
                    guard let nested = flattenStruct(depth: depth + 1) else { return nil }
                    member = nested
                } else {
                    guard let code = current, let bytes = Self.memberBytes[code],
                          type(depth: depth + 1) != nil else { return nil }
                    member = ([code], bytes, bytes)
                }
                size = (size + member.alignment - 1) / member.alignment * member.alignment + member.size
                alignment = max(alignment, member.alignment)
                members += member.members
            }
            guard current == "}", !members.isEmpty else { return nil }
            index += 1
            return (members, (size + alignment - 1) / alignment * alignment, alignment)
        }
        /// The size, and alignment, of each scalar a struct member may be.
        /// `l` and `L` are left out: clang spells a 64-bit long `q`, and the
        /// runtime reads `l` as four bytes.
        private static let memberBytes: [Character: Int] = [
            "c": 1, "C": 1, "B": 1, "s": 2, "S": 2, "i": 4, "I": 4, "f": 4,
            "q": 8, "Q": 8, "d": 8, "@": 8, "#": 8, ":": 8, "*": 8, "^": 8,
        ]
    }
}
