import Foundation

struct WorkspaceContext {
    let rootPath: URL
}

class ToolExecutor {
    let workspace: WorkspaceContext
    var safeMode: Bool = false {
        didSet {
            for i in handlers.indices {
                if var bashTool = handlers[i] as? BashTool {
                    bashTool.safeMode = safeMode
                    handlers[i] = bashTool
                } else if var writeTool = handlers[i] as? WriteFileTool {
                    writeTool.safeMode = safeMode
                    handlers[i] = writeTool
                } else if var editTool = handlers[i] as? EditFileTool {
                    editTool.safeMode = safeMode
                    handlers[i] = editTool
                }
            }
        }
    }

    static let maxOutputSize = 102_400 // 100KB

    private var handlers: [ToolHandler]

    init(workspace: WorkspaceContext) {
        self.workspace = workspace
        self.handlers = [
            ReadFileTool(workspace: workspace),
            WriteFileTool(workspace: workspace),
            EditFileTool(workspace: workspace),
            BashTool(workspace: workspace),
            GrepSearchTool(workspace: workspace),
            FindFilesTool(workspace: workspace),
        ]
    }

    func execute(toolName: String, arguments: String) -> String {
        guard let data = arguments.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return "Error: Invalid JSON arguments"
        }

        guard let handler = handlers.first(where: { $0.toolName == toolName }) else {
            return "Error: Unknown tool '\(toolName)'"
        }

        return handler.execute(arguments: json)
    }
}

// MARK: - Shared Utilities

enum PathError: Error {
    case escapesWorkspace
}

func canonicalizedFileURL(_ url: URL) -> URL {
    url.standardizedFileURL.resolvingSymlinksInPath().standardizedFileURL
}

func canonicalizedPathForContainment(_ url: URL) -> URL {
    let fileManager = FileManager.default
    var existingAncestor = url.standardizedFileURL
    var unresolvedComponents: [String] = []

    while !fileManager.fileExists(atPath: existingAncestor.path) {
        let parent = existingAncestor.deletingLastPathComponent().standardizedFileURL
        if parent.path == existingAncestor.path {
            break
        }

        let component = existingAncestor.lastPathComponent
        if !component.isEmpty {
            unresolvedComponents.insert(component, at: 0)
        }
        existingAncestor = parent
    }

    var canonicalized = canonicalizedFileURL(existingAncestor)
    for component in unresolvedComponents {
        canonicalized.appendPathComponent(component)
    }
    return canonicalized.standardizedFileURL
}

func isWithinDirectory(_ candidate: URL, root: URL) -> Bool {
    let candidatePath = candidate.path
    let rootPath = root.path

    if candidatePath == rootPath {
        return true
    }

    let rootWithSeparator = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
    return candidatePath.hasPrefix(rootWithSeparator)
}

func pathRelativeToRoot(_ candidate: URL, root: URL) -> String {
    let candidatePath = candidate.path
    let rootPath = root.path
    if candidatePath == rootPath {
        return ""
    }

    let rootWithSeparator = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
    return String(candidatePath.dropFirst(rootWithSeparator.count))
}

func resolvedPath(for path: String, workspace: WorkspaceContext) -> Result<URL, PathError> {
    let canonicalRoot = canonicalizedFileURL(workspace.rootPath)

    let candidate: URL
    if path.hasPrefix("/") {
        candidate = URL(fileURLWithPath: path)
    } else {
        candidate = canonicalRoot.appendingPathComponent(path)
    }
    let canonicalCandidate = canonicalizedPathForContainment(candidate)

    guard isWithinDirectory(canonicalCandidate, root: canonicalRoot) else {
        return .failure(.escapesWorkspace)
    }

    return .success(canonicalCandidate)
}

func truncateUTF8(_ string: String, maxBytes: Int) -> String {
    guard string.utf8.count > maxBytes else { return string }
    var index = string.startIndex
    var byteCount = 0
    while index < string.endIndex {
        let nextIndex = string.index(after: index)
        let charBytes = string[index..<nextIndex].utf8.count
        if byteCount + charBytes > maxBytes { break }
        byteCount += charBytes
        index = nextIndex
    }
    return String(string[..<index])
}

// MARK: - ReadFileTool

