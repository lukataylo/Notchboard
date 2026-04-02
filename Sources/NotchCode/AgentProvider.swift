import Foundation
import AppKit
import os.log

// MARK: - Agent Provider Protocol

protocol AgentProvider: AnyObject {
    var providerType: AgentType { get }
    var state: NotchState { get }
    var coordination: CoordinationEngine { get }
    func start()
    func cleanup()
}

// MARK: - Base Agent Provider (shared event processing)

class BaseAgentProvider: AgentProvider {
    var providerType: AgentType { fatalError("Subclass must override") }
    let state: NotchState
    let coordination: CoordinationEngine
    let eventsDir: URL

    var source: DispatchSourceFileSystemObject?
    var dirFD: Int32 = -1
    var sessionMap: [String: UUID] = [:]
    var toolCounts: [String: Int] = [:]
    var runningTools: [String: (sessionUUID: UUID, taskTitle: String)] = [:]
    var handledEvents: Set<String> = []

    init(state: NotchState, coordination: CoordinationEngine, eventsSubdir: String) {
        self.state = state
        self.coordination = coordination
        let base = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".notchcode")
        self.eventsDir = base.appendingPathComponent("events/\(eventsSubdir)")
    }

    func start() {
        let fm = FileManager.default
        try? fm.createDirectory(at: eventsDir, withIntermediateDirectories: true)
        startWatching()
    }

    func cleanup() {
        if let files = try? FileManager.default.contentsOfDirectory(at: eventsDir, includingPropertiesForKeys: nil) {
            for file in files { try? FileManager.default.removeItem(at: file) }
        }
        source?.cancel()
        if dirFD >= 0 { close(dirFD); dirFD = -1 }
    }

    // MARK: - File Watching

    func startWatching() {
        dirFD = open(eventsDir.path, O_EVTONLY)
        guard dirFD >= 0 else { return }
        source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: dirFD, eventMask: .write, queue: .main)
        source?.setEventHandler { [weak self] in self?.processEvents() }
        source?.setCancelHandler { [weak self] in
            if let fd = self?.dirFD, fd >= 0 { close(fd) }
            self?.dirFD = -1
        }
        source?.resume()
    }

    // MARK: - Event Processing (shared)

    func processEvents() {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: eventsDir, includingPropertiesForKeys: nil) else { return }

        for file in files.filter({ $0.pathExtension == "json" }).sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let filename = file.lastPathComponent
            if handledEvents.contains(filename) { continue }

            guard let data = try? Data(contentsOf: file),
                  let event = try? JSONDecoder().decode(AgentEvent.self, from: data) else {
                if let a = try? fm.attributesOfItem(atPath: file.path),
                   let d = a[.creationDate] as? Date, Date().timeIntervalSince(d) > 10 {
                    try? fm.removeItem(at: file)
                }
                continue
            }

            handledEvents.insert(filename)
            handleEvent(event)
            try? fm.removeItem(at: file)
        }
    }

    func handleEvent(_ event: AgentEvent) {
        guard let sessionId = event.sessionId else { return }

        let projectName = event.cwd.map { ($0 as NSString).lastPathComponent } ?? String(sessionId.prefix(8))
        let session: AgentSession
        if let uuid = sessionMap[sessionId], let existing = state.sessions.first(where: { $0.id == uuid }) {
            session = existing
        } else {
            let s = AgentSession(name: projectName, projectPath: event.cwd ?? "~", agentType: providerType)
            s.isActive = true; s.statusMessage = "Connected"
            state.sessions.append(s)
            sessionMap[sessionId] = s.id
            toolCounts[sessionId] = 0
            session = s
            if state.sessions.count == 1 { state.activeSessionIndex = 0 }
        }

        onSessionReady(session: session, event: event)

        let hookType = event.hookType ?? event.hookEventName?.lowercased() ?? ""
        let toolUseId = event.toolUseId ?? event.requestId ?? UUID().uuidString

        switch hookType {
        case "pre-tool-use", "pretooluse":
            handlePreToolUse(event: event, session: session, toolUseId: toolUseId)
        case "post-tool-use", "posttooluse":
            handlePostToolUse(event: event, session: session, sessionId: sessionId, toolUseId: toolUseId)
        default: break
        }
        state.objectWillChange.send()
    }

    /// Override point for subclasses (e.g. setting up transcript reader)
    func onSessionReady(session: AgentSession, event: AgentEvent) {}

    private func handlePreToolUse(event: AgentEvent, session: AgentSession, toolUseId: String) {
        let desc = event.toolDescription
        let requestId = event.requestId ?? toolUseId

        // Coordination: check conflicts for write ops, auto-approve reads
        let blocked = coordination.evaluateToolUse(
            requestId: requestId, event: event,
            agentType: providerType, sessionName: session.name, sessionId: session.id
        )
        if !blocked {
            coordination.writeDecision(requestId: requestId, approved: true)
        }

        if session.tasks.count >= 20 { session.tasks.removeFirst() }
        session.tasks.append(TaskItem(title: desc, status: .running))
        session.statusMessage = desc
        session.isWaitingForUser = false
        runningTools[toolUseId] = (sessionUUID: session.id, taskTitle: desc)
    }

    private func handlePostToolUse(event: AgentEvent, session: AgentSession, sessionId: String, toolUseId: String) {
        let desc = event.toolDescription
        toolCounts[sessionId, default: 0] += 1

        let detail: String?
        if let r = event.toolResponse {
            detail = r.interrupted == true ? "interrupted" : (r.stderr?.isEmpty == false ? "stderr" : nil)
            if let stdout = r.stdout, !stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let trimmed = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
                let lines = trimmed.components(separatedBy: "\n").suffix(4)
                session.lastResponse = String(lines.joined(separator: "\n").suffix(200))
            }
        } else { detail = nil }

        if let info = runningTools.removeValue(forKey: toolUseId),
           let idx = session.tasks.lastIndex(where: { $0.title == info.taskTitle && $0.status == .running }) {
            session.tasks[idx].status = .completed
            session.tasks[idx].detail = detail
        } else {
            if session.tasks.count >= 20 { session.tasks.removeFirst() }
            session.tasks.append(TaskItem(title: desc, status: .completed, detail: detail))
        }

        let count = toolCounts[sessionId, default: 1]
        session.progress = min(1.0 - 1.0 / (Double(count) * 0.3 + 1.0), 0.99)
        session.statusMessage = desc
    }
}

