// C entry thunks let the native C oracle call the Swift wrappers with a
// compiler-generated C ABI. The imported SDK spellings remain Swiftcc.
// Distinct direct/indirect arithmetic keeps optimized wrappers from merging
// into a shared function whose callee is an unknown pointer parameter.
@_silgen_name("getpid")
func importedPID(_ value: Double) throws -> Double
@_silgen_name("named_foreign_pid_indirect_entry")
func indirectPID(_ value: Double) throws -> Double
@_silgen_name("sqrt")
func importedSqrt(_ value: Int64) throws -> Int64
@_silgen_name("named_foreign_sqrt_indirect_entry")
func indirectSqrt(_ value: Int64) throws -> Int64
@_silgen_name("free")
func importedFree(_ value: Int64) throws -> Int64
@_silgen_name("named_foreign_free_indirect_entry")
func indirectFree(_ value: Int64) throws -> Int64
@_silgen_name("CGRectInset")
func importedRect(_ value: Int64) throws -> Int64
@_silgen_name("named_foreign_rect_indirect_entry")
func indirectRect(_ value: Int64) throws -> Int64
@_silgen_name("printf")
func importedFormat(_ value: Double, _ weight: Int64) throws -> Int64
@_silgen_name("named_foreign_format_indirect_entry")
func indirectFormat(_ value: Double, _ weight: Int64) throws -> Int64

@_cdecl("named_foreign_pid")
@inline(never) public func foreignPIDDirect(_ value: Double) -> Double {
    do { return (try importedPID(value)) * 2 } catch { return -1001 }
}

@_cdecl("named_foreign_pid_indirect")
@inline(never) public func foreignPIDIndirect(_ value: Double) -> Double {
    do { return (try indirectPID(value)) * 4 } catch { return -1001 }
}

@_cdecl("named_foreign_sqrt")
@inline(never) public func foreignSqrtDirect(_ value: Int64) -> Int64 {
    do { return (try importedSqrt(value)) &+ 3 } catch { return -101 }
}

@_cdecl("named_foreign_sqrt_indirect")
@inline(never) public func foreignSqrtIndirect(_ value: Int64) -> Int64 {
    do { return (try indirectSqrt(value)) &+ 4 } catch { return -101 }
}

@_cdecl("named_foreign_free")
@inline(never) public func foreignFreeDirect(_ value: Int64) -> Int64 {
    do { return (try importedFree(value)) &+ 5 } catch { return -102 }
}

@_cdecl("named_foreign_free_indirect")
@inline(never) public func foreignFreeIndirect(_ value: Int64) -> Int64 {
    do { return (try indirectFree(value)) &+ 6 } catch { return -102 }
}

@_cdecl("named_foreign_rect")
@inline(never) public func foreignRectDirect(_ value: Int64) -> Int64 {
    do { return (try importedRect(value)) &* 3 } catch { return -103 }
}

@_cdecl("named_foreign_rect_indirect")
@inline(never) public func foreignRectIndirect(_ value: Int64) -> Int64 {
    do { return (try indirectRect(value)) &* 4 } catch { return -103 }
}

@_cdecl("named_foreign_format")
@inline(never) public func foreignFormatDirect(_ value: Double, _ weight: Int64) -> Int64 {
    do { return (try importedFormat(value, weight)) &+ 7 } catch { return -104 }
}

@_cdecl("named_foreign_format_indirect")
@inline(never) public func foreignFormatIndirect(_ value: Double, _ weight: Int64) -> Int64 {
    do { return (try indirectFormat(value, weight)) &+ 8 } catch { return -104 }
}
