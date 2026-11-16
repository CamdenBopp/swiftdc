# swift-argument-parser examples: `roll`

Built from [https://github.com/apple/swift-argument-parser](https://github.com/apple/swift-argument-parser) at `d7b6cebecb27`. Every `func` declared in `Examples/roll/SplitMix64.swift`, in source order: its source, then swiftdc's rendering, then Ghidra's, both for the same address in the same release binary.

swiftdc `5b97024`, Ghidra , Apple Swift version 6.4 (swiftlang-6.4.0.34.1 clang-2100.3.34.1). Regenerate with `Tools/samples/build.sh` and `Tools/samples/render.py`.

## `SplitMix64.next`

From `Examples/roll/SplitMix64.swift`.

```swift
  mutating func next() -> UInt64 {
    self.state &+= 0x9e37_79b9_7f4a_7c15
    var z: UInt64 = self.state
    z = (z ^ (z &>> 30)) &* 0xbf58_476d_1ce4_e5b9
    z = (z ^ (z &>> 27)) &* 0x94d0_49bb_1331_11eb
    return z ^ (z &>> 31)
  }
```

The optimizer inlined it into every caller, so the binary has no body of its own to decompile.
