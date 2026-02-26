import Foundation

struct WorkspaceContext {
    let rootPath: URL
}

class ToolExecutor {
    let workspace: WorkspaceContext
    var safeMode: Bool = false

    private static let maxFileSize = 1_048_576 // 1MB
    private static let maxOutputSize = 102_400 // 100KB
    private static let maxFindResults = 200
    private static let bashTimeout: TimeInterval = 30
    private static let shellPath = "/bin/zsh"
    private static let grepPath = "/usr/bin/grep"

    private static let safeModeAllowedPrefixes = [
        "git", "grep", "rg", "find", "ls", "cat", "head", "tail", "wc",
        "swift test", "xcodebuild test", "npm test", "pytest"
    ]

    private static let skippedDirectories: Set<String> = [
        ".git", ".build", "node_modules"
    ]

    init(workspace: WorkspaceContext) {
        self.workspace = workspace
    }

    /// Truncate a string to at most `maxBytes` of UTF-8 without splitting multi-byte characters.
    private func truncateUTF8(_ string: String, maxBytes: Int) -> String {
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

    func execute(toolName: String, arguments: String) -> String {
        guard let data = arguments.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return "Error: Invalid JSON arguments"
        }

        switch toolName {
        case "read_file":
            return executeReadFile(json)
        case "write_file":
            return executeWriteFile(json)
        case "edit_file":
            return executeEditFile(json)
        case "bash":
            return executeBash(json)
        case "grep_search":
            return executeGrepSearch(json)
        case "find_files":
            return executeFindFiles(json)
        default:
            return "Error: Unknown tool '\(toolName)'"
        }
    }

    // MARK: - Path Validation

    private enum PathError: Error {
        case escapesWorkspace
    }

    private func resolvedPath(for relativePath: String) -> Result<URL, PathError> {
        let resolved: URL
        if relativePath.hasPrefix("/") {
            resolved = URL(fileURLWithPath: relativePath).standardizedFileURL
        } else {
            resolved = workspace.rootPath.appendingPathComponent(relativePath).standardizedFileURL
        }

        let resolvedString = resolved.path
        let rootString = workspace.rootPath.standardizedFileURL.path

        guard resolvedString.hasPrefix(rootString) else {
            return .failure(.escapesWorkspace)
        }

        return .success(resolved)
    }

    // MARK: - read_file

    private func executeReadFile(_ args: [String: Any]) -> String {
        guard let path = args["path"] as? String else {
            return "Error: Missing required parameter 'path'"
        }

        let resolved: URL
        switch resolvedPath(for: path) {
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

    // MARK: - write_file

    private func executeWriteFile(_ args: [String: Any]) -> String {
        if safeMode {
            return "Error: write_file is disabled in safe mode"
        }

        guard let path = args["path"] as? String else {
            return "Error: Missing required parameter 'path'"
        }
        guard let content = args["content"] as? String else {
            return "Error: Missing required parameter 'content'"
        }

        let resolved: URL
        switch resolvedPath(for: path) {
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

    // MARK: - edit_file

    private func executeEditFile(_ args: [String: Any]) -> String {
        if safeMode {
            return "Error: edit_file is disabled in safe mode"
        }

        guard let path = args["path"] as? String else {
            return "Error: Missing required parameter 'path'"
        }
        guard let oldText = args["old_text"] as? String else {
            return "Error: Missing required parameter 'old_text'"
        }
        guard let newText = args["new_text"] as? String else {
            return "Error: Missing required parameter 'new_text'"
        }

        let resolved: URL
        switch resolvedPath(for: path) {
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

    // MARK: - bash

    private func executeBash(_ args: [String: Any]) -> String {
        guard let command = args["command"] as? String else {
            return "Error: Missing required parameter 'command'"
        }

        if safeMode {
            let trimmed = command.trimmingCharacters(in: .whitespaces)
            let allowed = Self.safeModeAllowedPrefixes.contains { prefix in
                trimmed == prefix || trimmed.hasPrefix(prefix + " ")
            }
            if !allowed {
                return "Error: Command not allowed in safe mode"
            }
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: Self.shellPath)
        process.arguments = ["-c", command]
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

        if output.utf8.count > Self.maxOutputSize {
            output = truncateUTF8(output, maxBytes: Self.maxOutputSize) + "\n[Output truncated at 100KB]"
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

    // MARK: - grep_search

    private func executeGrepSearch(_ args: [String: Any]) -> String {
        guard let pattern = args["pattern"] as? String else {
            return "Error: Missing required parameter 'pattern'"
        }

        let searchPath: String
        if let path = args["path"] as? String {
            switch resolvedPath(for: path) {
            case .success(let url): searchPath = url.path
            case .failure: return "Error: Path escapes workspace root"
            }
        } else {
            searchPath = workspace.rootPath.path
        }

        var grepArgs = ["-rn", pattern, searchPath]
        if let include = args["include"] as? String {
            grepArgs.insert("--include=\(include)", at: 0)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: Self.grepPath)
        process.arguments = grepArgs
        process.currentDirectoryURL = workspace.rootPath

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return "Error: Failed to launch grep: \(error.localizedDescription)"
        }

        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        var output = String(data: data, encoding: .utf8) ?? ""

        if output.isEmpty {
            return "No matches found"
        }

        if output.utf8.count > Self.maxOutputSize {
            output = truncateUTF8(output, maxBytes: Self.maxOutputSize) + "\n[Output truncated at 100KB]"
        }

        return output
    }

    // MARK: - find_files

    private func executeFindFiles(_ args: [String: Any]) -> String {
        guard let pattern = args["pattern"] as? String else {
            return "Error: Missing required parameter 'pattern'"
        }

        let searchRoot: URL
        if let path = args["path"] as? String {
            switch resolvedPath(for: path) {
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
        let rootPath = workspace.rootPath.standardizedFileURL.path

        while let url = enumerator.nextObject() as? URL {
            let filename = url.lastPathComponent

            if Self.skippedDirectories.contains(filename) {
                enumerator.skipDescendants()
                continue
            }

            if predicate.evaluate(with: filename) {
                let fullPath = url.standardizedFileURL.path
                if fullPath.hasPrefix(rootPath) {
                    let relative = String(fullPath.dropFirst(rootPath.count))
                        .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                    results.append(relative)
                }

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
