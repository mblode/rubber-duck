import Foundation

struct ToolDefinitions {
    static func allTools() -> [[String: Any]] {
        return [
            readFile,
            writeFile,
            editFile,
            bash,
            grepSearch,
            findFiles,
            webSearch,
        ]
    }

    // MARK: - File Tools

    private static let readFile: [String: Any] = [
        "type": "function",
        "name": "read_file",
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
        "name": "write_file",
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
        "name": "edit_file",
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
        "name": "bash",
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
        "name": "grep_search",
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
        "name": "find_files",
        "description": "Find files matching a glob pattern. Returns a list of matching file paths relative to the workspace root.",
        "parameters": [
            "type": "object",
            "properties": [
                "pattern": [
                    "type": "string",
                    "description": "Glob pattern to match file paths against, e.g. \"**/*.swift\" or \"src/*.ts\". Omit or use \"**/*\" to list all files.",
                ],
                "path": [
                    "type": "string",
                    "description": "Subdirectory to search in (relative to workspace root). Searches entire workspace if omitted.",
                ],
                "include_hidden": [
                    "type": "boolean",
                    "description": "Include hidden files and directories (dot-prefixed) in matches. Defaults to false.",
                ],
                "include_directories": [
                    "type": "boolean",
                    "description": "Include directory paths in the output. Defaults to false (files only).",
                ],
            ],
            "required": [],
            "additionalProperties": false,
        ] as [String: Any],
    ]

    private static let webSearch: [String: Any] = [
        "type": "function",
        "name": "web_search",
        "description": "Search the public web for up-to-date information and return top results with URLs. Use this for recent events, announcements, and facts likely to change over time.",
        "parameters": [
            "type": "object",
            "properties": [
                "query": [
                    "type": "string",
                    "description": "Search query in natural language",
                ],
                "num_results": [
                    "type": "integer",
                    "description": "Maximum number of results to return (1-10). Defaults to 5.",
                ],
                "include_domains": [
                    "type": "array",
                    "items": ["type": "string"],
                    "description": "Optional list of domains to include, e.g. [\"openai.com\", \"docs.exa.ai\"]",
                ],
                "exclude_domains": [
                    "type": "array",
                    "items": ["type": "string"],
                    "description": "Optional list of domains to exclude.",
                ],
                "include_text": [
                    "type": "boolean",
                    "description": "Include extracted page text snippets in results. Defaults to false.",
                ],
            ],
            "required": ["query"],
            "additionalProperties": false,
        ] as [String: Any],
    ]
}
