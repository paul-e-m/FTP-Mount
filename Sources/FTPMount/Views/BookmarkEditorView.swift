import SwiftUI

struct BookmarkEditorView: View {
    @EnvironmentObject private var bookmarkStore: BookmarkStore
    @EnvironmentObject private var mountManager: MountManager

    @State private var draft: Bookmark
    @State private var password = ""
    @State private var savedPassword = ""
    @State private var portText: String
    @State private var errorMessage: String?
    @State private var hasLoadedPassword = false

    init(bookmark: Bookmark) {
        _draft = State(initialValue: bookmark)
        _portText = State(initialValue: bookmark.port.map(String.init) ?? "")
    }

    private var state: MountState { mountManager.state(for: draft.id) }
    private var isBusy: Bool {
        switch state {
        case .mounting, .unmounting: return true
        default: return false
        }
    }

    private var savedBookmark: Bookmark? { bookmarkStore.bookmark(id: draft.id) }

    private var hasUnsavedChanges: Bool {
        guard let savedBookmark else { return true }
        return draft != savedBookmark || password != savedPassword
    }

    private var canConnect: Bool {
        savedBookmark?.isValid == true && !hasUnsavedChanges && !isBusy
    }

    var body: some View {
        Form {
            Section("Connection") {
                TextField("Bookmark name", text: $draft.name)
                Picker("Protocol", selection: $draft.transferProtocol) {
                    ForEach(TransferProtocol.allCases) { item in
                        Text(item.rawValue).tag(item)
                    }
                }
                .pickerStyle(.segmented)

                if draft.transferProtocol == .webdav {
                    TextField("WebDAV server URL", text: $draft.server, prompt: Text("https://dav.example.com/files"))
                    Picker("WebDAV server type", selection: $draft.webDAVVendor) {
                        ForEach(WebDAVVendor.allCases) { vendor in
                            Text(vendor.rawValue).tag(vendor)
                        }
                    }
                    Text("Use the full WebDAV URL supplied by your provider, including https:// and any path.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    TextField("Server host or IP", text: $draft.server, prompt: Text("ftp.example.com"))
                    TextField("Port (default: \(draft.transferProtocol.defaultPort))", text: $portText)
                        .onChange(of: portText) { newValue in
                            portText = newValue.filter(\.isNumber)
                        }
                }
                TextField("Username", text: $draft.username)
                    .textContentType(.username)
                SecureField("Password", text: $password)
                    .textContentType(.password)
                TextField("Root directory (optional)", text: $draft.rootDirectory, prompt: Text("/uploads"))
                if draft.transferProtocol == .sftp {
                    Toggle("Verify server key using ~/.ssh/known_hosts", isOn: $draft.verifySFTPHostKey)
                    if draft.verifySFTPHostKey {
                        Text("Unknown or changed server keys are rejected. Connect once with macOS ssh to add a trusted key.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if draft.transferProtocol == .ftp {
                Label(
                    "FTP does not encrypt credentials or file contents. Use SFTP whenever the server supports it.",
                    systemImage: "exclamationmark.shield"
                )
                .font(.callout)
                .foregroundStyle(.orange)
            }
            if draft.transferProtocol == .webdav {
                Label(
                    "Use an https:// WebDAV URL whenever possible. HTTP WebDAV does not encrypt credentials or file contents.",
                    systemImage: "exclamationmark.shield"
                )
                .font(.callout)
                .foregroundStyle(.orange)
            }

            Section {
                HStack {
                    Label(state.label, systemImage: state.isMounted ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(state.isMounted ? .green : .secondary)
                    Spacer()
                    Button("Save Bookmark", action: save)
                        .disabled(isBusy)
                    if state.isMounted {
                        Button("Show in Finder") { mountManager.reveal(draft.id) }
                        Button("Unmount") { Task { await mountManager.unmount(draft.id) } }
                            .buttonStyle(.borderedProminent)
                    } else {
                        Button("Connect", action: connect)
                            .buttonStyle(.borderedProminent)
                            .disabled(!canConnect)
                    }
                }
                if hasUnsavedChanges {
                    Text("Save changes before connecting. Connect always uses the saved bookmark and its Keychain password.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(draft.name)
        .padding(.top, 4)
        .task {
            guard !hasLoadedPassword else { return }
            hasLoadedPassword = true
            do {
                password = try bookmarkStore.password(for: draft)
                savedPassword = password
            }
            catch { errorMessage = error.localizedDescription }
        }
        .alert("Could Not Save Connection", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var draftIsValid: Bool {
        var candidate = draft
        candidate.port = parsedPort
        return candidate.isValid && (portText.isEmpty || parsedPort != nil)
    }

    private var parsedPort: Int? {
        guard !portText.isEmpty else { return nil }
        return Int(portText)
    }

    private func save() {
        do {
            draft.port = parsedPort
            try bookmarkStore.save(draft, password: password)
            draft = bookmarkStore.bookmark(id: draft.id) ?? draft
            savedPassword = password
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func connect() {
        guard let bookmark = savedBookmark else { return }
        Task {
            do {
                let savedPassword = try bookmarkStore.password(for: bookmark)
                await mountManager.mount(bookmark, password: savedPassword)
            } catch {
                errorMessage = "Could not read the saved password: \(error.localizedDescription)"
            }
        }
    }
}
