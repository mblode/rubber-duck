import Foundation

/// Protocol for individual tool implementations.
/// Each tool handler declares its name and execution logic.
protocol ToolHandler {
    var toolName: String { get }
    func execute(arguments: [String: Any]) -> String
}
