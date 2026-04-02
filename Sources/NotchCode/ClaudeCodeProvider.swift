import Foundation
import AppKit
import os.log

private let log = Logger(subsystem: "com.notchcode", category: "claude")

class ClaudeCodeProvider: BaseAgentProvider {
    override var providerType: AgentType { .claudeCode }

    let binDir: URL
    var transcriptTimer: Timer?
    var decisionTimer: Timer?

    init(state: NotchState, coordination: CoordinationEngine) {
        let base = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".notchcode")
        self.binDir = base.appendingPathComponent("bin")
        super.init(state: state, coordination: coordination, eventsSubdir: "claude")
    }

    override func start() {
        let fm = FileManager.default
        try? fm.createDirectory(at: binDir, withIntermediateDirectories: true)
        writeHookScript()
        super.start()
        log.info("Claude provider started, watching \(self.eventsDir.path)")

        transcriptTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.pollTranscripts()
            self?.coordination.writeMCPState(sessions: self?.state.sessions ?? [])
        }

        decisionTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.coordination.expireOldDecisions()
            self?.coordination.pollMCPConflicts()
        }

        DispatchQueue.global(qos: .utility).async { [weak self] in
            self?.detectRunningSessions()
        }
    }

    override func onSessionReady(session: AgentSession, event: AgentEvent) {
        if let tp = event.transcriptPath, session.transcriptReader == nil {
            session.transcriptPath = tp
            session.transcriptReader = TranscriptReader(path: tp)
        }
    }

    override func cleanup() {
        // Clean pending decisions so hooks don't hang
        let decisionsDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".notchcode/decisions")
        if let files = try? FileManager.default.contentsOfDirectory(at: decisionsDir, includingPropertiesForKeys: nil) {
            for file in files { try? FileManager.default.removeItem(at: file) }
        }
        transcriptTimer?.invalidate()
        decisionTimer?.invalidate()
        super.cleanup()
    }

    // MARK: - Process Detection

    private func detectRunningSessions() {
        let pipe = Pipe()
        let ps = Process()
        ps.executableURL = URL(fileURLWithPath: "/bin/ps")
        ps.arguments = ["-eo", "pid,comm"]
        ps.standardOutput = pipe
        ps.standardError = FileHandle.nullDevice
        guard (try? ps.run()) != nil else { return }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        ps.waitUntilExit()
        guard let output = String(data: data, encoding: .utf8) else { return }

        var pids: [Int32] = []
        for line in output.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasSuffix(" claude") || trimmed.hasSuffix("/claude") {
                if let pid = Int32(trimmed.split(separator: " ").first ?? "") { pids.append(pid) }
            }
        }
        guard !pids.isEmpty else { return }

        var sessions: [(name: String, path: String)] = []
        for pid in pids {
            let lp = Pipe()
            let lsof = Process()
            lsof.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
            lsof.arguments = ["-p", String(pid), "-Fn", "-d", "cwd"]
            lsof.standardOutput = lp
            lsof.standardError = FileHandle.nullDevice
            guard (try? lsof.run()) != nil else { continue }
            let ld = lp.fileHandleForReading.readDataToEndOfFile()
            lsof.waitUntilExit()
            if let out = String(data: ld, encoding: .utf8),
               let line = out.components(separatedBy: "\n").last(where: { $0.hasPrefix("n/") }) {
                let cwd = String(line.dropFirst())
                sessions.append((name: (cwd as NSString).lastPathComponent, path: cwd))
            }
        }

        guard !sessions.isEmpty else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            for s in sessions {
                if self.state.sessions.contains(where: { $0.projectPath == s.path && $0.agentType == .claudeCode }) { continue }
                let session = AgentSession(name: s.name, projectPath: s.path, agentType: .claudeCode)
                session.isActive = true
                session.statusMessage = "Running"
                self.state.sessions.append(session)
            }
            if !self.state.sessions.isEmpty { self.state.activeSessionIndex = 0 }
            self.state.objectWillChange.send()
        }
    }

    // MARK: - Transcript Polling

    func pollTranscripts() {
        var changed = false
        for session in state.sessions where session.isActive && session.agentType == .claudeCode {
            guard let reader = session.transcriptReader else { continue }
            for entry in reader.readNew() {
                switch entry {
                case .reasoning(let text):
                    let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !clean.isEmpty {
                        if let dot = clean.firstIndex(of: "."), clean.distance(from: clean.startIndex, to: dot) < 150 {
                            session.lastReasoning = String(clean[...dot])
                        } else {
                            session.lastReasoning = String(clean.prefix(150))
                        }
                        changed = true
                    }
                case .usage(let input, let output):
                    session.inputTokens = input
                    session.outputTokens = output
                    changed = true
                case .userMessage:
                    session.isWaitingForUser = false
                    changed = true
                }
            }
        }
        if changed { state.objectWillChange.send() }
    }

    // MARK: - Send Message to Terminal

    func sendToTerminal(_ message: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(message, forType: .string)

        if let session = state.activeSession {
            if session.tasks.count >= 20 { session.tasks.removeFirst() }
            session.tasks.append(TaskItem(title: "Copied: \(String(message.prefix(50)))", status: .completed))
            state.objectWillChange.send()
        }

        DispatchQueue.global(qos: .userInitiated).async {
            let script = """
            tell application "Terminal"
                repeat with w in windows
                    repeat with t in tabs of w
                        if busy of t and processes of t contains "claude" then
                            set frontmost of w to true
                            activate
                            return
                        end if
                    end repeat
                end repeat
            end tell
            """
            var err: NSDictionary?
            NSAppleScript(source: script)?.executeAndReturnError(&err)
            if err != nil {
                NSAppleScript(source: "tell application \"iTerm2\" to activate")?.executeAndReturnError(nil)
            }
        }
    }

    // MARK: - Hook Script

    func writeHookScript() {
        let script = """
#!/bin/bash
# NotchCode Switchboard hook — coordination layer for multi-agent development.
# Supports Claude Code and Cursor. Falls back to auto-approve if NotchCode is down.
HOOK_TYPE="${1:-notification}"
REQUEST_ID="$(date +%s%N 2>/dev/null || date +%s)-$$"
DECISIONS_DIR="$HOME/.notchcode/decisions"
INPUT=$(cat -)
if [ -n "$VSCODE_PID" ] || [ -n "$CURSOR_TRACE_DIR" ]; then
    EVENTS_DIR="$HOME/.notchcode/events/cursor"
else
    EVENTS_DIR="$HOME/.notchcode/events/claude"
fi
mkdir -p "$EVENTS_DIR" "$DECISIONS_DIR"
if ! pgrep -f "NotchCode" >/dev/null 2>&1; then
    [ "$HOOK_TYPE" = "pre-tool-use" ] && echo '{"decision":"approve"}'
    exit 0
fi
EVENT=$(/usr/bin/python3 -c "
import json,sys
try: data=json.load(sys.stdin)
except: data={}
data['hook_type']=sys.argv[1]; data['request_id']=sys.argv[2]
json.dump(data,sys.stdout)
" "$HOOK_TYPE" "$REQUEST_ID" <<< "$INPUT" 2>/dev/null)
[ -z "$EVENT" ] && EVENT='{"hook_type":"'"$HOOK_TYPE"'","request_id":"'"$REQUEST_ID"'"}'
echo "$EVENT" > "$EVENTS_DIR/$REQUEST_ID.json"
if [ "$HOOK_TYPE" = "pre-tool-use" ]; then
    DECISION_FILE="$DECISIONS_DIR/$REQUEST_ID.json"
    WAITED=0
    while [ ! -f "$DECISION_FILE" ] && [ $WAITED -lt 150 ]; do
        sleep 0.1
        WAITED=$((WAITED + 1))
    done
    if [ -f "$DECISION_FILE" ]; then
        cat "$DECISION_FILE"
        rm -f "$DECISION_FILE"
    else
        echo '{"decision":"approve"}'
    fi
fi
"""
        let url = binDir.appendingPathComponent("notchcode-hook")
        try? script.write(to: url, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }

    // MARK: - Install/Remove Hooks

    func installHooks() {
        let hookPath = binDir.appendingPathComponent("notchcode-hook").path
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/settings.json")
        var settings: [String: Any] = (try? Data(contentsOf: url))
            .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]

        let hook: ([String]) -> [[String: Any]] = { types in
            types.map { ["matcher": "", "hooks": [["type": "command", "command": "\(hookPath) \($0)"]]] }
        }
        var hooks = settings["hooks"] as? [String: Any] ?? [:]
        hooks["PreToolUse"] = hook(["pre-tool-use"])
        hooks["PostToolUse"] = hook(["post-tool-use"])
        settings["hooks"] = hooks

        if let data = try? JSONSerialization.data(withJSONObject: settings, options: .prettyPrinted) {
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: url)
        }

        let alert = NSAlert()
        alert.messageText = "Hooks Installed"
        alert.informativeText = "AI coding agents will now stream activity to NotchCode. Works with Claude Code and Cursor."
        alert.runModal()
    }

    func removeHooks() {
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/settings.json")
        guard var settings = (try? Data(contentsOf: url)).flatMap({ try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }) else { return }
        settings.removeValue(forKey: "hooks")
        if let data = try? JSONSerialization.data(withJSONObject: settings, options: .prettyPrinted) { try? data.write(to: url) }
        let alert = NSAlert(); alert.messageText = "Hooks Removed"; alert.informativeText = "All NotchCode hooks removed."; alert.runModal()
    }
}
