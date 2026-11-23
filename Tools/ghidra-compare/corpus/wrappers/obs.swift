import Observation
// @Observable class: getters call access(keyPath:), setters withMutation(keyPath:)
@Observable public final class Model {
  public var score: Int = 0
  public var name: String = ""
  public init() {}
}
// true: returns m.score (after registrar access)
public func getScore(_ m: Model) -> Int { m.score }
// true: m.score = v via withMutation
public func setScore(_ m: Model, _ v: Int) { m.score = v }
