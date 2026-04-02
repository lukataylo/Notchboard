import Foundation
import os.log

private let log = Logger(subsystem: "com.notchcode", category: "coordination")

// MARK: - File Lock

struct FileLock {
    let filePath: String
    let agentType: AgentType
    let sessionName: String
    let sessionId: UUID
    let claimedAt: Date
}

// MARK: - Shared Context Entry

struct ContextEntry: Codable, Identifiable {
    let id: String
    let agentType: String
    let sessionName: String
    let message: String
    let timestamp: Date
}

// MARK: - Pending Decision

struct PendingDecision: Identifiable {
    let id: String
    let blockedAgent: AgentType
    let blockedSession: String
    let ownerAgent: AgentType
    let ownerSession: String
    let toolDescription: String
    let fileName: String
    let receivedAt: Date
}

// MARK: - Stats

struct SwitchboardStats {
    var conflictsPrevented: Int = 0
    var filesCoordinated: Int = 0
    var contextShared: Int = 0
}

// MARK: - Coordination Engine

class CoordinationEngine: ObservableObject {
    static var shared: CoordinationEngine?

    let decisionsDir: URL
    let contextFile: URL
    let locksFile: URL

    @Published var fileLocks: [String: FileLock] = [:]
    @Published var contextEntries: [ContextEntry] = []
    @Published var pendingDecisions: [PendingDecision] = []
    @Published var stats = SwitchboardStats()

