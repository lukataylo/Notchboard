import Foundation
import os.log

private let log = Logger(subsystem: "com.notchcode", category: "mcp")

/// Manages the MCP server binary that agents connect to for coordination.
/// The MCP server is a Python script that reads state from ~/.notchcode/mcp_state.json
/// and provides tools via JSON-RPC over stdio.
class MCPServerManager {
    let scriptPath: URL
    let statePath: URL

    init() {
        let base = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".notchcode")
        scriptPath = base.appendingPathComponent("bin/notchcode-mcp")
        statePath = base.appendingPathComponent("mcp_state.json")
    }

    func writeMCPServer() {
        let base = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".notchcode")
        try? FileManager.default.createDirectory(at: base.appendingPathComponent("bin"), withIntermediateDirectories: true)

        let script = #"""
#!/usr/bin/env python3
"""NotchCode MCP Server — Multi-Agent Coordination Protocol.

Provides tools for AI agents to discover each other, coordinate file access,
and share context through the NotchCode switchboard.

Runs as a stdio MCP server that agents connect to via their MCP configuration.
"""
import json, sys, os, time, uuid
from pathlib import Path

BASE = Path.home() / ".notchcode"
STATE_FILE = BASE / "mcp_state.json"
CONTEXT_FILE = BASE / "context.json"
DECISIONS_DIR = BASE / "decisions"
LOCKS_FILE = BASE / "file_locks.json"

def read_state():
    try:
        return json.loads(STATE_FILE.read_text())
    except:
        return {"agents": [], "file_locks": [], "context_entries": [], "recent_conflicts": []}

def read_context():
    try:
        entries = json.loads(CONTEXT_FILE.read_text())
        # Filter to last hour
        cutoff = time.time() - 3600
        return [e for e in entries if _parse_ts(e.get("timestamp", "")) > cutoff]
    except:
        return []

def write_context(entries):
    CONTEXT_FILE.write_text(json.dumps(entries, default=str))

def _parse_ts(ts):
    try:
        from datetime import datetime, timezone
        return datetime.fromisoformat(ts.replace("Z", "+00:00")).timestamp()
    except:
        return 0

def read_locks():
    try:
        return json.loads(LOCKS_FILE.read_text())
    except:
        return {}

def write_locks(locks):
    LOCKS_FILE.write_text(json.dumps(locks, default=str))

def _write_mcp_conflict(file_path, blocked_agent, owner_lock):
    """Write a conflict event so the Notchboard UI displays it."""
    conflict_dir = BASE / "events" / "mcp"
    conflict_dir.mkdir(parents=True, exist_ok=True)
    event = {
        "type": "mcp_conflict",
        "file_path": file_path,
        "file_name": os.path.basename(file_path),
        "blocked_agent": blocked_agent,
        "owner_agent": owner_lock.get("agent_name", "unknown"),
        "owner_type": owner_lock.get("agent_type", "unknown"),
        "timestamp": time.time()
    }
    event_file = conflict_dir / f"conflict-{int(time.time()*1000)}.json"
    event_file.write_text(json.dumps(event))

# --- MCP Protocol ---

TOOLS = [
    {
        "name": "list_active_agents",
        "description": "List all currently active AI coding agents monitored by NotchCode. Returns each agent's type, project, status, and progress.",
        "inputSchema": {"type": "object", "properties": {}, "required": []}
    },
    {
        "name": "get_agent_status",
        "description": "Get detailed status of a specific agent session by name.",
        "inputSchema": {
            "type": "object",
            "properties": {"session_name": {"type": "string", "description": "Name of the agent session"}},
            "required": ["session_name"]
        }
    },
    {
        "name": "claim_file",
        "description": "Claim exclusive access to a file. Other agents will be warned if they try to edit it. Returns success or conflict info.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "file_path": {"type": "string", "description": "Absolute path to the file to claim"},
                "agent_name": {"type": "string", "description": "Your agent/session name for identification"}
            },
            "required": ["file_path", "agent_name"]
        }
    },
    {
        "name": "release_file",
        "description": "Release your claim on a file so other agents can edit it.",
        "inputSchema": {
            "type": "object",
            "properties": {"file_path": {"type": "string", "description": "Absolute path to the file to release"}},
            "required": ["file_path"]
        }
    },
    {
        "name": "get_file_activity",
        "description": "Check which agents have claimed or recently edited a file.",
        "inputSchema": {
            "type": "object",
            "properties": {"file_path": {"type": "string", "description": "Absolute path to check"}},
            "required": ["file_path"]
        }
    },
    {
        "name": "share_context",
        "description": "Share a finding or note with other agents working on the same codebase. This is visible to all agents via the NotchCode switchboard.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "message": {"type": "string", "description": "The context to share (e.g. 'auth uses JWT tokens, see src/auth.ts')"},
                "agent_name": {"type": "string", "description": "Your agent/session name"}
            },
            "required": ["message", "agent_name"]
        }
    },
    {
        "name": "read_context",
        "description": "Read shared context from other agents. Returns recent notes and findings shared through the NotchCode switchboard.",
        "inputSchema": {"type": "object", "properties": {}, "required": []}
    },
    {
        "name": "get_conflicts",
        "description": "List recent file conflicts between agents.",
        "inputSchema": {"type": "object", "properties": {}, "required": []}
    }
]

