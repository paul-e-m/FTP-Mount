import AppKit
import SwiftUI

struct SetupView: View {
    @EnvironmentObject private var mountManager: MountManager
    @Environment(\.dismiss) private var dismiss
    @State private var isInstallingRclone = false
    @State private var isActivatingMacFUSE = false
    @State private var message: String?

    private var status: DependencyStatus { mountManager.dependencyStatus }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Get FTP Mount Ready")
                .font(.title2.bold())
            Text("FTP Mount checks each requirement before it connects. Complete the items below once; your bookmarks and passwords stay on this Mac.")
                .foregroundStyle(.secondary)

            requirementCard(
                title: "1. rclone",
                detail: rcloneDetail,
                isReady: status.hasCompatibleRclone,
                actionTitle: rcloneActionTitle,
                action: installRclone,
                isWorking: isInstallingRclone
            )

            requirementCard(
                title: "2. macFUSE",
                detail: macFUSEDetail,
                isReady: status.hasActiveMacFUSE,
                actionTitle: macFUSEActionTitle,
                action: macFUSEAction,
                isWorking: isActivatingMacFUSE
            )

            GroupBox("What happens next") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("• Save a connection once, then use Connect whenever you need it.")
                    Text("• Connect checks the server login before creating a Finder mount.")
                    Text("• Choose SFTP where your hosting provider supports SSH. Plain FTP is not encrypted.")
                    Button("Open FTP Mount Help") {
                        NotificationCenter.default.post(name: .showFreeTPHelp, object: nil)
                    }
                    .padding(.top, 2)
                }
                .font(.callout)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack {
                Button("Check Again") { mountManager.refreshDependencies() }
                Spacer()
                if status.isReady {
                    Label("Ready to connect", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .onAppear { mountManager.refreshDependencies() }
        .alert("FTP Mount Setup", isPresented: Binding(
            get: { message != nil },
            set: { if !$0 { message = nil } }
        )) {
            Button("OK", role: .cancel) { message = nil }
        } message: {
            Text(message ?? "")
        }
    }

    private var rcloneDetail: String {
        if let reason = status.rcloneMountUnsupportedReason { return reason }
        if let url = status.rcloneURL { return "Installed at \(url.path)" }
        return "Required to connect to FTP, SFTP, and WebDAV servers."
    }

    private var rcloneActionTitle: String? {
        status.hasCompatibleRclone ? nil : "Install rclone"
    }

    private var macFUSEDetail: String {
        if status.hasActiveMacFUSE { return "Installed and active." }
        if status.hasMacFUSE { return "Installed, but macOS has not activated it yet." }
        return "Required to present a remote server as a Finder drive."
    }

    private var macFUSEActionTitle: String? {
        if status.hasActiveMacFUSE { return nil }
        return status.hasMacFUSE ? "Activate macFUSE" : "Download macFUSE"
    }

    private func requirementCard(
        title: String,
        detail: String,
        isReady: Bool,
        actionTitle: String?,
        action: @escaping () -> Void,
        isWorking: Bool
    ) -> some View {
        GroupBox {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: isReady ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .font(.title2)
                    .foregroundStyle(isReady ? .green : .orange)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.headline)
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                Spacer(minLength: 12)
                if isWorking {
                    ProgressView()
                        .controlSize(.small)
                } else if let actionTitle {
                    Button(actionTitle, action: action)
                        .buttonStyle(.borderedProminent)
                }
            }
            .padding(4)
        }
    }

    private func installRclone() {
        Task {
            isInstallingRclone = true
            defer { isInstallingRclone = false }
            do {
                try await DependencyInstaller.installRclone()
                mountManager.refreshDependencies()
                message = "rclone was installed. FTP Mount can now use it for Finder mounts."
            } catch {
                message = error.localizedDescription
            }
        }
    }

    private func macFUSEAction() {
        guard status.hasMacFUSE else {
            NSWorkspace.shared.open(URL(string: "https://macfuse.github.io/")!)
            message = "Download and run the macFUSE installer. Return to FTP Mount afterward and click Check Again."
            return
        }
        isActivatingMacFUSE = true
        defer { isActivatingMacFUSE = false }
        do {
            try DependencyInstaller.activateMacFUSE()
            mountManager.refreshDependencies()
            message = status.hasActiveMacFUSE
                ? "macFUSE is active. FTP Mount is ready to connect."
                : "macFUSE asked macOS for activation. Approve any system prompt and restart if macOS requests it, then click Check Again."
        } catch {
            message = error.localizedDescription
        }
    }
}
