import Foundation
import AppKit
import os.log

private let log = Logger(subsystem: "com.notchcode", category: "cursor")

class CursorProvider: BaseAgentProvider {
    override var providerType: AgentType { .cursor }

    var activityTimer: Timer?

    init(state: NotchState, coordination: CoordinationEngine) {
        super.init(state: state, coordination: coordination, eventsSubdir: "cursor")
    }

    override func start() {
        super.start()
        log.info("Cursor provider started, watching \(self.eventsDir.path)")

        activityTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.detectCursorActivity()
        }

        DispatchQueue.global(qos: .utility).async { [weak self] in
            self?.detectCursorActivity()
        }
    }

    override func cleanup() {
        activityTimer?.invalidate()
        super.cleanup()
    }

    // MARK: - Cursor Activity Detection

    func detectCursorActivity() {
        let running = NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == "com.todesktop.230313mzl4w4u92" }
        if !running {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                let stale = self.state.sessions.filter { $0.agentType == .cursor && $0.isActive && $0.tasks.isEmpty }
                for session in stale { session.isActive = false }
                if !stale.isEmpty { self.state.objectWillChange.send() }
            }
            return
        }

        let cursorSupport = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Cursor/User/workspaceStorage")

        guard let dirs = try? FileManager.default.contentsOfDirectory(at: cursorSupport, includingPropertiesForKeys: nil) else { return }

        let recent = dirs.compactMap { dir -> (url: URL, date: Date)? in
            let wsFile = dir.appendingPathComponent("workspace.json")
            guard let attrs = try? FileManager.default.attributesOfItem(atPath: wsFile.path),
                  let date = attrs[.modificationDate] as? Date,
                  Date().timeIntervalSince(date) < 600 else { return nil }
            return (url: wsFile, date: date)
        }.sorted { $0.date > $1.date }

        for item in recent.prefix(3) {
            guard let data = try? Data(contentsOf: item.url),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let folder = json["folder"] as? String else { continue }

            let path: String
            if folder.hasPrefix("file://") {
                path = String(folder.dropFirst(7)).removingPercentEncoding ?? String(folder.dropFirst(7))
            } else {
                path = folder
            }

            let name = (path as NSString).lastPathComponent

            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                if self.state.sessions.contains(where: { $0.projectPath == path && $0.agentType == .cursor }) { return }
                let session = AgentSession(name: name, projectPath: path, agentType: .cursor)
                session.isActive = true
                session.statusMessage = "Active in Cursor"
                self.state.sessions.append(session)
                if self.state.sessions.count == 1 { self.state.activeSessionIndex = 0 }
                self.state.objectWillChange.send()
            }
        }
    }

    // MARK: - Open in Cursor

    func openInCursor(path: String) {
        DispatchQueue.global(qos: .userInitiated).async {
            NSAppleScript(source: "tell application \"Cursor\" to activate")?.executeAndReturnError(nil)
        }
    }
}
