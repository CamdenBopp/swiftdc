import PlainErrorABI
import PlainErrorSystem

let inputs = [-37, -1, 0, 1, 37, Int.max]
for input in inputs {
    let expected = input < 0 ? -8 : (input &+ 137)
    precondition(catchPlainProbe(input) == expected)
    let catalogExpected = input < 0 ? -11 : ((input &+ 37) &* 3)
    precondition(catchCatalogProbe(input) == catalogExpected)
    precondition(positiveSystemProbe() == 2)
    precondition(indirectSystemProbe() == 2)
    precondition(directBodyProbe() == 2)
    precondition(indirectBodyProbe() == 2)
    precondition(returnDispatchProbe(input) == (input == 0 ? 2 : 1))
    precondition(returnLRProbe() == 1)
    precondition(returnAliasProbe() == 2)
    precondition(returnRegisterProbe() == 1)
    precondition(returnRegisterGoodProbe() == 2)
    precondition(returnAuthProbe() == 2)
    precondition(returnFallthroughProbe() == 1)
    precondition(returnDeepProbe() == 1)
    precondition(returnFPFrameProbe() == 1)
    precondition(returnGPFrameProbe() == 1)
    var plainForwarded: Int?
    do { plainForwarded = try forwardPlainProbe(input) } catch { plainForwarded = nil }
    precondition(plainForwarded == (input < 0 ? nil : ((input &+ 37) &+ 17)))
    var catalogForwarded: Int?
    do { catalogForwarded = try forwardCatalogProbe(input) } catch { catalogForwarded = nil }
    precondition(catalogForwarded == (input < 0 ? nil : ((input &+ 37) &* 7)))
    let systemValue = try typedSystemProbe()
    precondition(systemValue > 0)
}
print("PASS 114 native plain-name Swift error and system C observations")
