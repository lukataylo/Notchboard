# The Notchboard

**AI coding agents can't see each other. The Notchboard fixes that.**

Two AI agents on the same codebase will silently stomp on each other's files. There's no coordination protocol, no shared awareness, nothing. The Notchboard is an MCP server and macOS app that gives any AI agent real-time awareness of every other agent — file locks, shared context, conflict prevention — all visible live in your MacBook's notch.

It took two agents from destructive to collaborative with **zero changes to the agents themselves**.

<p align="center">
  <strong>Claude Code</strong> (orange) and <strong>Cursor</strong> (purple) working on the same project.<br/>
  The Notchboard sits between them — watching, coordinating, preventing conflicts.
</p>

---

## The Problem

You're running Claude Code in your terminal refactoring `auth.py`. Meanwhile, Cursor is open in the same repo, and you ask it to also touch `auth.py`. Neither agent knows the other exists. Both edit the same file. One overwrites the other. You lose work.

This happens constantly when developers use multiple AI coding tools. There's no standard way for agents to discover each other, claim files, or share what they've learned.

## The Solution

The Notchboard is a **coordination runtime** that works with any MCP-compatible agent. It provides:

- **Conflict Prevention** — When Agent A is editing a file, Agent B gets blocked with a rich explanation of who owns the file, what they're doing, and how to coordinate. The blocked agent can autonomously pivot to a different task.
- **Agent Discovery** — Any agent can call `list_active_agents` to see every other agent's status, project, progress, and current thinking.
- **Shared Context** — Agents post findings to a shared scratchpad (`share_context`) that other agents read (`read_context`). "Auth uses JWT tokens, see auth.py" — now every agent knows.
- **File Locking** — Explicit `claim_file` / `release_file` protocol. First-come, first-served. Stale locks auto-expire.

All of this is visible in real-time in a dashboard that lives in your MacBook's notch area.

---

## How It Works

```
Claude Code / Cursor                    The Notchboard                     Any MCP Agent
       │                                      │                                  │
       │──── hook: pre-tool-use ─────────────▶│                                  │
       │                                      │ check file locks                 │
       │                                      │ conflict? → block + explain      │
       │◀──── {"decision":"approve/block"} ───│                                  │
       │                                      │                                  │
       │                                      │◀── list_active_agents ───────────│
       │                                      │──── agent status + reasoning ───▶│
       │                                      │                                  │
       │                                      │◀── share_context ───────────────│
       │                                      │◀── read_context ────────────────│
       │                                      │──── shared findings ────────────▶│
```

Three layers:

1. **Observation** — A lightweight hook intercepts every tool call from Claude Code and Cursor. The hook auto-detects which agent called it. If the Notchboard isn't running, everything auto-approves — zero disruption.

2. **Coordination** — When an agent tries to write a file, the engine checks if another agent already claimed it. If there's a conflict, the blocked agent receives a structured explanation: who owns the file, what they're doing, and how to use MCP tools to coordinate. The agent can autonomously read shared context and pivot — no human intervention needed.

3. **MCP Server** — A stdio MCP server that any agent can connect to. Eight tools for discovery, file coordination, and context sharing. Works with Claude Code, Cursor, and anything else that speaks MCP.

---

## MCP Tools

| Tool | Description |
|------|-------------|
| `list_active_agents` | See all running AI agents — type, project, status, progress, current reasoning |
| `get_agent_status` | Detailed status of a specific agent session |
| `claim_file` | Acquire exclusive write access to a file |
| `release_file` | Release your claim so other agents can edit |
| `get_file_activity` | Check who has claimed or recently edited a file |
| `share_context` | Post a finding for other agents ("auth uses JWT, see auth.py") |
| `read_context` | Read what other agents have shared |
| `get_conflicts` | List recent file conflicts between agents |

Any MCP-compatible agent gets multi-agent coordination for free by connecting one server.

---

## The Notch UI

The dashboard lives in your MacBook's notch (or as a floating pill on external monitors).

**Collapsed** — Shows the active agent's icon, current status, and a progress ring. Flashes a red triangle when there's a conflict.

