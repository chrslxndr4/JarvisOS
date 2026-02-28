import Foundation

public protocol MessageIntaking: Actor {
    func startListening() async throws
    func stopListening() async
    var incomingCommands: AsyncStream<JARVISCommand> { get }
}

public protocol IntentRouting: Actor {
    func route(command: JARVISCommand, catalog: CommandCatalog) async throws -> JARVISIntent
    func warmUp() async throws
    func coolDown() async
}

public protocol CommandCataloging: Actor {
    func refresh() async throws
    var catalog: CommandCatalog { get }
    func validate(intent: JARVISIntent) -> Bool
}

public protocol CommandExecuting: Actor {
    func execute(intent: JARVISIntent) async throws -> ExecutionResult
}

public protocol MemoryStoring: Actor {
    func storeCommandLog(command: JARVISCommand, intent: JARVISIntent?, result: ExecutionResult?) async throws
    func storeNote(content: String, tags: [String]) async throws
    func queryContext(limit: Int) async throws -> [String]
    func search(query: String) async throws -> [String]
}

public protocol ResponseHandling: Actor {
    func send(response: ExecutionResult, for command: JARVISCommand) async throws
    func formatConfirmation(intent: JARVISIntent) -> String
}
