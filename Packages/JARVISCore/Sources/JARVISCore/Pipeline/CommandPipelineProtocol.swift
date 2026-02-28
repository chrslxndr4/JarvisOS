import Foundation

public protocol CommandPipelineProtocol: Actor {
    func start() async throws
    func stop() async
    func processCommand(_ command: JARVISCommand) async throws -> ExecutionResult
}