**Expanded** (press `Cmd+Shift+N`) — Full coordination dashboard:
- **Stats bar** — Conflicts prevented, files coordinated, context entries shared
- **Conflict visualization** — Two agent icons connected by a red line over the filename, with Allow/Block buttons
- **Session list** — All active agents with type badges, progress rings, and durations
- **Live task feed** — Every tool call as it happens (Read, Edit, Bash, Grep...)
- **Claude's reasoning** — What Claude is thinking, streamed from the transcript
- **Token usage** — Input/output token counts
- **Message input** — Type a message to Claude Code directly from the notch

---

## Install

```bash
git clone https://github.com/lukataylo/Notchboard.git
cd Notchboard
chmod +x install.sh
./install.sh
```

This builds a release binary, creates `Notchboard.app`, copies it to `/Applications`, and launches it.

### Setup

1. Look for the `</>` icon in your menu bar
2. Click it → **Install Hooks** (adds hooks to `~/.claude/settings.json`)
3. Click it → **Install MCP Server** (adds server to `~/.claude/mcp.json`)
4. Start using Claude Code and/or Cursor — activity streams automatically

### Requirements

- macOS 13 (Ventura) or later
- Swift 5.9+
- Zero external dependencies

---

## Demo

### Quick simulated demo (no agents needed)

```bash
cd notchcode-demo
./test_hooks.sh
```

Simulates two agents (Claude Code + Cursor) building **TacoOverflow** — a taco recipe app. Claude refactors `taco_ranker.py`, Cursor tries to edit the same file, conflict fires, MCP tools coordinate.

### Full integration tests

```bash
cd notchcode-demo
./test_full.sh
```

30 tests covering hooks, conflict detection, MCP tools, edge cases, and stats tracking.

### Live demo with real agents

1. Open Claude Code: `cd notchcode-demo && claude`
2. Ask Claude: *"Look at src/taco_ranker.py — add ghost_pepper and carolina_reaper to SALSA_TYPES, add a salsa_bias parameter to rank_tacos(), and run the tests."*
3. Open Cursor in the same directory
4. Ask Cursor: *"Refactor rank_tacos in src/taco_ranker.py to use a weighted spice_factor formula."*
5. Watch the Notchboard detect the conflict in real-time (`Cmd+Shift+N`)

---

## Architecture

```
Sources/NotchCode/
├── main.swift              # Entry point
├── Models.swift            # AgentType, AgentSession, TaskItem, NotchState
├── AgentProvider.swift     # BaseAgentProvider (shared event processing), registry, event model
├── ClaudeCodeProvider.swift # Claude Code: hooks, transcripts, process detection
├── CursorProvider.swift    # Cursor: workspace detection, hook events
├── Coordination.swift      # File locks, conflict detection, decisions, shared context, stats
├── MCPServer.swift         # Python MCP server generator + installer
├── TranscriptReader.swift  # Claude transcript tailing for reasoning + tokens
├── Views.swift             # Collapsed/expanded notch views, conflict visualization, stats bar
├── Components.swift        # ProgressRing, progressColor
├── Shapes.swift            # ClaudeCodeIcon, CursorIcon, NotchCodeIcon, NotchCollapsedShape
├── Infrastructure.swift    # Panels, hotkey, menu bar, AppDelegate
├── Settings.swift          # Preferences + launch agent
└── Info.plist              # Bundle metadata
```

~1,500 lines of Swift. Zero dependencies. One Python MCP server script (~250 lines).

---

## Why This Is a Runtime Primitive

The Notchboard isn't a product — it's infrastructure. The file lock protocol, shared context bus, and agent discovery layer work with **any** MCP-compatible agent. Claude Code and Cursor are just the first two. The protocol is:

1. Agent connects to `notchcode-switchboard` MCP server
2. Agent calls `claim_file` before editing, `release_file` when done
3. Agent calls `read_context` to see what others have shared
4. Agent calls `list_active_agents` to discover who's working on what

No SDK. No agent modifications. No vendor lock-in. Just one MCP server that makes every agent aware of every other agent.

---

Built with Swift, SwiftUI, and the MCP protocol. Runs in your MacBook's notch.
