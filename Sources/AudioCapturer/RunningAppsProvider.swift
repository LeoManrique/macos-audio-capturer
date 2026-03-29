import AppKit
import Observation

struct RunningApp: Identifiable, Hashable {
    let id: String // bundleIdentifier
    let name: String
    let icon: NSImage

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: RunningApp, rhs: RunningApp) -> Bool {
        lhs.id == rhs.id
    }
}

@Observable
@MainActor
final class RunningAppsProvider {
    var apps: [RunningApp] = []

    private var observer: NSObjectProtocol?

    init() {
        refresh()
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }

        let terminateObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        // Store second observer — we only need to prevent dealloc
        _ = terminateObserver
    }

    func refresh() {
        apps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app -> RunningApp? in
                guard let bundleID = app.bundleIdentifier,
                      let name = app.localizedName else { return nil }
                let icon = app.icon ?? NSImage(named: NSImage.applicationIconName)!
                icon.size = NSSize(width: 16, height: 16)
                return RunningApp(id: bundleID, name: name, icon: icon)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