def handle_tool(name, args):
    state = read_state()

    if name == "list_active_agents":
        agents = state.get("agents", [])
        if not agents:
            return "No active agents detected. Make sure NotchCode is running and hooks are installed."
        lines = []
        for a in agents:
            status = "⏳ waiting" if a.get("is_waiting") else f"▶ {a.get('status', 'unknown')}"
            lines.append(f"• {a['agent_type']} [{a['session_name']}] — {a['project_path']}\n  Status: {status} | Progress: {int(a.get('progress', 0)*100)}% | Duration: {a.get('duration', '?')}")
            if a.get("last_reasoning"):
                lines.append(f"  Thinking: {a['last_reasoning'][:100]}")
        return "\n".join(lines)

    elif name == "get_agent_status":
        sname = args.get("session_name", "")
        for a in state.get("agents", []):
            if a["session_name"].lower() == sname.lower():
                return json.dumps(a, indent=2)
        return f"No agent found with session name '{sname}'. Active sessions: {[a['session_name'] for a in state.get('agents', [])]}"

    elif name == "claim_file":
        fp = args["file_path"]
        agent = args.get("agent_name", "unknown")
        locks = read_locks()
        if fp in locks:
            existing = locks[fp]
            # Check if stale (>5 min)
            if time.time() - existing.get("claimed_at", 0) < 300:
                # Write a conflict event so the Notchboard UI shows it
                _write_mcp_conflict(fp, agent, existing)
                return f"⚠️ CONFLICT: '{fp}' is already claimed by {existing['agent_name']} ({existing.get('agent_type', '?')}). Wait for them to finish or coordinate. Use read_context for details."
        locks[fp] = {"agent_name": agent, "agent_type": "unknown", "claimed_at": time.time()}
        write_locks(locks)
        return f"✅ Claimed '{os.path.basename(fp)}'. Other agents will be warned if they try to edit it."

    elif name == "release_file":
        fp = args["file_path"]
        locks = read_locks()
        if fp in locks:
            del locks[fp]
            write_locks(locks)
            return f"Released claim on '{os.path.basename(fp)}'."
        return f"No claim found for '{fp}'."

    elif name == "get_file_activity":
        fp = args["file_path"]
        locks = read_locks()
        state_locks = state.get("file_locks", [])
        results = []
        if fp in locks:
            l = locks[fp]
            results.append(f"Claimed by: {l['agent_name']} (via MCP)")
        for l in state_locks:
            if l["file_path"] == fp:
                results.append(f"Locked by: {l['agent_type']} [{l['session_name']}] since {l['claimed_at']}")
        if not results:
            return f"No activity on '{os.path.basename(fp)}'. Safe to edit."
        return "\n".join(results)

    elif name == "share_context":
        msg = args["message"]
        agent = args.get("agent_name", "unknown")
        entries = read_context()
        entries.append({
            "id": str(uuid.uuid4()),
            "agent_type": "unknown",
            "session_name": agent,
            "message": msg,
            "timestamp": time.strftime("%Y-%m-%dT%H:%M:%S+00:00")
        })
        # Keep last 50
        entries = entries[-50:]
        write_context(entries)
        return f"✅ Shared with all agents: \"{msg[:80]}{'...' if len(msg)>80 else ''}\""

    elif name == "read_context":
        entries = read_context()
        state_entries = state.get("context_entries", [])
        all_entries = entries + state_entries
        if not all_entries:
            return "No shared context yet. Use share_context to post findings for other agents."
        # Deduplicate by id
        seen = set()
        unique = []
        for e in all_entries:
            eid = e.get("id", "")
            if eid not in seen:
                seen.add(eid)
                unique.append(e)
        lines = []
        for e in unique[-20:]:
            lines.append(f"[{e.get('session_name', '?')}] {e['message']}")
        return "\n".join(lines)

    elif name == "get_conflicts":
        conflicts = state.get("recent_conflicts", [])
        if not conflicts:
            return "No recent conflicts. All agents are working independently."
        lines = [f"• {c['file']} — {c['agents']} at {c['time']}" for c in conflicts[-10:]]
        return "\n".join(lines)

    return f"Unknown tool: {name}"

