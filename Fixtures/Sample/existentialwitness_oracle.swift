// Native oracles for existentialwitness.swift, in their own module so the
// existential functions keep their existential parameters.
import ExistentialWitness

@_cdecl("existential_witness_measure")
public func existentialWitnessMeasure() -> Int { ExistentialWitness.measure(Square(3)) }

@_cdecl("existential_witness_grow")
public func existentialWitnessGrow() -> Int { ExistentialWitness.grow(Square(3), by: 4) }

@_cdecl("existential_witness_name")
public func existentialWitnessName() -> Int { ExistentialWitness.callName(Tag()) }

@_cdecl("existential_witness_name_then")
public func existentialWitnessNameThen() -> Int { ExistentialWitness.callNameThen(Tag(), 2) }

@_cdecl("existential_witness_lookup")
public func existentialWitnessLookup() -> Int { Registry(10).lookup(Tag()) }