struct ReadFileTool: ToolHandler {
    let toolName = ToolName.readFile
    let workspace: WorkspaceContext

    private static let maxFileSize = 1_048_576 // 1MB

    func execute(arguments: [String: Any]) -> String {
        guard let path = arguments["path"] as? String else {
            return "Error: Missing required parameter 'path'"
        }

        let resolved: URL
        switch resolvedPath(for: path, workspace: workspace) {
        case .success(let url): resolved = url
        case .failure: return "Error: Path escapes workspace root"
        }

        let fm = FileManager.default
        guard fm.fileExists(atPath: resolved.path) else {
            return "Error: File not found at '\(path)'"
        }

        do {
            let attributes = try fm.attributesOfItem(atPath: resolved.path)
            if let fileSize = attributes[.size] as? Int, fileSize > Self.maxFileSize {
                return "Error: File exceeds 1MB limit (\(fileSize) bytes)"
            }
        } catch {
            return "Error: Cannot read file attributes: \(error.localizedDescription)"
        }

        do {
            let content = try String(contentsOf: resolved, encoding: .utf8)
            return content
        } catch {
            return "Error: Failed to read file: \(error.localizedDescription)"
        }
    }
}

// MARK: - WriteFileTool

struct WriteFileTool: ToolHandler {
    let toolName = ToolName.writeFile
    let workspace: WorkspaceContext
    var safeMode: Bool = false

    func execute(arguments: [String: Any]) -> String {
        if safeMode {
            return "Error: write_file is disabled in safe mode"
        }

        guard let path = arguments["path"] as? String else {
            return "Error: Missing required parameter 'path'"
        }
        guard let content = arguments["content"] as? String else {
            return "Error: Missing required parameter 'content'"
        }

        let resolved: URL
        switch resolvedPath(for: path, workspace: workspace) {
        case .success(let url): resolved = url
        case .failure: return "Error: Path escapes workspace root"
        }

        do {
            let parentDir = resolved.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)

            guard let data = content.data(using: .utf8) else {
                return "Error: Failed to encode content as UTF-8"
            }
            try data.write(to: resolved)
            logInfo("ToolExecutor: Wrote \(data.count) bytes to \(path)")
            return "Successfully wrote \(data.count) bytes to \(path)"
        } catch {
            return "Error: Failed to write file: \(error.localizedDescription)"
        }
    }
}

// MARK: - EditFileTool

struct EditFileTool: ToolHandler {
    let toolName = ToolName.editFile
    let workspace: WorkspaceContext
    var safeMode: Bool = false

    func execute(arguments: [String: Any]) -> String {
        if safeMode {
            return "Error: edit_file is disabled in safe mode"
        }

        guard let path = arguments["path"] as? String else {
            return "Error: Missing required parameter 'path'"
        }
        guard let oldText = arguments["old_text"] as? String else {
            return "Error: Missing required parameter 'old_text'"
        }
        guard let newText = arguments["new_text"] as? String else {
            return "Error: Missing required parameter 'new_text'"
        }

        let resolved: URL
        switch resolvedPath(for: path, workspace: workspace) {
        case .success(let url): resolved = url
        case .failure: return "Error: Path escapes workspace root"
        }

        do {
            let content = try String(contentsOf: resolved, encoding: .utf8)

            let occurrences = content.components(separatedBy: oldText).count - 1
            if occurrences == 0 {
                return "Error: old_text not found in file"
            }
            if occurrences > 1 {
                return "Error: old_text found \(occurrences) times (ambiguous edit)"
            }

            let updated = content.replacingOccurrences(of: oldText, with: newText)
            guard let data = updated.data(using: .utf8) else {
                return "Error: Failed to encode updated content as UTF-8"
            }
            try data.write(to: resolved)
            logInfo("ToolExecutor: Edited \(path)")
            return "Successfully edited \(path)"
        } catch {
            return "Error: Failed to edit file: \(error.localizedDescription)"
        }
    }
}

// MARK: - BashTool

struct BashTool: ToolHandler {
    let toolName = ToolName.bash
    let workspace: WorkspaceContext
    var safeMode: Bool = false

    private static let bashTimeout: TimeInterval = 30
    private static let shellPath = "/bin/zsh"

