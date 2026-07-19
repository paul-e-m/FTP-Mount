import AppKit
import SwiftUI

struct HelpView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("FTP Mount Help").font(.title2.bold())
                    Text("Mount FTP, SFTP, and WebDAV servers as Finder folders.").foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding(24)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    helpSection("Before your first connection") {
                        Text("Open FTP Mount → Settings (⌘,) and complete rclone and macFUSE. FTP Mount can download rclone. macFUSE is installed separately because macOS requires your approval before a filesystem component can run.")
                        Text("If macOS asks, approve macFUSE in System Settings → Privacy & Security, then restart if requested.")
                    }
                    helpSection("Create, save, and connect") {
                        Text("Click + to create a bookmark. Enter a name, protocol, server, username, optional port, password, and optional root directory.")
                        Text("Choose Save Bookmark once. After that, Connect uses the saved server settings and its password from your macOS Keychain. If you edit a bookmark, save it before connecting.")
                    }
                    helpSection("Finding the mounted server") {
                        Text("A successful connection opens in Finder at ~/FTP Mounts/<bookmark name>. It behaves like a Finder folder and may not appear under /Volumes or as a sidebar drive.")
                        Text("Use Show in Finder to return to it. Use Unmount before quitting FTP Mount or disconnecting from a network.")
                    }
                    helpSection("FTP, SFTP, and WebDAV") {
                        Text("SFTP uses SSH, normally port 22, and encrypts both passwords and file transfers. For SFTP, FTP Mount checks the host key against ~/.ssh/known_hosts by default.")
                        Text("WebDAV uses the complete server URL, normally https://… . Select the server type when connecting to Nextcloud, ownCloud, Fastmail, or SharePoint.")
                        Text("Plain FTP normally uses port 21 and does not encrypt the username, password, or transferred files. Use it only when SFTP or FTPS is unavailable and you accept that risk.")
                    }
                    helpSection("Common connection problems") {
                        Text("Sign-in failed: confirm the protocol, server, port, username, and password. FTP credentials are not always valid for SFTP; the server must provide SSH/SFTP access.")
                        Text("macFUSE did not create a mount: open Settings, activate macFUSE, approve any macOS security request, and restart if asked.")
                        Text("No remote files appear: check the Root directory field. Leave it blank to begin at the account’s default directory.")
                        Text("Files do not upload: keep FTP Mount running and wait a few seconds after Finder finishes copying. rclone reports transfer errors in the connection status.")
                    }
                    helpSection("Where data is stored") {
                        Text("Bookmarks are stored in ~/Library/Application Support/FTP Mount/bookmarks.json. Passwords are stored separately in the macOS login Keychain and are never written to the bookmark file.")
                    }
                    HStack {
                        Link("rclone documentation", destination: URL(string: "https://rclone.org/docs/")!)
                        Link("macFUSE support", destination: URL(string: "https://macfuse.github.io/")!)
                    }
                    .padding(.top, 4)
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(minWidth: 620, minHeight: 620)
    }

    private func helpSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.headline)
            VStack(alignment: .leading, spacing: 5, content: content)
                .font(.callout)
        }
    }
}
