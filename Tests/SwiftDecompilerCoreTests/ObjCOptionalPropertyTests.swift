import Foundation
import Testing
@testable import SwiftDecompilerCore

/// A protocol's property list has no optional flag: `@optional @property
/// NSString *nickname` rendered under `@required` (`objcoptionalprop.m`).
/// Its getter's method list decides, a custom getter included, on both the
/// instance and the class side.
@Test func anOptionalProtocolPropertyRendersOptionalIfPresent() throws {
    let path = "Fixtures/Sample/libObjCOptionalProp.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let text = ObjCDumper().dump(try BinaryLoader.load(path: path))
    let start = try #require(text.range(of: "@protocol OPThing"))
    let body = text[start.lowerBound...].prefix { _ in true }
    let protocolText = String(body[..<(body.range(of: "@end")?.lowerBound ?? body.endIndex)])
    let optional = try #require(protocolText.range(of: "@optional"), Comment(rawValue: protocolText))
    let required = protocolText[..<optional.lowerBound], optionalPart = protocolText[optional.upperBound...]
    #expect(required.contains("NSString *name;"), Comment(rawValue: protocolText))
    for property in ["NSString *nickname;", "BOOL custom;", "long long shared;"] {
        #expect(optionalPart.contains(property) && !required.contains(property), Comment(rawValue: protocolText))
    }
}
