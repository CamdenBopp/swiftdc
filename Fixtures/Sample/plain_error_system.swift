// This separate image links only the real C getpid from libSystem.
@_silgen_name("system_error_arm")
func systemErrorArm() -> Int
@inline(never) public func positiveSystemProbe() -> Int { systemErrorArm() &+ 1 }

@_silgen_name("system_error_indirect_arm")
func systemErrorIndirectArm() -> Int
@inline(never) public func indirectSystemProbe() -> Int { systemErrorIndirectArm() &+ 1 }

import Darwin
// A throwing source signature still has a normal exit here: the exact C
// import preserves the entry's no-error state, independently of arity.
@inline(never) public func typedSystemProbe() throws -> Int { Int(getpid()) &+ 1 }

@_silgen_name("system_error_body_direct_arm")
func systemErrorBodyDirectArm() -> Int
@inline(never) public func directBodyProbe() -> Int { systemErrorBodyDirectArm() &+ 1 }

@_silgen_name("system_error_body_indirect_arm")
func systemErrorBodyIndirectArm() -> Int
@inline(never) public func indirectBodyProbe() -> Int { systemErrorBodyIndirectArm() &+ 1 }

@_silgen_name("system_error_return_control")
func systemErrorReturnControl(_ choice: Int) -> Int
@inline(never) public func returnDispatchProbe(_ choice: Int) -> Int { systemErrorReturnControl(choice) &+ 1 }

@_silgen_name("system_error_return_lr_control")
func systemErrorReturnLRControl() -> Int
@inline(never) public func returnLRProbe() -> Int { systemErrorReturnLRControl() &+ 1 }

@_silgen_name("system_error_return_alias_control")
func systemErrorReturnAliasControl() -> Int
@inline(never) public func returnAliasProbe() -> Int { systemErrorReturnAliasControl() &+ 1 }

@_silgen_name("system_error_return_register_control")
func systemErrorReturnRegisterControl() -> Int
@inline(never) public func returnRegisterProbe() -> Int { systemErrorReturnRegisterControl() &+ 1 }

@_silgen_name("system_error_return_register_good_control")
func systemErrorReturnRegisterGoodControl() -> Int
@inline(never) public func returnRegisterGoodProbe() -> Int { systemErrorReturnRegisterGoodControl() &+ 1 }

@_silgen_name("system_error_return_auth_control")
func systemErrorReturnAuthControl() -> Int
@inline(never) public func returnAuthProbe() -> Int { systemErrorReturnAuthControl() &+ 1 }

@_silgen_name("system_error_return_fallthrough_control")
func systemErrorReturnFallthroughControl() -> Int
@inline(never) public func returnFallthroughProbe() -> Int { systemErrorReturnFallthroughControl() &+ 1 }

@_silgen_name("system_error_return_deep_control")
func systemErrorReturnDeepControl() -> Int
@inline(never) public func returnDeepProbe() -> Int { systemErrorReturnDeepControl() &+ 1 }

@_silgen_name("system_error_return_fp_alias_control")
func systemErrorReturnFPFrameControl() -> Int
@inline(never) public func returnFPFrameProbe() -> Int { systemErrorReturnFPFrameControl() &+ 1 }

@_silgen_name("system_error_return_gp_alias_control")
func systemErrorReturnGPFrameControl() -> Int
@inline(never) public func returnGPFrameProbe() -> Int { systemErrorReturnGPFrameControl() &+ 1 }