    private static let safeModeAllowedPrefixes: [[String]] = [
        ["git"], ["grep"], ["rg"], ["find"], ["ls"], ["cat"], ["head"], ["tail"], ["wc"],
        ["swift", "test"], ["xcodebuild", "test"], ["npm", "test"], ["pytest"]
    ]

    func execute(arguments: [String: Any]) -> String {
        guard let command = arguments["command"] as? String else {
            return "Error: Missing required parameter 'command'"
        }

        if safeMode {
            let parsedCommand: [String]
            do {
                parsedCommand = try Self.parseCommandArguments(command)
            } catch {
                return "Error: Invalid command syntax in safe mode"
            }

            let allowed = Self.safeModeAllowedPrefixes.contains { prefix in
                parsedCommand.starts(with: prefix)
            }
            if !allowed {
                return "Error: Command not allowed in safe mode"
            }

            return runProcess(
                executableURL: URL(fileURLWithPath: "/usr/bin/env"),
                processArguments: parsedCommand
            )
        }

        return runProcess(
            executableURL: URL(fileURLWithPath: Self.shellPath),
            processArguments: ["-c", command]
        )
    }

    private func runProcess(executableURL: URL, processArguments: [String]) -> String {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = processArguments
        process.currentDirectoryURL = workspace.rootPath

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        var terminated = false
        let terminateLock = NSLock()

        do {
            try process.run()
        } catch {
            return "Error: Failed to launch process: \(error.localizedDescription)"
        }

        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global())
        timer.schedule(deadline: .now() + Self.bashTimeout)
        timer.setEventHandler {
            terminateLock.lock()
            terminated = true
            terminateLock.unlock()
            process.terminate()
        }
        timer.resume()

        process.waitUntilExit()
        timer.cancel()

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

        let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
        let stderr = String(data: stderrData, encoding: .utf8) ?? ""

        var output = ""
        if !stdout.isEmpty {
            output += stdout
        }
        if !stderr.isEmpty {
            if !output.isEmpty { output += "\n" }
            output += stderr
        }

        if output.utf8.count > ToolExecutor.maxOutputSize {
            output = truncateUTF8(output, maxBytes: ToolExecutor.maxOutputSize) + "\n[Output truncated at 100KB]"
        }

        terminateLock.lock()
        let wasTerminated = terminated
        terminateLock.unlock()

        let exitCode = process.terminationStatus
        if wasTerminated {
            output += "\n[Process timed out after \(Int(Self.bashTimeout))s and was terminated]"
        }
        output += "\n[Exit code: \(exitCode)]"

        return output
    }

    private enum SafeModeCommandParseError: Error {
        case emptyCommand
        case danglingEscape
        case unterminatedQuote
    }

    private static func parseCommandArguments(_ command: String) throws -> [String] {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw SafeModeCommandParseError.emptyCommand
        }

        var arguments: [String] = []
        var current = ""
        var inQuote: Character?
        var isEscaping = false
        var tokenStarted = false

        for character in trimmed {
            if isEscaping {
                current.append(character)
                isEscaping = false
                tokenStarted = true
                continue
            }

            if character == "\\" {
                if inQuote == "'" {
                    current.append(character)
                } else {
                    isEscaping = true
                }
                tokenStarted = true
                continue
            }

            if let quote = inQuote {
                if character == quote {
                    inQuote = nil
                } else {
                    current.append(character)
                }
                tokenStarted = true
                continue
            }

            if character == "'" || character == "\"" {
                inQuote = character
                tokenStarted = true
                continue
            }

            if character.isWhitespace {
                if tokenStarted {
                    arguments.append(current)
                    current = ""
                    tokenStarted = false
                }
                continue
            }

            current.append(character)
            tokenStarted = true
        }

        if isEscaping {
            throw SafeModeCommandParseError.danglingEscape
        }
        if inQuote != nil {
            throw SafeModeCommandParseError.unterminatedQuote
        }
        if tokenStarted {
            arguments.append(current)
        }
        guard !arguments.isEmpty else {
            throw SafeModeCommandParseError.emptyCommand
        }

        return arguments
    }
}

// MARK: - GrepSearchTool

struct GrepSearchTool: ToolHandler {
    let toolName = ToolName.grepSearch
    let workspace: WorkspaceContext

    private static let grepPath = "/usr/bin/grep"

