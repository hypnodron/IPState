import Foundation

@MainActor
public func eventually(timeout: Duration = .seconds(2), _ condition: @MainActor () async -> Bool) async -> Bool {
    // Predicates inspect state; they must not wait for the operation being observed.
    let deadline = ContinuousClock.now.advanced(by: timeout)
    while !Task.isCancelled {
        if await condition() { return true }
        if ContinuousClock.now >= deadline { return false }
        do { try await Task.sleep(for: .milliseconds(5)) }
        catch { return false }
    }
    return false
}

@MainActor
public func taskCompletes(_ task: Task<Void, Never>, timeout: Duration = .seconds(2)) async -> Bool {
    var completed = false
    // An unstructured observer lets the deadline return even if the operation ignores cancellation.
    let observer = Task { await task.value; completed = true }
    defer {
        observer.cancel()
        if !completed { task.cancel() }
    }
    return await eventually(timeout: timeout) { completed }
}
