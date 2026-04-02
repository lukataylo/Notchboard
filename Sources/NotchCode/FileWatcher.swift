import Foundation
import AppKit
import os.log

private let log = Logger(subsystem: "com.notchcode", category: "filewatcher")

/// Watches locked files for external modifications.
/// If a file that's locked by one agent gets modified by a different app
/// (Cursor, VS Code, Vim, anything), the watcher detects it and raises a conflict.
/// This makes the Notchboard work with ANY editor — not just hook-based agents.
class FileWatcher {
    let coordination: CoordinationEngine
    let state: NotchState
    var timer: Timer?

    /// Tracks last known modification dates for locked files
    var knownModDates: [String: Date] = [:]

    /// Files with an active (unresolved) conflict — don't re-alert
    var activeConflictPaths: Set<String> = []

    init(coordination: CoordinationEngine, state: NotchState) {
        self.coordination = coordination
        self.state = state
    }

    func start() {
        // Poll every 2 seconds for external file modifications
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.checkLockedFiles()
        }
        log.info("File watcher started — monitoring locked files for external changes")
    }

    func stop() {
        timer?.invalidate()
    }

    func checkLockedFiles() {
        let fm = FileManager.default

        for (path, lock) in coordination.fileLocks {
            guard fm.fileExists(atPath: path) else { continue }

            guard let attrs = try? fm.attributesOfItem(atPath: path),
                  let modDate = attrs[.modificationDate] as? Date else { continue }

            // First time seeing this file — record its mod date
            guard let lastKnown = knownModDates[path] else {
                knownModDates[path] = modDate
                continue
            }

            // File hasn't changed since last check
            if modDate <= lastKnown { continue }

            // File changed — update our record
            knownModDates[path] = modDate

            // Was this change from the lock owner's session? Check if there was a
            // recent post-tool-use event for this file (within last 5 seconds).
            // If so, the lock owner made the change — not a conflict.
            let recentOwnerEdit = state.sessions
                .first(where: { $0.id == lock.sessionId })?
                .tasks
                .suffix(3)
                .contains(where: {
                    $0.title.contains((path as NSString).lastPathComponent) &&
                    Date().timeIntervalSince($0.startedAt) < 5
                }) ?? false

            if recentOwnerEdit { continue }

            // External modification detected. Which app did it?
            let modifierApp = identifyModifier()
            let fileName = (path as NSString).lastPathComponent

            // Only one active conflict per file — don't spam alerts on repeated saves
            if activeConflictPaths.contains(path) { continue }
            activeConflictPaths.insert(path)

            log.info("External modification: \(fileName) by \(modifierApp.name) (locked by \(lock.agentType.displayName))")

            // Create or find a session for the external modifier
            let externalSession = getOrCreateSession(for: modifierApp)

            // Record the conflict
            coordination.stats.conflictsPrevented += 1

            let decision = PendingDecision(
                id: UUID().uuidString,
                blockedAgent: modifierApp.agentType,
                blockedSession: externalSession.name,
                ownerAgent: lock.agentType,
                ownerSession: lock.sessionName,
                toolDescription: "Edit \(fileName)",
                fileName: fileName,
                filePath: path,
                isExternal: true,
                receivedAt: Date()
            )
            coordination.pendingDecisions.append(decision)

            // Auto-share context about the external modification
            coordination.addContext(
                agentType: .claudeCode, sessionName: "switchboard",
                message: "\(modifierApp.name) modified \(fileName) which is locked by \(lock.agentType.displayName) [\(lock.sessionName)]. External edit detected."
            )

            coordination.objectWillChange.send()
            state.objectWillChange.send()
        }

        // Clean stale entries for files no longer locked
        let lockedPaths = Set(coordination.fileLocks.keys)
        knownModDates = knownModDates.filter { lockedPaths.contains($0.key) }

        // Clear active conflict flags for resolved conflicts
        let pendingPaths = Set(coordination.pendingDecisions.compactMap { $0.filePath })
        activeConflictPaths = activeConflictPaths.intersection(pendingPaths)
    }

    // MARK: - App Identification

    struct ExternalApp {
        let name: String
        let bundleId: String?
        let agentType: AgentType

        static let unknown = ExternalApp(name: "Unknown", bundleId: nil, agentType: .cursor)
    }

    /// Identify the frontmost app that likely made the change
    func identifyModifier() -> ExternalApp {
        guard let app = NSWorkspace.shared.frontmostApplication else {
            return .unknown
        }

        let bundleId = app.bundleIdentifier ?? ""
        let name = app.localizedName ?? "Unknown"

        // Map known bundle IDs to agent types
        switch bundleId {
        case "com.todesktop.230313mzl4w4u92":  // Cursor
            return ExternalApp(name: "Cursor", bundleId: bundleId, agentType: .cursor)
        case let id where id.contains("vscode") || id.contains("VSCode"):
            return ExternalApp(name: "VS Code", bundleId: bundleId, agentType: .cursor)
        case let id where id.contains("com.apple.Terminal") || id.contains("iTerm"):
            return ExternalApp(name: name, bundleId: bundleId, agentType: .claudeCode)
        default:
            return ExternalApp(name: name, bundleId: bundleId, agentType: .cursor)
        }
    }

    /// Get or create a session for an external modifier app
    func getOrCreateSession(for app: ExternalApp) -> AgentSession {
        // Check if we already have a session for this app type
        if let existing = state.sessions.first(where: {
            $0.agentType == app.agentType && $0.isActive
        }) {
            return existing
        }

        // Create a new session for the external app
        let session = AgentSession(name: app.name, projectPath: "~", agentType: app.agentType)
        session.isActive = true
        session.statusMessage = "External edit detected"
        state.sessions.append(session)
        if state.sessions.count == 1 { state.activeSessionIndex = 0 }
        return session
    }
}