    func execute(arguments: [String: Any]) -> String {
        guard let pattern = arguments["pattern"] as? String else {
            return "Error: Missing required parameter 'pattern'"
        }

        let searchPath: String
        if let path = arguments["path"] as? String {
            switch resolvedPath(for: path, workspace: workspace) {
            case .success(let url): searchPath = url.path
            case .failure: return "Error: Path escapes workspace root"
            }
        } else {
            searchPath = workspace.rootPath.path
        }

        var grepArgs = ["-rn", pattern, searchPath]
        if let include = arguments["include"] as? String {
            grepArgs.insert("--include=\(include)", at: 0)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: Self.grepPath)
        process.arguments = grepArgs
        process.currentDirectoryURL = workspace.rootPath

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            return "Error: Failed to launch grep: \(error.localizedDescription)"
        }

        process.waitUntilExit()

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        let exitCode = process.terminationStatus

        if exitCode == 1 {
            return "No matches found"
        }

        let stderr = String(data: stderrData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if exitCode != 0 {
            if !stderr.isEmpty {
                return "Error: grep failed with exit code \(exitCode): \(stderr)"
            }
            return "Error: grep failed with exit code \(exitCode)"
        }

        var output = String(data: stdoutData, encoding: .utf8) ?? ""
        if output.isEmpty {
            return "No matches found"
        }

        if output.utf8.count > ToolExecutor.maxOutputSize {
            output = truncateUTF8(output, maxBytes: ToolExecutor.maxOutputSize) + "\n[Output truncated at 100KB]"
        }

        return output
    }
}

// MARK: - FindFilesTool

struct FindFilesTool: ToolHandler {
    let toolName = ToolName.findFiles
    let workspace: WorkspaceContext

    private static let maxFindResults = 200

    private static let skippedDirectories: Set<String> = [
        ".git", ".build", "node_modules"
    ]

    func execute(arguments: [String: Any]) -> String {
        guard let pattern = arguments["pattern"] as? String else {
            return "Error: Missing required parameter 'pattern'"
        }

        let searchRoot: URL
        if let path = arguments["path"] as? String {
            switch resolvedPath(for: path, workspace: workspace) {
            case .success(let url): searchRoot = url
            case .failure: return "Error: Path escapes workspace root"
            }
        } else {
            searchRoot = workspace.rootPath
        }

        let predicate = NSPredicate(format: "SELF LIKE %@", pattern)
        let fm = FileManager.default

        guard let enumerator = fm.enumerator(
            at: searchRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return "Error: Cannot enumerate directory"
        }

        var results: [String] = []
        let canonicalWorkspaceRoot = canonicalizedFileURL(workspace.rootPath)
        let canonicalSearchRoot = canonicalizedFileURL(searchRoot)

        while let url = enumerator.nextObject() as? URL {
            let filename = url.lastPathComponent

            if Self.skippedDirectories.contains(filename) {
                enumerator.skipDescendants()
                continue
            }

            let canonicalURL = canonicalizedFileURL(url)
            guard isWithinDirectory(canonicalURL, root: canonicalWorkspaceRoot),
                  isWithinDirectory(canonicalURL, root: canonicalSearchRoot) else {
                continue
            }

            let workspaceRelative = pathRelativeToRoot(canonicalURL, root: canonicalWorkspaceRoot)
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let searchRelative = pathRelativeToRoot(canonicalURL, root: canonicalSearchRoot)
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let workspaceRelativeWithLeadingSlash = "/" + workspaceRelative
            let searchRelativeWithLeadingSlash = "/" + searchRelative

            // Support both basename globs (*.swift) and path globs (src/*.ts, **/*).
            let matchesPattern =
                predicate.evaluate(with: filename)
                || predicate.evaluate(with: searchRelative)
                || predicate.evaluate(with: workspaceRelative)
                || predicate.evaluate(with: searchRelativeWithLeadingSlash)
                || predicate.evaluate(with: workspaceRelativeWithLeadingSlash)

            if matchesPattern {
                results.append(workspaceRelative)

                if results.count >= Self.maxFindResults {
                    results.append("[Results truncated at \(Self.maxFindResults) entries]")
                    break
                }
            }
        }

        if results.isEmpty {
            return "No files found matching '\(pattern)'"
        }

        return results.joined(separator: "\n")
    }
}
