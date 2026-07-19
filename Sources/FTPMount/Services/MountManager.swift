import AppKit
import Foundation

enum MountManagerError: LocalizedError {
    case missingRclone
    case unsupportedRclone(String)
    case missingMacFUSE
    case inactiveMacFUSE
    case invalidBookmark
    case missingKnownHosts
    case authenticationFailed(String)
    case mountDidNotAppear(String)
    case rcloneFailed(String)
    case configWriteFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingRclone:
            return "rclone is not installed. Open Setup for installation instructions."
        case .unsupportedRclone(let details):
            return details
        case .missingMacFUSE:
            return "macFUSE is not installed. Open Setup for installation instructions."
        case .inactiveMacFUSE:
            return "macFUSE is installed but not active. Open Setup and choose Activate macFUSE."
        case .invalidBookmark:
            return "Enter a name, server, username, and valid connection details before mounting. WebDAV servers must use an http:// or https:// URL."
        case .missingKnownHosts:
            return "SFTP host-key verification is enabled, but ~/.ssh/known_hosts does not exist. Connect once with the macOS ssh command to verify and save the server key, or disable verification for this bookmark."
        case .authenticationFailed(let details):
            let summary = "Sign-in failed. Check the server address, port, username, and password."
            return details.isEmpty ? summary : "\(summary)\n\n\(details)"
        case .mountDidNotAppear(let details):
            let summary = "rclone connected, but macFUSE did not create the Finder mount. Make sure macFUSE is enabled, then try again."
            return details.isEmpty ? summary : "\(summary)\n\n\(details)"
        case .rcloneFailed(let details):
            return details.isEmpty ? "rclone stopped before the drive was mounted." : details
        case .configWriteFailed(let details):
            return "Could not prepare the temporary connection configuration: \(details)"
        }
    }
}

private final class MountSession {
    let process: Process
    let mountURL: URL
    let configURL: URL
    let outputPipe: Pipe
    var log = ""

    init(process: Process, mountURL: URL, configURL: URL, outputPipe: Pipe) {
        self.process = process
        self.mountURL = mountURL
        self.configURL = configURL
        self.outputPipe = outputPipe
    }
}

@MainActor
final class MountManager: ObservableObject {
    @Published private(set) var states: [UUID: MountState] = [:]
    @Published private(set) var dependencyStatus = DependencyChecker.inspect()

    private var sessions: [UUID: MountSession] = [:]
    private var recentFailures: [UUID: String] = [:]
    private let fileManager = FileManager.default

    func state(for id: UUID) -> MountState {
        states[id] ?? .unmounted
    }

    func refreshDependencies() {
        dependencyStatus = DependencyChecker.inspect()
    }

    func mount(_ bookmark: Bookmark, password: String) async {
        guard sessions[bookmark.id] == nil else { return }
        recentFailures.removeValue(forKey: bookmark.id)
        guard bookmark.isValid else {
            states[bookmark.id] = .failed(MountManagerError.invalidBookmark.localizedDescription)
            return
        }

        refreshDependencies()
        guard let rcloneURL = dependencyStatus.rcloneURL else {
            states[bookmark.id] = .failed(MountManagerError.missingRclone.localizedDescription)
            return
        }
        if let reason = dependencyStatus.rcloneMountUnsupportedReason {
            states[bookmark.id] = .failed(MountManagerError.unsupportedRclone(reason).localizedDescription)
            return
        }
        guard dependencyStatus.hasMacFUSE else {
            states[bookmark.id] = .failed(MountManagerError.missingMacFUSE.localizedDescription)
            return
        }
        guard dependencyStatus.hasActiveMacFUSE else {
            states[bookmark.id] = .failed(MountManagerError.inactiveMacFUSE.localizedDescription)
            return
        }
        if bookmark.transferProtocol == .sftp && bookmark.verifySFTPHostKey {
            let knownHosts = fileManager.homeDirectoryForCurrentUser
                .appendingPathComponent(".ssh/known_hosts")
            guard fileManager.fileExists(atPath: knownHosts.path) else {
                states[bookmark.id] = .failed(MountManagerError.missingKnownHosts.localizedDescription)
                return
            }
        }

        states[bookmark.id] = .mounting
        do {
            let obscuredPassword = try await obscure(password, using: rcloneURL)
            let mountURL = try prepareMountPoint(for: bookmark)
            let configURL = try writeTemporaryConfig(
                for: bookmark,
                obscuredPassword: obscuredPassword
            )
            try await verifyConnection(
                rcloneURL: rcloneURL,
                remote: remoteName(for: bookmark),
                configURL: configURL
            )
            startProcess(
                for: bookmark,
                rcloneURL: rcloneURL,
                mountURL: mountURL,
                configURL: configURL
            )
            try await waitForMount(bookmarkID: bookmark.id, at: mountURL)
            states[bookmark.id] = .mounted(mountURL)
            NSWorkspace.shared.open(mountURL)
        } catch {
            if case .failed = state(for: bookmark.id) {
                return
            }
            if let session = sessions[bookmark.id], !isMountActive(at: session.mountURL) {
                if session.process.isRunning { session.process.terminate() }
                cleanup(bookmarkID: bookmark.id, session: session)
            }
            states[bookmark.id] = .failed(error.localizedDescription)
        }
    }