    init() {
        let base = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".notchcode")
        decisionsDir = base.appendingPathComponent("decisions")
        contextFile = base.appendingPathComponent("context.json")
        locksFile = base.appendingPathComponent("file_locks.json")
        try? FileManager.default.createDirectory(at: decisionsDir, withIntermediateDirectories: true)
        loadContext()
        Self.shared = self
    }

    // MARK: - File Locking

    func checkConflict(filePath: String, agentType: AgentType, sessionId: UUID) -> FileLock? {
        guard let lock = fileLocks[filePath] else { return nil }
        if lock.sessionId == sessionId { return nil }
        if Date().timeIntervalSince(lock.claimedAt) > 300 {
            fileLocks.removeValue(forKey: filePath)
            return nil
        }
        return lock
    }

    func claimFile(_ path: String, agentType: AgentType, sessionName: String, sessionId: UUID) {
        let isNew = fileLocks[path] == nil
        fileLocks[path] = FileLock(
            filePath: path, agentType: agentType,
            sessionName: sessionName, sessionId: sessionId,
            claimedAt: Date()
        )
        if isNew { stats.filesCoordinated += 1 }
        persistLocks()
        objectWillChange.send()
    }

    func releaseFile(_ path: String) {
        fileLocks.removeValue(forKey: path)
        persistLocks()
        objectWillChange.send()
    }

    func releaseAll(for sessionId: UUID) {
        fileLocks = fileLocks.filter { $0.value.sessionId != sessionId }
        persistLocks()
        objectWillChange.send()
    }

    private func persistLocks() {
        var out: [String: [String: Any]] = [:]
        for (path, lock) in fileLocks {
            out[path] = [
                "agent_name": lock.sessionName,
                "agent_type": lock.agentType.displayName,
                "claimed_at": lock.claimedAt.timeIntervalSince1970
            ]
        }
        if let data = try? JSONSerialization.data(withJSONObject: out) {
            try? data.write(to: locksFile)
        }
    }

    // MARK: - Decision System

    /// Evaluate a tool use. Returns true if blocked (conflict).
    /// When blocked, writes a rich decision with reason so the agent can autonomously pivot.
    func evaluateToolUse(requestId: String, event: AgentEvent, agentType: AgentType, sessionName: String, sessionId: UUID) -> Bool {
        guard event.isWriteOperation else { return false }

        let filePath = event.toolInput?["file_path"]?.stringValue
            ?? event.toolInput?["command"]?.stringValue
            ?? event.toolName ?? "unknown"

        guard let conflict = checkConflict(filePath: filePath, agentType: agentType, sessionId: sessionId) else {
            // No conflict — claim and approve
            if let fp = event.toolInput?["file_path"]?.stringValue {
                claimFile(fp, agentType: agentType, sessionName: sessionName, sessionId: sessionId)
            }
            return false
        }

        // Conflict detected — build rich context for the blocked agent
        let fileName = (filePath as NSString).lastPathComponent
        stats.conflictsPrevented += 1

        let decision = PendingDecision(
            id: requestId,
            blockedAgent: agentType,
            blockedSession: sessionName,
            ownerAgent: conflict.agentType,
            ownerSession: conflict.sessionName,
            toolDescription: event.toolDescription,
            fileName: fileName,
            receivedAt: Date()
        )
        pendingDecisions.append(decision)

        // Auto-share context about the conflict so the blocked agent can read it via MCP
        let contextMsg = "\(conflict.agentType.displayName) [\(conflict.sessionName)] is currently editing \(fileName). Coordinate via notchcode-switchboard MCP tools or work on a different file."
        addContext(agentType: .claudeCode, sessionName: "switchboard", message: contextMsg)

        objectWillChange.send()
        return true
    }

    /// Write a decision response. When blocking, includes a rich reason the agent can read.
    func writeDecision(requestId: String, approved: Bool, reason: String? = nil) {
        var decision: [String: Any] = ["decision": approved ? "approve" : "block"]

        // Build rich reason for blocks so agents can autonomously pivot
        if !approved, let pending = pendingDecisions.first(where: { $0.id == requestId }) {
            let richReason = reason ?? """
            CONFLICT: \(pending.fileName) is being edited by \(pending.ownerAgent.displayName) [\(pending.ownerSession)]. \
            To coordinate: use the notchcode-switchboard MCP server tools — \
            call read_context to see what the other agent is doing, \
            call list_active_agents for full status, \
            or work on a different file to avoid the conflict.
            """
            decision["reason"] = richReason
        }

        let file = decisionsDir.appendingPathComponent("\(requestId).json")
        if let data = try? JSONSerialization.data(withJSONObject: decision) {
            try? data.write(to: file)
        }
        pendingDecisions.removeAll { $0.id == requestId }
        objectWillChange.send()
        log.info("Decision: \(requestId) → \(approved ? "approve" : "block")")
    }

    /// Auto-approve pending decisions that have timed out
    func expireOldDecisions() {
        let expired = pendingDecisions.filter { Date().timeIntervalSince($0.receivedAt) > 12 }
        for decision in expired {
            writeDecision(requestId: decision.id, approved: true)
        }
    }

    // MARK: - Shared Context

    func addContext(agentType: AgentType, sessionName: String, message: String) {
        let entry = ContextEntry(
            id: UUID().uuidString,
            agentType: agentType.rawValue,
            sessionName: sessionName,
            message: message,
            timestamp: Date()
        )
        contextEntries.append(entry)
        if contextEntries.count > 50 { contextEntries.removeFirst() }
        stats.contextShared += 1
        saveContext()
        objectWillChange.send()
    }

    func loadContext() {
        guard let data = try? Data(contentsOf: contextFile),
              let entries = try? JSONDecoder().decode([ContextEntry].self, from: data) else { return }
        contextEntries = entries.filter { Date().timeIntervalSince($0.timestamp) < 3600 }
    }

    func saveContext() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(contextEntries) {
            try? data.write(to: contextFile)
        }
    }

    // MARK: - MCP State

    func writeMCPState(sessions: [AgentSession]) {
        let base = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".notchcode")
        let stateFile = base.appendingPathComponent("mcp_state.json")

        var agents: [[String: Any]] = []
        for session in sessions where session.isActive {
            agents.append([
                "agent_type": session.agentType.displayName,
                "session_name": session.name,
                "project_path": session.projectPath,
                "status": session.statusMessage,
                "progress": session.progress,
                "input_tokens": session.inputTokens,
                "output_tokens": session.outputTokens,
                "duration": session.duration,
                "is_waiting": session.isWaitingForUser,
                "task_count": session.tasks.count,
                "last_reasoning": session.lastReasoning ?? ""
            ])
        }

        var locks: [[String: Any]] = []
        for (path, lock) in fileLocks {
            locks.append([
                "file_path": path,
                "agent_type": lock.agentType.displayName,
                "session_name": lock.sessionName,
                "claimed_at": ISO8601DateFormatter().string(from: lock.claimedAt)
            ])
        }

        let state: [String: Any] = [
            "agents": agents,
            "file_locks": locks,
            "context_entries": contextEntries.map { [
                "id": $0.id, "agent_type": $0.agentType,
                "session_name": $0.sessionName, "message": $0.message,
                "timestamp": ISO8601DateFormatter().string(from: $0.timestamp)
            ] },
            "stats": [
                "conflicts_prevented": stats.conflictsPrevented,
                "files_coordinated": stats.filesCoordinated,
                "context_shared": stats.contextShared
            ]
        ]

        if let data = try? JSONSerialization.data(withJSONObject: state, options: .prettyPrinted) {
            try? data.write(to: stateFile)
        }
    }
}
