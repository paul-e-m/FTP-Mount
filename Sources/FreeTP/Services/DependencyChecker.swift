import Foundation

struct DependencyStatus {
    let rcloneURL: URL?
    let rcloneMountUnsupportedReason: String?
    let hasMacFUSE: Bool
    let hasActiveMacFUSE: Bool

    var hasCompatibleRclone: Bool { rcloneURL != nil && rcloneMountUnsupportedReason == nil }
    var isReady: Bool { hasCompatibleRclone && hasActiveMacFUSE }
}

enum DependencyChecker {
    static let rcloneCandidates = [
        "/opt/homebrew/bin/rclone",
        "/usr/local/bin/rclone",
        "/opt/local/bin/rclone",
        "/usr/bin/rclone"
    ]

    static func inspect() -> DependencyStatus {
        let fileManager = FileManager.default
        let appSupport = fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        let ftpMountRclone = appSupport.appendingPathComponent("FTP Mount/bin/rclone").path
        let rclone = ([ftpMountRclone] + rcloneCandidates)
            .first(where: { fileManager.isExecutableFile(atPath: $0) })
            .map(URL.init(fileURLWithPath:))
        let resolvedRclonePath = rclone?.resolvingSymlinksInPath().path ?? ""
        let isHomebrewRclone = resolvedRclonePath.contains("/Cellar/rclone/")
        let unsupportedReason = isHomebrewRclone
            ? "The Homebrew rclone build cannot mount FUSE filesystems on macOS. Install the official rclone binary instead."
            : nil
        let macFUSEPaths = [
            "/Library/Filesystems/macfuse.fs",
            "/Library/Filesystems/osxfuse.fs"
        ]
        let hasMacFUSE = macFUSEPaths.contains { fileManager.fileExists(atPath: $0) }
        let hasActiveMacFUSE = hasMacFUSE && isMacFUSEActive()
        return DependencyStatus(
            rcloneURL: rclone,
            rcloneMountUnsupportedReason: unsupportedReason,
            hasMacFUSE: hasMacFUSE,
            hasActiveMacFUSE: hasActiveMacFUSE
        )
    }

    private static func isMacFUSEActive() -> Bool {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/kmutil")
        process.arguments = ["showloaded"]
        process.standardOutput = output
        process.standardError = output
        do {
            try process.run()
            process.waitUntilExit()
            let text = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            return text.contains("io.macfuse.filesystems.macfuse")
        } catch {
            return false
        }
    }
}
