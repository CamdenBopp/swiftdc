@inline(never)
private func sink(_ value: Int) {
    print("sink", value)
}

@inline(never)
private func intResult(_ value: Int) async -> Int {
    await Task.yield()
    return value &+ 1
}

@inline(never)
private func useInt(_ value: Int) async {
    sink(await intResult(value) &+ 2)
}

@inline(never)
private func parentFinished(_ value: Int) {
    print("parent", value)
}

@inline(never)
private func parent(_ value: Int) async {
    await useInt(value)
    // Keep the parent's own continuation live after the direct call.
    parentFinished(value)
}

@main
private struct ClosedAwaitHopDriver {
    static func main() async {
        guard CommandLine.arguments.count == 2,
              let input = Int(CommandLine.arguments[1])
        else {
            fatalError("Pass one signed 64-bit integer")
        }

        // Deliberately unstructured and detached. Do not use async let,
        // a task group, or an inline task as the proof root.
        let task = Task.detached {
            await parent(input)
        }
        await task.value
    }
}
