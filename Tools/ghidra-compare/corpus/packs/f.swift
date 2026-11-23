public protocol P {}
public protocol Src<Out> { associatedtype Out }
public class Base { public init() {} }
public struct F {
  public var a: any (Base & P).Type   // existential metatype of class composition
  public var b: (any P).Type           // metatype of the existential itself
  public var c: any P.Type             // existential metatype
  public var d: any Src<Int>           // constrained existential
  public var e: (any Src<Int>).Type    // metatype of constrained existential
  public var g: [any Src<String>]
}
