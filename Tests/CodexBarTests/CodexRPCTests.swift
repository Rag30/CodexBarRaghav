import Foundation
import Testing
@testable import CodexBarCore

struct CodexRPCTests {
    private struct StubLocalizedError: LocalizedError {
        let message: String

        var errorDescription: String? {
            self.message
        }
    }

    actor AttemptCounter {
        private var attempts = 0

        func increment() -> Int {
            self.attempts += 1
            return self.attempts
        }

        func value() -> Int {
            self.attempts
        }
    }

    @Test
    func `output framer preserves trailing line on EOF`() {
        var buffer = Data()
        let firstInput = #"{"id":1}"# + "\n" + #"{"id":2"#
        let secondInput = #"}"# + "\n" + #"{"id":3}"#

        let firstChunk = CodexRPCOutputFramer.appendAndDrainLines(
            buffer: &buffer,
            data: Data(firstInput.utf8))
        let secondChunk = CodexRPCOutputFramer.appendAndDrainLines(
            buffer: &buffer,
            data: Data(secondInput.utf8))
        let remainder = CodexRPCOutputFramer.drainRemainder(buffer: &buffer)

        #expect(firstChunk == [Data(#"{"id":1}"#.utf8)])
        #expect(secondChunk == [Data(#"{"id":2}"#.utf8)])
        #expect(remainder == Data(#"{"id":3}"#.utf8))
        #expect(CodexRPCOutputFramer.drainRemainder(buffer: &buffer) == nil)
    }

    @Test
    func `retry policy retries closed stdout once`() async throws {
        let attempts = AttemptCounter()

        let output = try await CodexRPCRetryPolicy.run(maxAttempts: 2, retryDelayNanoseconds: 0) {
            let attempt = await attempts.increment()
            if attempt == 1 {
                throw StubLocalizedError(message: "Codex returned invalid data: codex app-server closed stdout")
            }
            return "ok"
        }

        #expect(output == "ok")
        #expect(await attempts.value() == 2)
    }

    @Test
    func `retry policy does not retry unrelated rpc failures`() async {
        let attempts = AttemptCounter()

        do {
            _ = try await CodexRPCRetryPolicy.run(maxAttempts: 2, retryDelayNanoseconds: 0) {
                _ = await attempts.increment()
                throw StubLocalizedError(message: "Codex connection failed: permission denied")
            }
            Issue.record("Expected retry policy to throw the original non-retryable error")
        } catch {
            #expect(error.localizedDescription == "Codex connection failed: permission denied")
            #expect(await attempts.value() == 1)
        }
    }
}