    func unmount(_ bookmarkID: UUID) async {
        guard let session = sessions[bookmarkID] else {
            states[bookmarkID] = .unmounted
            return
        }
        states[bookmarkID] = .unmounting

        let unmount = Process()
        unmount.executableURL = URL(fileURLWithPath: "/sbin/umount")
        unmount.arguments = [session.mountURL.path]
        do {
            try unmount.run()
            unmount.waitUntilExit()
        } catch {
            // Terminating rclone below is the fallback if umount cannot be launched.
        }
        if session.process.isRunning { session.process.terminate() }
        cleanup(bookmarkID: bookmarkID, session: session)
        states[bookmarkID] = .unmounted
    }

    func reveal(_ bookmarkID: UUID) {
        guard case .mounted(let url) = state(for: bookmarkID) else { return }
        NSWorkspace.shared.open(url)
    }

    func unmountAll() {
        for (id, session) in Array(sessions) {
            let unmount = Process()
            unmount.executableURL = URL(fileURLWithPath: "/sbin/umount")
            unmount.arguments = [session.mountURL.path]
            try? unmount.run()
            unmount.waitUntilExit()
            if session.process.isRunning { session.process.terminate() }
            cleanup(bookmarkID: id, session: session)
            states[id] = .unmounted
        }
    }

    private func obscure(_ password: String, using rcloneURL: URL) async throws -> String {
        if password.isEmpty { return "" }
        return try await Task.detached {
            let process = Process()
            let input = Pipe()
            let output = Pipe()
            let errors = Pipe()
            process.executableURL = rcloneURL
            process.arguments = ["obscure", "-"]
            process.standardInput = input
            process.standardOutput = output
            process.standardError = errors
            try process.run()
            input.fileHandleForWriting.write(Data((password + "\n").utf8))
            try input.fileHandleForWriting.close()
            process.waitUntilExit()
            let result = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if process.terminationStatus != 0 {
                let details = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                throw MountManagerError.rcloneFailed(details)
            }
            return result
        }.value
    }

