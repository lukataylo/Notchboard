import AppKit
import SwiftUI
import Combine

// MARK: - Agent Types

enum AgentType: String, CaseIterable {
    case claudeCode
    case cursor

    var displayName: String {
        switch self {
        case .claudeCode: return "Claude Code"
        case .cursor: return "Cursor"
        }
    }

    var accentColor: Color {
        switch self {
        case .claudeCode: return claudeOrange
        case .cursor: return cursorPurple
        }
    }
}

// MARK: - Constants

let claudeOrange = Color(red: 0.851, green: 0.467, blue: 0.341)
let cursorPurple = Color(red: 0.4, green: 0.35, blue: 0.85)
let claudeGreen = Color.green

// MARK: - NSScreen Extension

extension NSScreen {
    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }
    var hasNotch: Bool {
        if #available(macOS 12.0, *) { return safeAreaInsets.top > 0 }
        return false
    }
}

// MARK: - Models

struct TaskItem: Identifiable {
    let id = UUID()
    var title: String
    var status: TaskStatus
    var detail: String?
    var startedAt: Date = Date()

    var elapsed: String {
        let s = Date().timeIntervalSince(startedAt)
        return s < 60 ? String(format: "%.1fs", s) : String(format: "%.0fm", s / 60)
    }

    enum TaskStatus {
        case running, completed
        var label: String { self == .running ? "Running" : "Done" }
        var color: Color { self == .running ? .orange : claudeGreen }
        var icon: String { self == .running ? "circle.dotted" : "checkmark.circle.fill" }
    }
}

class AgentSession: Identifiable, ObservableObject {
    let id = UUID()
    let agentType: AgentType
    @Published var name: String
    @Published var projectPath: String
    @Published var progress: Double = 0
    @Published var tasks: [TaskItem] = []
    @Published var statusMessage: String = "Idle"
    @Published var isActive: Bool = false
    @Published var lastResponse: String? = nil
    @Published var lastReasoning: String? = nil
    @Published var inputTokens: Int = 0
    @Published var outputTokens: Int = 0
    @Published var isWaitingForUser: Bool = false
    @Published var transcriptPath: String? = nil
    var transcriptReader: TranscriptReader? = nil
    var startedAt: Date = Date()

    init(name: String, projectPath: String, agentType: AgentType) {
        self.name = name
        self.projectPath = projectPath
        self.agentType = agentType
    }

    var tokenSummary: String {
        guard inputTokens > 0 else { return "" }
        return "\(formatTokens(inputTokens))in / \(formatTokens(outputTokens))out"
    }

    var duration: String {
        let s = Date().timeIntervalSince(startedAt)
        if s < 60 { return "\(Int(s))s" }
        if s < 3600 { return "\(Int(s / 60))m" }
        return String(format: "%.1fh", s / 3600)
    }
}

// MARK: - App State

class NotchState: ObservableObject {
    @Published var sessions: [AgentSession] = []
    @Published var activeSessionIndex: Int = 0
    @Published var expandedScreenID: CGDirectDisplayID? = nil

    var activeSession: AgentSession? {
        guard sessions.indices.contains(activeSessionIndex) else { return nil }
        return sessions[activeSessionIndex]
    }
    var hasActiveWork: Bool { sessions.contains { $0.isActive } }

    var activeAgentTypes: Set<AgentType> {
        Set(sessions.filter { $0.isActive }.map { $0.agentType })
    }
}
