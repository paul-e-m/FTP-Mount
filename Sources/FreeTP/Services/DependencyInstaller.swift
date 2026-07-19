import AppKit
import Foundation

enum DependencyInstallerError: LocalizedError {
    case unsupportedArchitecture
    case downloadFailed
    case archiveDidNotContainRclone
    case processFailed(String)
    case macFUSENotInstalled
    case activationFailed(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedArchitecture:
            return "This Mac’s processor is not supported by the rclone installer. Download rclone from rclone.org instead."
        case .downloadFailed:
            return "FTP Mount could not download rclone from rclone.org. Check your internet connection and try again."
        case .archiveDidNotContainRclone:
            return "The downloaded rclone archive did not contain the expected executable."
        case .processFailed(let details):
            return details
        case .macFUSENotInstalled:
            return "Install macFUSE first, then return to FTP Mount to activate it."
        case .activationFailed(let details):
            return details.isEmpty ? "macFUSE could not be activated. Follow any macOS security prompt, restart if asked, then check again." : details
        }
    }
}

enum DependencyInstaller {
    static let rcloneDestination = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/FTP Mount/bin/rclone")

    static func installRclone() async throws {
        let archiveName: String
        #if arch(arm64)
        archiveName = "rclone-current-osx-arm64.zip"
        #elseif arch(x86_64)
        archiveName = "rclone-current-osx-amd64.zip"
        #else
        throw DependencyInstallerError.unsupportedArchitecture
        #endif

        guard let source = URL(string: "https://downloads.rclone.org/\(archiveName)") else {
            throw DependencyInstallerError.downloadFailed
        }
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FreeTP-rclone-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        do {
            try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
            let (downloadURL, response) = try await URLSession.shared.download(from: source)
            guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else {
                throw DependencyInstallerError.downloadFailed
            }

            let archiveURL = temporaryDirectory.appendingPathComponent("rclone.zip")
            try FileManager.default.moveItem(at: downloadURL, to: archiveURL)
            let unpackedURL = temporaryDirectory.appendingPathComponent("unpacked", isDirectory: true)
            try FileManager.default.createDirectory(at: unpackedURL, withIntermediateDirectories: true)
            try runTool("/usr/bin/ditto", arguments: ["-x", "-k", archiveURL.path, unpackedURL.path])

            let entries = try FileManager.default.contentsOfDirectory(
                at: unpackedURL,
                includingPropertiesForKeys: [.isDirectoryKey]
            )
            guard let folder = entries.first(where: { $0.lastPathComponent.hasPrefix("rclone-") }) else {
                throw DependencyInstallerError.archiveDidNotContainRclone
            }
            let binary = folder.appendingPathComponent("rclone")
            guard FileManager.default.isExecutableFile(atPath: binary.path) else {
                throw DependencyInstallerError.archiveDidNotContainRclone
            }

            let destinationDirectory = rcloneDestination.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: rcloneDestination.path) {
                try FileManager.default.removeItem(at: rcloneDestination)
            }
            try FileManager.default.copyItem(at: binary, to: rcloneDestination)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: rcloneDestination.path)
        } catch let error as DependencyInstallerError {
            throw error
        } catch {
            throw DependencyInstallerError.downloadFailed
        }
    }

    static func activateMacFUSE() throws {
        let tool = "/Library/Filesystems/macfuse.fs/Contents/Resources/macfuse.app/Contents/MacOS/macfuse"
        guard FileManager.default.isExecutableFile(atPath: tool) else {
            throw DependencyInstallerError.macFUSENotInstalled
        }
        let command = "'\(tool)' install --force; '\(tool)' kernel-extension load"
        let escapedCommand = command.replacingOccurrences(of: "\"", with: "\\\"")
        let source = "do shell script \"\(escapedCommand)\" with administrator privileges"
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error {
            throw DependencyInstallerError.activationFailed(error[NSAppleScript.errorMessage] as? String ?? "")
        }
    }

    private static func runTool(_ executable: String, arguments: [String]) throws {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = output
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let details = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            throw DependencyInstallerError.processFailed(details)
        }
    }
}
