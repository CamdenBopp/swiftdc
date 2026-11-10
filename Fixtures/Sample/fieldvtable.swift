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

// The receiver is an argument whose declared type is the class: `ldr x8,
// [x0]; ldr x8, [x8, #slot]; mov x20, x0; blr x8`.
@inline(never) public func runEngine(_ engine: Engine) -> Int { engine.start() }
@inline(never) public func runOther(_ engine: FieldVTableOther.Engine) -> Int { engine.coast() }

extension Car {
    @inline(never) public func borrow(_ other: Engine, for seconds: Int) -> Int { other.stop(after: seconds) }
}

@_cdecl("field_vtable_run_turbo")
public func fieldVTableRunTurbo() -> Int { runEngine(Turbo()) }

@_cdecl("field_vtable_run_other")
public func fieldVTableRunOther() -> Int { runOther(FieldVTableOther.Engine()) }

@_cdecl("field_vtable_borrow")
public func fieldVTableBorrow() -> Int { Car(Engine()).borrow(Turbo(), for: 4) }

// The receiver is a field of a class argument: `ldr x20, [x0, #0x10]; ldr
// x8, [x20]; ldr x8, [x8, #slot]; blr x8`, typed by Car's field record.
@inline(never) public func driveHeld(_ car: Car) -> Int { car.engine.start() }
@inline(never) public func driveSpare(_ car: Car) -> Int { car.spare?.start() ?? -1 }

@_cdecl("field_vtable_drive_held")
public func fieldVTableDriveHeld() -> Int { driveHeld(Car(Turbo())) }

// The receiver is a call's result, typed by the callee's return type:
// `bl makeEngine; ldr x8, [x0]; ldr x8, [x8, #slot]; mov x20, x0; blr x8`.
@inline(never) public func makeEngine(_ turbo: Bool) -> Engine { turbo ? Turbo() : Engine() }
@inline(never) public func startMade(_ turbo: Bool) -> Int { makeEngine(turbo).start() }

@_cdecl("field_vtable_start_made")
public func fieldVTableStartMade() -> Int { startMade(true) }