def main():
    """MCP stdio server — reads JSON-RPC from stdin, writes to stdout."""
    while True:
        try:
            line = sys.stdin.readline()
            if not line:
                break
            msg = json.loads(line.strip())
        except (json.JSONDecodeError, ValueError):
            continue
        except EOFError:
            break

        method = msg.get("method", "")
        mid = msg.get("id")

        if method == "initialize":
            resp = {
                "jsonrpc": "2.0", "id": mid,
                "result": {
                    "protocolVersion": "2024-11-05",
                    "capabilities": {"tools": {"listChanged": False}},
                    "serverInfo": {"name": "notchcode-switchboard", "version": "1.0.0"}
                }
            }
        elif method == "notifications/initialized":
            continue  # No response needed for notifications
        elif method == "tools/list":
            resp = {"jsonrpc": "2.0", "id": mid, "result": {"tools": TOOLS}}
        elif method == "tools/call":
            params = msg.get("params", {})
            tool_name = params.get("name", "")
            tool_args = params.get("arguments", {})
            try:
                result_text = handle_tool(tool_name, tool_args)
                resp = {
                    "jsonrpc": "2.0", "id": mid,
                    "result": {"content": [{"type": "text", "text": result_text}]}
                }
            except Exception as e:
                resp = {
                    "jsonrpc": "2.0", "id": mid,
                    "error": {"code": -1, "message": str(e)}
                }
        elif method == "ping":
            resp = {"jsonrpc": "2.0", "id": mid, "result": {}}
        else:
            if mid is not None:
                resp = {"jsonrpc": "2.0", "id": mid, "error": {"code": -32601, "message": f"Unknown method: {method}"}}
            else:
                continue  # Skip unknown notifications

        sys.stdout.write(json.dumps(resp) + "\n")
        sys.stdout.flush()

if __name__ == "__main__":
    main()
"""#
        try? script.write(to: scriptPath, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptPath.path)
        log.info("MCP server script written to \(self.scriptPath.path)")
    }

    /// Generate the MCP config snippet users add to their claude_desktop_config.json or .claude.json
    func mcpConfigSnippet() -> String {
        return """
        {
          "mcpServers": {
            "notchcode-switchboard": {
              "command": "\(scriptPath.path)",
              "args": []
            }
          }
        }
        """
    }

    /// Install MCP server config into Claude Code and Cursor
    func installMCPConfig() {
        let serverEntry: [String: Any] = [
            "command": scriptPath.path,
            "args": [] as [String]
        ]

        // Claude Code: ~/.claude/mcp.json
        installMCPInto(
            path: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/mcp.json"),
            serverEntry: serverEntry
        )

        // Cursor: ~/Library/Application Support/Cursor/User/globalStorage/rooveterinaryinc.roo-cline/settings/mcp_settings.json
        // Also try the standard Cursor MCP path
        let cursorMCP = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Cursor/User/globalStorage/cursor-mcp/mcp.json")
        installMCPInto(path: cursorMCP, serverEntry: serverEntry)

        // Cursor also reads from ~/.cursor/mcp.json in some versions
        let cursorHome = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".cursor/mcp.json")
        installMCPInto(path: cursorHome, serverEntry: serverEntry)
    }

    private func installMCPInto(path: URL, serverEntry: [String: Any]) {
        var existing: [String: Any] = [:]
        if let data = try? Data(contentsOf: path),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            existing = json
        }

        var servers = existing["mcpServers"] as? [String: Any] ?? [:]
        servers["notchcode-switchboard"] = serverEntry
        existing["mcpServers"] = servers

        if let data = try? JSONSerialization.data(withJSONObject: existing, options: .prettyPrinted) {
            try? FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: path)
        }
    }
}
