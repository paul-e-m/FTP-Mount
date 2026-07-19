import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var bookmarkStore: BookmarkStore
    @EnvironmentObject private var mountManager: MountManager
    @State private var selection: UUID?
    @State private var showingSetup = false
    @State private var showingHelp = false

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section("Saved connections") {
                    ForEach(bookmarkStore.bookmarks) { bookmark in
                        BookmarkRow(bookmark: bookmark, state: mountManager.state(for: bookmark.id))
                            .tag(bookmark.id)
                    }
                }
            }
            .navigationTitle("FTP Mount")
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: 12) {
                    Button(action: addBookmark) {
                        Image(systemName: "plus")
                    }
                    .help("New connection")
                    Button(action: deleteSelected) {
                        Image(systemName: "minus")
                    }
                    .disabled(selection == nil)
                    .help("Delete connection")
                    Spacer()
                    Button(action: { showingSetup = true }) {
                        Image(systemName: "wrench.and.screwdriver")
                    }
                    .help("Setup")
                }
                .buttonStyle(.borderless)
                .padding(10)
                .background(.bar)
            }
        } detail: {
            if let id = selection, let bookmark = bookmarkStore.bookmark(id: id) {
                BookmarkEditorView(bookmark: bookmark)
                    .id(bookmark.id)
            } else {
                EmptyStateView(addAction: addBookmark)
            }
        }
        .sheet(isPresented: $showingSetup) {
            SetupView()
                .environmentObject(mountManager)
                .frame(width: 640, height: 550)
        }
        .sheet(isPresented: $showingHelp) {
            HelpView()
        }
        .alert("FTP Mount", isPresented: Binding(
            get: { bookmarkStore.lastError != nil },
            set: { if !$0 { bookmarkStore.lastError = nil } }
        )) {
            Button("OK", role: .cancel) { bookmarkStore.lastError = nil }
        } message: {
            Text(bookmarkStore.lastError ?? "")
        }
        .onReceive(NotificationCenter.default.publisher(for: .newFreeTPBookmark)) { _ in
            addBookmark()
        }
        .onReceive(NotificationCenter.default.publisher(for: .showFreeTPHelp)) { _ in
            showingHelp = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .showFreeTPSetup)) { _ in
            showingSetup = true
        }
        .onAppear {
            if selection == nil { selection = bookmarkStore.bookmarks.first?.id }
        }
    }

    private func addBookmark() {
        selection = bookmarkStore.add().id
    }

    private func deleteSelected() {
        guard let id = selection, let bookmark = bookmarkStore.bookmark(id: id) else { return }
        Task {
            await mountManager.unmount(id)
            do {
                try bookmarkStore.delete(bookmark)
                selection = bookmarkStore.bookmarks.first?.id
            } catch {
                bookmarkStore.lastError = error.localizedDescription
            }
        }
    }
}

private struct BookmarkRow: View {
    let bookmark: Bookmark
    let state: MountState

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: state.isMounted ? "externaldrive.fill.badge.checkmark" : "externaldrive")
                .foregroundStyle(state.isMounted ? .green : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(bookmark.name).lineLimit(1)
                Text("\(bookmark.transferProtocol.rawValue) · \(bookmark.server.isEmpty ? "Not configured" : bookmark.server)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 3)
    }
}

private struct EmptyStateView: View {
    let addAction: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "externaldrive.connected.to.line.below")
                .font(.system(size: 42))
                .foregroundStyle(.secondary)
            Text("No Connection Selected")
                .font(.title2.bold())
            Text("Create a bookmark for an FTP, SFTP, or WebDAV server.")
                .foregroundStyle(.secondary)
            Button("New Connection", action: addAction)
                .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}
