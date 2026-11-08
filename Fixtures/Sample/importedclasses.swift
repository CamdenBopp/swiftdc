import Foundation
import CoreGraphics

// Merely declaring these parameters does not require a class-symbol reference.
// Their mangled signatures still distinguish imported classes from C structs.
@inline(never) public func note(_ n: Int) -> Int { n &+ 1 }
public func withObject(_ n: Int, _ object: NSObject) -> Int { note(n) }
public func withOptionalObject(_ n: Int, _ object: NSObject?) -> Int { note(n &+ 2) }
public func withPoint(_ n: Int, _ point: CGPoint) -> Int { note(n &+ 3) }
