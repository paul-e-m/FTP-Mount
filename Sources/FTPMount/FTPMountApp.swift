import AppKit
import SwiftUI

@main
struct FTPMountApp: App {
    @StateObject private var bookmarkStore = BookmarkStore()
    @StateObject private var mountManager = MountManager()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(bookmarkStore)
                .environmentObject(mountManager)
                .frame(minWidth: 820, minHeight: 520)
                .onAppear { appDelegate.mountManager = mountManager }
        }
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Connection") {
                    NotificationCenter.default.post(name: .newFTPMountBookmark, object: nil)
                }
                .keyboardShortcut("n")
            }
            CommandGroup(replacing: .help) {
                Button("FTP Mount Help") {
                    NotificationCenter.default.post(name: .showFTPMountHelp, object: nil)
                }
                .keyboardShortcut("?", modifiers: .command)
                Button("Check Requirements") {
                    NotificationCenter.default.post(name: .showFTPMountSetup, object: nil)
                }
            }
        }

        Settings {
            SetupView()
                .environmentObject(mountManager)
                .frame(width: 640, height: 550)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var mountManager: MountManager?

    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated {
            mountManager?.unmountAll()
        }
    }
}

extension Notification.Name {
    static let newFTPMountBookmark = Notification.Name("FTPMount.newBookmark")
    static let showFTPMountHelp = Notification.Name("FTPMount.showHelp")
    static let showFTPMountSetup = Notification.Name("FTPMount.showSetup")
}
