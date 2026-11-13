/// Runtime entry points the generated `SwiftRuntimeSignatures` leaves out
/// because they are generic Swift functions under C names, each checked
/// by hand against the runtime's body and the compiler's call sites, in
/// the format of `SDKCPrototypes`.
///
/// The key path intrinsics (stdlib KeyPath.swift, `@_silgen_name`) are
/// generic over `Root` and `Value`, but take no metadata: it is read from
/// the key path's class (`ldr x8, [x1]`, then its generic arguments). So
/// each takes a fixed register list, at -Onone and -O alike:
///
/// - `swift_getAtKeyPath`: x0 the root's address, x1 the key path; the
///   value returns through x8, which the format cannot state, so the
///   result is `v`: x0 carries nothing.
/// - `swift_setAtWritableKeyPath`: x0 the root's address (inout), x1 the
///   key path, x2 the new value's address.
/// - `swift_setAtReferenceWritableKeyPath`: x0 the root's address, x1 the
///   key path, x2 the new value's address.
///
/// Without these, a call took whatever registers were live past them:
/// `swift_getAtKeyPath(local_30, arg1, arg1, arg2)`.
///
/// The getter's result buffer in x8 is also an input: the call writes
/// through it, so a value stored there before the call must not survive it
/// (`resultThroughX8`). Its arity alone passed x0 and x1, and a 77 stored
/// at the buffer before the call was read back as the result.
enum SwiftIntrinsicSignatures {
    static let table: [String: String] = [
        "swift_getAtKeyPath": "v ii",
        "swift_setAtWritableKeyPath": "v iii",
        "swift_setAtReferenceWritableKeyPath": "v iii",
    ]

    /// Entry points whose result is written through the buffer in x8.
    static let resultThroughX8: Set<String> = ["swift_getAtKeyPath"]
}
