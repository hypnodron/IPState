import Foundation
import Testing
import IPStateTestSupport

@MainActor
struct AsyncTestSupportTests {
    @Test func anUnmetConditionReturnsAtItsDeadline() async {
        #expect(await eventually(timeout: .milliseconds(20)) { false } == false)
    }

    @Test func taskCompletionTimesOutEvenWhenCancellationCannotReleaseTheOperation() async throws {
        var response: CheckedContinuation<Void, Never>?
        let pending = Task { await withCheckedContinuation { response = $0 } }
        defer { response?.resume(); pending.cancel() }
        try #require(await eventually { response != nil })
        #expect(await taskCompletes(pending, timeout: .milliseconds(20)) == false)
        #expect(pending.isCancelled)
        response?.resume()
        response = nil
        #expect(await taskCompletes(pending))
    }
}
