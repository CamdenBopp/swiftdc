// Another module's class that shares its simple name with FieldVTable's
// Engine. A field of this type must not name FieldVTable.Engine's methods:
// its vtable is laid out by this module, not by the image under analysis.
open class Engine {
    public init() {}
    open func spin() -> Int { 5 }
    open func idle() -> Int { 6 }
    open func coast() -> Int { 7 }
    open func brake() -> Int { 8 }
}