// MARK: - Provider Registry

class AgentProviderRegistry {
    private var providers: [AgentProvider] = []
    let state: NotchState

    init(state: NotchState) {
        self.state = state
    }

    func register(_ provider: AgentProvider) {
        providers.append(provider)
    }

    func startAll() {
        for provider in providers { provider.start() }
    }

    func cleanupAll() {
        for provider in providers { provider.cleanup() }
    }

    func provider(for type: AgentType) -> AgentProvider? {
        providers.first { $0.providerType == type }
    }

    func claudeProvider() -> ClaudeCodeProvider? {
        provider(for: .claudeCode) as? ClaudeCodeProvider
    }
}

// MARK: - Shared Event Model

struct AgentEvent: Codable {
    let sessionId: String?
    let cwd: String?
    let permissionMode: String?
    let hookEventName: String?
    let toolName: String?
    let toolInput: [String: AnyCodableValue]?
    let toolResponse: ToolResponse?
    let toolUseId: String?
    let hookType: String?
    let requestId: String?
    let transcriptPath: String?

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id", cwd, permissionMode = "permission_mode"
        case hookEventName = "hook_event_name", toolName = "tool_name"
        case toolInput = "tool_input", toolResponse = "tool_response"
        case toolUseId = "tool_use_id", hookType = "hook_type", requestId = "request_id"
        case transcriptPath = "transcript_path"
    }

    struct ToolResponse: Codable {
        let stdout: String?
        let stderr: String?
        let interrupted: Bool?
    }

    var toolDescription: String {
        guard let input = toolInput else { return toolName ?? "Tool" }
        switch toolName {
        case "Edit": return "Edit \(shortPath(input["file_path"]?.stringValue))"
        case "Write": return "Write \(shortPath(input["file_path"]?.stringValue))"
        case "Read": return "Read \(shortPath(input["file_path"]?.stringValue))"
        case "Bash":
            return input["description"]?.stringValue ?? "Run: \(String((input["command"]?.stringValue ?? "").prefix(50)))"
        case "Glob": return "Search: \(input["pattern"]?.stringValue ?? "")"
        case "Grep": return "Grep: \(input["pattern"]?.stringValue ?? "")"
        case "Agent": return "Agent: \(input["description"]?.stringValue ?? "subagent")"
        default: return toolName ?? "Tool"
        }
    }

    var isWriteOperation: Bool { ["Edit", "Write", "Bash", "NotebookEdit"].contains(toolName) }

    private func shortPath(_ path: String?) -> String {
        guard let path = path else { return "file" }
        let parts = path.split(separator: "/")
        return parts.count > 2 ? String(parts.suffix(2).joined(separator: "/")) : path
    }
}

// MARK: - AnyCodableValue

enum AnyCodableValue: Codable {
    case string(String), int(Int), double(Double), bool(Bool), null
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode(Int.self) { self = .int(v) }
        else if let v = try? c.decode(Double.self) { self = .double(v) }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else { self = .null }
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let v): try c.encode(v)
        case .int(let v): try c.encode(v)
        case .double(let v): try c.encode(v)
        case .bool(let v): try c.encode(v)
        case .null: try c.encodeNil()
        }
    }
    var stringValue: String? { if case .string(let v) = self { return v }; return nil }
}