    private func prepareMountPoint(for bookmark: Bookmark) throws -> URL {
        let base = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("FTP Mounts", isDirectory: true)
        try fileManager.createDirectory(at: base, withIntermediateDirectories: true)
        let name = safeFileName(bookmark.name)
        let url = base.appendingPathComponent(name, isDirectory: true)
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func verifyConnection(
        rcloneURL: URL,
        remote: String,
        configURL: URL
    ) async throws {
        let result = try await runRclone(
            executable: rcloneURL,
            arguments: [
                "lsd", remote,
                "--config", configURL.path,
                "--log-level", "ERROR",
                "--retries", "1",
                "--low-level-retries", "1"
            ]
        )
        guard result.status == 0 else {
            throw classifiedConnectionError(result.output)
        }
    }

    private func runRclone(executable: URL, arguments: [String]) async throws -> (status: Int32, output: String) {
        try await Task.detached {
            let process = Process()
            let output = Pipe()
            process.executableURL = executable
            process.arguments = arguments
            process.standardOutput = output
            process.standardError = output
            try process.run()
            process.waitUntilExit()
            let text = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return (process.terminationStatus, text)
        }.value
    }

    private func classifiedConnectionError(_ details: String) -> MountManagerError {
        let lowercased = details.lowercased()
        let authenticationTerms = ["authentication", "authenticate", "login", "password", "permission denied", "access denied"]
        if authenticationTerms.contains(where: lowercased.contains) {
            return .authenticationFailed(details)
        }
        return .rcloneFailed(details)
    }

    private func waitForMount(bookmarkID: UUID, at mountURL: URL) async throws {
        for _ in 0..<20 {
            guard let session = sessions[bookmarkID] else {
                let details = recentFailures[bookmarkID] ?? "rclone exited before macFUSE mounted the connection."
                throw MountManagerError.rcloneFailed(details)
            }
            if isMountActive(at: mountURL) { return }
            guard session.process.isRunning else {
                throw MountManagerError.rcloneFailed(lastLogLines(from: session))
            }
            try await Task.sleep(for: .milliseconds(250))
        }
        let details = sessions[bookmarkID].map(lastLogLines(from:)) ?? ""
        throw MountManagerError.mountDidNotAppear(details)
    }

    private func isMountActive(at mountURL: URL) -> Bool {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/sbin/mount")
        process.standardOutput = output
        process.standardError = output
        do {
            try process.run()
            process.waitUntilExit()
            let text = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            return text.split(separator: "\n").contains { line in
                line.contains(mountURL.path) && line.lowercased().contains("fuse")
            }
        } catch {
            return false
        }
    }

    private func lastLogLines(from session: MountSession) -> String {
        session.log.split(separator: "\n").suffix(3).joined(separator: "\n")
    }

    private func remoteName(for bookmark: Bookmark) -> String {
        let root = bookmark.normalizedRoot
        return root.isEmpty ? "ftpmount:" : "ftpmount:\(root)"
    }

    private func writeTemporaryConfig(
        for bookmark: Bookmark,
        obscuredPassword: String
    ) throws -> URL {
        let directory = fileManager.temporaryDirectory
            .appendingPathComponent("FTP-Mount-\(bookmark.id.uuidString)", isDirectory: true)
        do {
            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            let url = directory.appendingPathComponent("rclone.conf")
            var lines = [
                "[ftpmount]",
                "type = \(bookmark.transferProtocol.rcloneType)",
                "user = \(safeConfigValue(bookmark.username))"
            ]
            if bookmark.transferProtocol == .webdav {
                lines.append("url = \(safeConfigValue(bookmark.server))")
                lines.append("vendor = \(bookmark.webDAVVendor.rcloneValue)")
            } else {
                lines.append("host = \(safeConfigValue(bookmark.server))")
                lines.append("port = \(bookmark.effectivePort)")
            }
            if !obscuredPassword.isEmpty { lines.append("pass = \(obscuredPassword)") }
            if bookmark.transferProtocol == .sftp && bookmark.verifySFTPHostKey {
                let knownHosts = fileManager.homeDirectoryForCurrentUser
                    .appendingPathComponent(".ssh/known_hosts")
                lines.append("known_hosts_file = \(safeConfigValue(knownHosts.path))")
            }
            let data = Data((lines.joined(separator: "\n") + "\n").utf8)
            try data.write(to: url, options: .atomic)
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            return url
        } catch {
            throw MountManagerError.configWriteFailed(error.localizedDescription)
        }
    }

    private func startProcess(
        for bookmark: Bookmark,
        rcloneURL: URL,
        mountURL: URL,
        configURL: URL
    ) {
        let process = Process()
        let output = Pipe()
        let cacheDirectory = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appendingPathComponent("FTP Mount/VFS/\(bookmark.id.uuidString)", isDirectory: true)
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)

        let remote = remoteName(for: bookmark)
        process.executableURL = rcloneURL
        process.arguments = [
            "mount", remote, mountURL.path,
            "--config", configURL.path,
            "--volname", bookmark.name,
            "--vfs-cache-mode", "writes",
            "--cache-dir", cacheDirectory.path,
            "--dir-cache-time", "30s",
            "--poll-interval", "0",
            "--log-level", "INFO"
        ]
        process.standardOutput = output
        process.standardError = output

        let session = MountSession(
            process: process,
            mountURL: mountURL,
            configURL: configURL,
            outputPipe: output
        )
        output.fileHandleForReading.readabilityHandler = { [weak session] handle in
            let text = String(decoding: handle.availableData, as: UTF8.self)
            guard !text.isEmpty else { return }
            session?.log = String(((session?.log ?? "") + text).suffix(8_000))
        }
        process.terminationHandler = { [weak self, weak session] process in
            guard let session else { return }
            Task { @MainActor in
                guard let self, self.sessions[bookmark.id] === session else { return }
                let details = self.lastLogLines(from: session)
                self.cleanup(bookmarkID: bookmark.id, session: session)
                if case .unmounting = self.states[bookmark.id] {
                    self.states[bookmark.id] = .unmounted
                } else {
                    let message = MountManagerError.rcloneFailed(details).localizedDescription
                    self.recentFailures[bookmark.id] = message
                    self.states[bookmark.id] = .failed(message)
                }
            }
        }

        sessions[bookmark.id] = session
        do {
            try process.run()
        } catch {
            cleanup(bookmarkID: bookmark.id, session: session)
            states[bookmark.id] = .failed(error.localizedDescription)
        }
    }

    private func cleanup(bookmarkID: UUID, session: MountSession) {
        session.outputPipe.fileHandleForReading.readabilityHandler = nil
        try? fileManager.removeItem(at: session.configURL.deletingLastPathComponent())
        sessions.removeValue(forKey: bookmarkID)
    }

    private func safeFileName(_ input: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/:")
        let parts = input.components(separatedBy: forbidden)
        let result = parts.joined(separator: "-").trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? "FTP Mount" : result
    }

    private func safeConfigValue(_ input: String) -> String {
        input.replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: "\n", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
