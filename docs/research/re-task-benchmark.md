# A reverse-engineering task benchmark (proposal, 2026-11-13)

How useful is swiftdc to someone reversing a Swift or Objective-C binary?
This turns that into numbers. Each task is a question a reverser really
asks, put to a fixture we write and compile ourselves, with the answer taken
from an oracle that is not swiftdc. Every answer is scored one of three
ways:

- **correct**: utility;
- **wrong**: a soundness failure, which must stay at zero;
- **declined**: the remaining gap (`?`, raw, or "not recorded").

The score is per task, per optimization level (-Onone, -O, -Osize; C at
-O0, -O2, -Os), and stripped and unstripped where the task allows. It is
reported as the three counts, never a single percentage, and tracked per
commit like the cost budget.

The task list started from the questions doronz88/swift_reversing teaches a
reader to answer by hand in IDA (conformances and their flags, which
function implements a requirement, associated conformances, strings,
calling conventions), widened to the work of reversing an app.

## Oracles

| Oracle | Gives |
|---|---|
| The fixture's source, with a machine-readable answer comment per task | the intended answer |
| `swiftc -emit-module-interface` | declarations, signatures, conformances |
| `swift-reflection-dump` | field layouts, associated types, captures |
| The dSYM (DWARF) | parameters, locals, types, line ranges |
| Native execution of the fixture | return values, call order, branch outcomes |
| `llvm-objdump`, `dyld_info`, `nm` | addresses, binds, fixups, exports |
| SDK headers | Objective-C framework declarations |

A task whose answer no oracle can check is not a task.

## Tasks

Each line is one task: the question, then what counts as correct.

### Types and metadata

1. List every nominal type the image defines, with its kind (class, struct, enum, actor, protocol). Correct: the set equals the interface's.
2. What are the stored properties of type T, in order, with types and byte offsets? Correct: names, types and offsets match the reflection dump.
3. What are the cases of enum E, and which carry payloads of what type?
4. What is the superclass chain of class C, including an Objective-C superclass?
5. Which generic parameters does type T have, with their constraints?
6. What is the size, stride and alignment of T?
7. Which types does a closure capture, in what layout? (Reflection capture descriptors.)
8. Which properties are `lazy`, wrapped (`@Published`, a custom wrapper) or `@objc dynamic`?

### Conformances and witnesses

9. Which protocols does T conform to, including retroactive and conditional conformances with their `where` clauses?
10. For conformance T: P, which function implements each requirement? Correct: requirement-to-symbol pairs match the witness table (and, when resilient, the resilient witness list).
11. What are T: P's associated types and their conformances?
12. Which conformances are synthesized (Equatable, Hashable, Codable) and which hand-written?
13. Which types conform to P anywhere in the image (the reverse query)?

### Functions and signatures

14. What is the full Swift signature of function F: labels, types, `throws`/typed throws, `async`, `inout`/`borrowing`/`consuming`, result? Correct: equals the interface line.
15. For a stripped function, how many arguments does it take, in which registers? Correct: matches DWARF / the source.
16. Which method of class C does vtable slot N call?
17. Is F a thunk (reabstraction, dispatch, partial-apply forwarder, `@objc` bridge), and to what?
18. Which functions are specializations of generic G, and for which types?
19. Which functions does the image export, and which are its entry points (main, `@main`, initializers, `+load`)?

### Calls and data flow

20. Who calls F? Correct: the caller set equals the set from the source, counting inlined call sites as absent.
21. What does F call, in order, on each path?
22. At call site S, what are the argument values? Correct: each rendered value equals the value native execution passes; a `?` is declined.
23. What does F return on each path, as a value or an expression of its arguments?
24. Which globals does F read and write?
25. Where is global G initialised, and with what value?
26. Which function's result flows into call S's argument N?

### Strings and constants

27. Which string literals does F use, byte for byte, including non-ASCII, escapes and interpolated segments?
28. Which strings does the image contain that no function references (dead or table-driven)?
29. Which numeric constants does F compare its input against (magic numbers, version checks)?
30. Which tables in `__const` does F index, with what element type?

### Control flow

31. Under what condition does F take each branch? Correct: the rendered condition agrees with native execution on sampled inputs, including the edges (0, -1, Int.min, UInt.max).
32. What are each loop's bounds and induction step?
33. For a switch, which case value reaches which body?
34. Under what conditions does F trap, abort or throw, and with what error value?
35. Which paths of F never return?

### Errors and async

36. Which errors can F throw, and under which conditions?
37. For async F, what are the suspension points, in order, and what does each await?
38. Which actor or executor does F run on (MainActor, an actor instance, generic)?
39. What does a `Task {}` or `withTaskGroup` body do, and where is its closure?

### Objective-C

40. Reconstruct class C's @interface: ivars with offsets, properties with attributes, methods with types. Correct: equals the header (SDK or fixture).
41. Which selectors does the image send, from where, to which receiver class?
42. Which methods does a category add, to which class?
43. What does a block passed to `dispatch_async` (or a completion handler) do, and what does it capture?
44. Which methods are swizzled (`method_exchangeImplementations`, `class_replaceMethod`), and with what?
45. Which `@objc` Swift methods are exposed, under which selectors?

### App-level questions

These use fixture apps written to look like the real thing, never code
from a real app.

46. What is the base URL of the API, and which endpoints does the app call, with which HTTP methods?
47. Which keys does the app read from and write to `UserDefaults`, and with what types?
48. Which keychain items does it store (service, account, accessibility class)?
49. What are the JSON keys of each Codable model, including `CodingKeys` renames?
50. Which notification names does it post and observe?
51. Which URL schemes and universal-link paths does it handle, and which function routes each?
52. What does a button do: the `@IBAction`/target-action or SwiftUI closure, and what it calls?
53. Which analytics events does it log, with which parameters?
54. Does it pin certificates, and against which keys or hashes?
55. Where does it check an in-app purchase or licence, and what makes the check pass?
56. Which feature flags or remote-config keys gate which code?
57. Which crypto does it use (CryptoKit, CommonCrypto), on what data, with what key source?
58. Which entitlement-gated or privacy-sensitive APIs does it call (location, contacts, camera)?
59. Which jailbreak, debugger or integrity checks does it make, and what happens when one fails?
60. Which hard-coded secrets does it carry (fixture placeholders only)?

## Running it

- One fixture per group, each built at every level, stripped and not.
- The answer comment format and the harness belong with the existing
  `score` command (`swiftdc score`, the oracle manifest
  `swiftdc-oracle/1`), extended from integer returns to these answers.
- The harness reports per task and level: correct, wrong, declined. Any
  wrong answer fails the gate the way a test does.
- The first run is a baseline. A task that cannot be asked of swiftdc at
  all (no view answers it, for example task 13) counts as declined and is
  listed as a feature gap.

## Already known from a first look

- Task 10: on `libProtocolWitness.resilient.dylib`, `dump` prints
  `extension ProtocolWitness.Thing: ProtocolWitness.Named {}` and names no
  implementation for either requirement.
- Tasks 20, 41: `xrefs` matches only function names (roadmap item 1).
- Task 43: no block model (roadmap item 2).
