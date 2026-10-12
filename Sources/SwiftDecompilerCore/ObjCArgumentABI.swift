/// Darwin arm64 uses independent integer and floating-point argument banks.
/// Recovered from the pre-merge stash (d921fc1, improve/source-findings).
/// Type-encoding offsets describe the runtime method frame, not register slots.
/// Only scalar signatures are classified; aggregates decline rather than shift
/// subsequent arguments into incorrect registers.
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

    static func locations(encoding: String, argumentCount: Int) -> [String: Int] {
        guard let types = parameterTypes(encoding: encoding, argumentCount: argumentCount) else { return [:] }
        var gp = 2, fp = 0, stack = 0
        var result: [String: Int] = [:]
        for (argument, type) in types.enumerated() {
            guard let code = type.first else { return [:] }
            let floating = code == "f" || code == "d" || code == "D"
            guard floating || "cCsSiIlLqQB@#:*^".contains(code),
                  let layout = ObjCTypeLayoutDecoder.layout(of: type) else { return [:] }
            if floating && fp < 8 {
                result["v\(fp)"] = argument
                fp += 1
            } else if !floating && gp < 8 {
                result["x\(gp)"] = argument
                gp += 1
            } else {
                // Apple arm64 packs stack arguments to their natural alignment,
                // unlike generic AAPCS64's minimum eight-byte slots.
                stack = (stack + layout.alignment - 1) / layout.alignment * layout.alignment
                result["stack@\(stack)"] = argument
                stack += layout.size
            }
        }
        return result
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
    }
}
