import Foundation

/// Canonical tool name constants shared between definitions and handlers.
enum ToolName {
    static let readFile = "read_file"
    static let writeFile = "write_file"
    static let editFile = "edit_file"
    static let bash = "bash"
    static let grepSearch = "grep_search"
    static let findFiles = "find_files"
}

struct ToolDefinitions {
    static func allTools() -> [[String: Any]] {
        return [
            readFile,
            writeFile,
            editFile,
            bash,
            grepSearch,
            findFiles,
        ]
    }

    // MARK: - File Tools

    private static let readFile: [String: Any] = [
        "type": "function",
        "name": ToolName.readFile,
        "description": "Read the contents of a file at the given path relative to the workspace root.",
        "parameters": [
            "type": "object",
            "properties": [
                "path": [
                    "type": "string",
                    "description": "Relative path from workspace root to the file to read",
                ],
            ],
            "required": ["path"],
            "additionalProperties": false,
        ] as [String: Any],
    ]

    private static let writeFile: [String: Any] = [
        "type": "function",
        "name": ToolName.writeFile,
        "description": "Write content to a file, creating it and any parent directories if they don't exist. Overwrites existing content.",
        "parameters": [
            "type": "object",
            "properties": [
                "path": [
                    "type": "string",
                    "description": "Relative path from workspace root to the file to write",
                ],
                "content": [
                    "type": "string",
                    "description": "The full content to write to the file",
                ],
            ],
            "required": ["path", "content"],
            "additionalProperties": false,
        ] as [String: Any],
    ]

    private static let editFile: [String: Any] = [
        "type": "function",
        "name": ToolName.editFile,
        "description": "Find and replace text in a file. The old_text must match exactly (including whitespace and indentation).",
        "parameters": [
            "type": "object",
            "properties": [
                "path": [
                    "type": "string",
                    "description": "Relative path from workspace root to the file to edit",
                ],
                "old_text": [
                    "type": "string",
                    "description": "The exact text to find in the file",
                ],
                "new_text": [
                    "type": "string",
                    "description": "The text to replace it with",
                ],
            ],
            "required": ["path", "old_text", "new_text"],
            "additionalProperties": false,
        ] as [String: Any],
    ]

    // MARK: - Shell

    private static let bash: [String: Any] = [
        "type": "function",
        "name": ToolName.bash,
        "description": "Run a shell command in the workspace directory and return its stdout and stderr. Use for builds, tests, git operations, or any CLI task.",
        "parameters": [
            "type": "object",
            "properties": [
                "command": [
                    "type": "string",
                    "description": "The shell command to execute",
                ],
            ],
            "required": ["command"],
            "additionalProperties": false,
        ] as [String: Any],
    ]

    // MARK: - Search Tools

    private static let grepSearch: [String: Any] = [
        "type": "function",
        "name": ToolName.grepSearch,
        "description": "Search file contents using a regex pattern. Returns matching lines with file paths and line numbers.",
        "parameters": [
            "type": "object",
            "properties": [
                "pattern": [
                    "type": "string",
                    "description": "Regex pattern to search for",
                ],
                "path": [
                    "type": "string",
                    "description": "Subdirectory to search in (relative to workspace root). Searches entire workspace if omitted.",
                ],
                "include": [
                    "type": "string",
                    "description": "File glob to filter which files are searched, e.g. \"*.swift\" or \"*.ts\"",
                ],
            ],
            "required": ["pattern"],
            "additionalProperties": false,
        ] as [String: Any],
    ]

    private static let findFiles: [String: Any] = [
        "type": "function",
        "name": ToolName.findFiles,
        "description": "Find files matching a glob pattern. Returns a list of matching file paths relative to the workspace root.",
        "parameters": [
            "type": "object",
            "properties": [
                "pattern": [
                    "type": "string",
                    "description": "Glob pattern to match file paths against, e.g. \"**/*.swift\" or \"src/*.ts\"",
                ],
                "path": [
                    "type": "string",
                    "description": "Subdirectory to search in (relative to workspace root). Searches entire workspace if omitted.",
                ],
            ],
            "required": ["pattern"],
            "additionalProperties": false,
        ] as [String: Any],
    ]
}
