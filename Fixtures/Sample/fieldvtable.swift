// A class method called on a stored field of self dispatches through the
// field object's vtable: `ldr x20, [x20, #k]; ldr x8, [x20]; ldr x8, [x8,
// #slot]; blr x8`. The slot names the method the field's declared class
// declares there, whichever subclass the object is: `Car(Turbo()).go()`
// runs Turbo.start() (returns 3) through Engine.start()'s slot.
import FieldVTableOther

open class Engine {
    public var rpm = 0
    public init() {}
    open func start() -> Int { rpm = 1; return rpm }
    open func stop(after seconds: Int) -> Int { rpm = 0; return seconds }
}

open class Turbo: Engine {
    public override init() { super.init() }
    open override func start() -> Int { rpm = 3; return rpm }
}

public final class Car {
    public let engine: Engine
    public var spare: Engine?
    public init(_ engine: Engine) { self.engine = engine }
    @inline(never) public func go() -> Int { engine.start() }
    @inline(never) public func park(_ seconds: Int) -> Int { engine.stop(after: seconds) }
    @inline(never) public func goSpare() -> Int { spare?.start() ?? -1 }
}

@_cdecl("field_vtable_go_turbo")
public func fieldVTableGoTurbo() -> Int { Car(Turbo()).go() }

@_cdecl("field_vtable_park")
public func fieldVTablePark() -> Int { Car(Engine()).park(9) }

// A field of another module's same-named class: slot 0x78 of
// FieldVTableOther.Engine is not FieldVTable.Engine.start().
public final class Garage {
    public let other: FieldVTableOther.Engine
    public init(_ other: FieldVTableOther.Engine) { self.other = other }
    @inline(never) public func run() -> Int { other.coast() }
}

@_cdecl("field_vtable_garage")
public func fieldVTableGarage() -> Int { Garage(FieldVTableOther.Engine()).run() }
