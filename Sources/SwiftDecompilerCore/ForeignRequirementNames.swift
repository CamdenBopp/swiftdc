import Foundation
import MachOKit
import MachOSwiftSection
import Demangling

/// Names the protocol requirements a shared-cache image's conformances reach
/// in another image.
///
/// A resilient witness prints as its implementation's symbol, or failing
/// that as its requirement's. The requirement of a conformance to
/// `Swift.Identifiable` is a descriptor in libswiftCore: on disk a bound
/// import with a name, in the cache a plain address this image's symbols do
/// not cover. SwiftDump then printed the implementation's address as a
/// function, `sub_1CAB7C369`, for what is an `associated conformance
/// descriptor`. The implementation of an associated type or conformance
/// witness is a mangled name, not code, and is often the same string for
/// several witnesses, so each is replaced in the order they print.
struct ForeignRequirementNames {
    private let machO: MachOFile
    private let extent: ImageExtent
    private let symbols: CacheSymbolResolver
    private let options: DemangleOptions

    init?(_ machO: MachOFile, options: DemangleOptions) {
        guard let extent = ImageExtent(cacheImage: machO), let symbols = CacheSymbolResolver(machO: machO) else { return nil }
        self.machO = machO
        self.extent = extent
        self.symbols = symbols
        self.options = options
    }

    func naming(in text: String, _ conformance: ProtocolConformance) -> String {
        var text = text
        var cursor = text.startIndex
        for witness in conformance.resilientWitnesses {
            guard case .element(let element)? = try? witness.requirement(in: machO.context) else { continue }
            // SwiftDump prints the requirement's default implementation
            // when it has one, as `AsyncIteratorProtocol.Failure` does.
            let printed = [element.defaultImplementationOffset, witness.implementationOffset].compactMap { offset in
                offset.flatMap { text.range(of: "\n    sub_" + machO.addressString(forOffset: $0) + "\n", range: cursor ..< text.endIndex) }
            }.min { $0.lowerBound < $1.lowerBound }
            guard let line = printed else { continue }
            guard !extent.contains(cacheOffset: element.offset) else {
                // This image's own requirement: `sub_` is what SwiftDump means.
                cursor = text.index(before: line.upperBound)
                continue
            }
            let replacement = "\n    " + name(ofRequirementAt: machO.address(forOffset: element.offset)) + "\n"
            let start = text.distance(from: text.startIndex, to: line.lowerBound)
            text.replaceSubrange(line, with: replacement)
            cursor = text.index(text.startIndex, offsetBy: start + replacement.count - 1)
        }
        return text
    }

    /// The exported name of the descriptor, or where it is: a requirement
    /// in another image with no export is still not a function.
    private func name(ofRequirementAt address: UInt64) -> String {
        guard let symbol = symbols.exportName(inTextSegmentAt: address), symbol.hasPrefix("_"),
              let node = try? demangleAsNode(String(symbol.dropFirst()))
        else { return "/* requirement in another image at 0x\(String(address, radix: 16)) */" }
        return node.print(using: options)
    }
}
