// A five-word struct is returned through x8. resultrole.s defines
// functions returning it that fill the buffer and then call a function
// named like a runtime entry point, with x8 unchanged. Whether the fill
// is still the result depends on where that callee's own declaration puts
// its result, and on the name being bound to the library that declares it.
//
// Bound to libswiftCore, declared to return in registers or nothing, so
// x8 is ignored and the fill is the result:
//   keptAfterRelease      void swift_release(HeapObject *)          Big of 9s
//   keptAfterAllocObject  HeapObject *swift_allocObject(...)        Big of 11s
//   keptAfterAllocBox     BoxPair swift_allocBox(...), two words    Big of 13s
//   keptAfterReleaseN     void swift_release_n(HeapObject *, n)     Big of 15s
//
// Bound to libResultRoleProvider (resultroleprovider.c), whose functions
// return five words through x8, so the fill is overwritten:
//   staleAfterForeignFuture  swift_opaqueResult, a name no runtime
//                            declares                               21...25
//   staleAfterForeignAlloc   swift_slowAlloc, a name the runtime
//                            declares as returning a pointer        31...35
//
// Bound to libswiftCore and declared to return three words through x8
// (SwiftShims FoundationShims.h:58, _SwiftNSOperatingSystemVersion):
//   staleAfterVersion     _swift_stdlib_operatingSystemVersion      the
//                         version in the first three words, 23 after
//
// Bound to libobjc, the forwarding entry (objc/message.h:296, declared
// `void (void)`): like a send it returns whatever the forwarded method
// returns, which for a five-word struct is through x8:
//   staleAfterForward     _objc_msgForward                          unknown, 27 before
public struct Big { public var a, b, c, d, e: Int }
@inline(never) public func make(_ x: Int) -> Big { Big(a: x, b: x, c: x, d: x, e: x) }
