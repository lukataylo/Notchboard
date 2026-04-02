#!/bin/bash
# Notchboard Demo — simulates two agents building BurnRate, a startup spend tracker
# Run from this directory: ./test_hooks.sh

set -e

HOOK="$HOME/.notchcode/bin/notchcode-hook"
EVENTS_CLAUDE="$HOME/.notchcode/events/claude"
EVENTS_CURSOR="$HOME/.notchcode/events/cursor"
DECISIONS="$HOME/.notchcode/decisions"
MCP="$HOME/.notchcode/bin/notchcode-mcp"
CWD="/Users/lukadadiani/notchcode-demo"

echo "=== Notchboard Demo ==="
echo ""

# Check prerequisites
if [ ! -f "$HOOK" ]; then
    echo "ERROR: Hook script not found at $HOOK"
    echo "Open Notchboard menu bar → Install Hooks first."
    exit 1
fi

if ! pgrep -f "NotchCode" >/dev/null 2>&1; then
    echo "ERROR: Notchboard is not running. Launch it first."
    exit 1
fi

echo "✓ Hook script found"
echo "✓ Notchboard is running"
echo ""

# Clean up old events
rm -f "$EVENTS_CLAUDE"/*.json "$EVENTS_CURSOR"/*.json "$DECISIONS"/*.json 2>/dev/null

# ─────────────────────────────────────────────────────
# Scene: Two agents are building BurnRate — a spend tracker for startups.
# Claude Code is adding matcha latte tracking to the beverages module.
# Cursor is adding coffee spend tracking to the same module.
# They're about to fight over beverages.py.
# ─────────────────────────────────────────────────────

echo "💸 SCENARIO: Building BurnRate — the spend tracker for startups that burn cash"
echo "   Claude Code: adding matcha latte tracking"
echo "   Cursor: adding coffee spend tracking"
echo ""
sleep 1

# --- Act 1: Claude reads the codebase ---
echo "── Act 1: Claude Code reviews the codebase ──"
echo '{"session_id":"claude-burnrate","cwd":"'"$CWD"'","hook_event_name":"PreToolUse","tool_name":"Read","tool_input":{"file_path":"'"$CWD"'/src/spend_tracker.py"},"tool_use_id":"read-1","transcript_path":""}' \
  | "$HOOK" pre-tool-use > /dev/null
sleep 0.3
echo '{"session_id":"claude-burnrate","cwd":"'"$CWD"'","hook_event_name":"PostToolUse","tool_name":"Read","tool_input":{"file_path":"'"$CWD"'/src/spend_tracker.py"},"tool_response":{"stdout":"class SpendTracker:\n    def submit(self, amount, category, description, submitter)...","stderr":"","interrupted":false},"tool_use_id":"read-1"}' \
  | "$HOOK" post-tool-use
echo "  Claude reads spend_tracker.py"
sleep 0.5

echo '{"session_id":"claude-burnrate","cwd":"'"$CWD"'","hook_event_name":"PreToolUse","tool_name":"Grep","tool_input":{"pattern":"TODO|matcha|coffee","file_path":"'"$CWD"'/src/"},"tool_use_id":"grep-1"}' \
  | "$HOOK" pre-tool-use > /dev/null
sleep 0.3
echo '{"session_id":"claude-burnrate","cwd":"'"$CWD"'","hook_event_name":"PostToolUse","tool_name":"Grep","tool_input":{"pattern":"TODO|matcha|coffee"},"tool_response":{"stdout":"beverages.py:89: # TODO: add team-wide matcha intervention alerts\nbeverages.py:91: # TODO: integrate with spend_tracker.py office category","stderr":"","interrupted":false},"tool_use_id":"grep-1"}' \
  | "$HOOK" post-tool-use
echo "  Claude greps for TODOs — finds matcha intervention alert needed"
sleep 0.5

# --- Act 2: Claude starts editing beverages.py ---
echo ""
echo "── Act 2: Claude Code updates the matcha tracking in beverages.py ──"
echo '{"session_id":"claude-burnrate","cwd":"'"$CWD"'","hook_event_name":"PreToolUse","tool_name":"Edit","tool_input":{"file_path":"'"$CWD"'/src/beverages.py","old_string":"BEVERAGE_BUDGET_PER_PERSON = 150.00","new_string":"BEVERAGE_BUDGET_PER_PERSON = 200.00\nMATCHA_INTERVENTION_THRESHOLD = 100.00"},"tool_use_id":"edit-1"}' \
  | "$HOOK" pre-tool-use > /dev/null
echo "  Claude claims beverages.py — raising matcha budget to \$200 and adding intervention threshold"
sleep 0.5
echo '{"session_id":"claude-burnrate","cwd":"'"$CWD"'","hook_event_name":"PostToolUse","tool_name":"Edit","tool_input":{"file_path":"'"$CWD"'/src/beverages.py"},"tool_response":{"stdout":"","stderr":"","interrupted":false},"tool_use_id":"edit-1"}' \
  | "$HOOK" post-tool-use
sleep 0.5

echo '{"session_id":"claude-burnrate","cwd":"'"$CWD"'","hook_event_name":"PreToolUse","tool_name":"Write","tool_input":{"file_path":"'"$CWD"'/src/slack_alerts.py"},"tool_use_id":"write-1"}' \
  | "$HOOK" pre-tool-use > /dev/null
sleep 0.3
echo '{"session_id":"claude-burnrate","cwd":"'"$CWD"'","hook_event_name":"PostToolUse","tool_name":"Write","tool_input":{"file_path":"'"$CWD"'/src/slack_alerts.py"},"tool_response":{"stdout":"","stderr":"","interrupted":false},"tool_use_id":"write-1"}' \
  | "$HOOK" post-tool-use
echo "  Claude creates slack_alerts.py for matcha intervention notifications"
sleep 0.5

# --- Act 3: Cursor enters the scene ---
echo ""
echo "── Act 3: Cursor starts adding coffee tracking ──"
REQUEST_ID1="$(date +%s%N 2>/dev/null || date +%s)-cursor1"
mkdir -p "$EVENTS_CURSOR"
echo '{"session_id":"cursor-burnrate","cwd":"'"$CWD"'","hook_event_name":"PostToolUse","hook_type":"post-tool-use","tool_name":"Read","tool_input":{"file_path":"'"$CWD"'/src/spend_tracker.py"},"tool_response":{"stdout":"class SpendTracker:...","stderr":"","interrupted":false},"tool_use_id":"cursor-read-1","request_id":"'"$REQUEST_ID1"'"}' \
  > "$EVENTS_CURSOR/$REQUEST_ID1.json"
echo "  Cursor reads spend_tracker.py"
sleep 1

REQUEST_ID2="$(date +%s%N 2>/dev/null || date +%s)-cursor2"
echo '{"session_id":"cursor-burnrate","cwd":"'"$CWD"'","hook_event_name":"PostToolUse","hook_type":"post-tool-use","tool_name":"Write","tool_input":{"file_path":"'"$CWD"'/src/coffee_dashboard.py"},"tool_response":{"stdout":"","stderr":"","interrupted":false},"tool_use_id":"cursor-write-1","request_id":"'"$REQUEST_ID2"'"}' \
  > "$EVENTS_CURSOR/$REQUEST_ID2.json"
echo "  Cursor creates coffee_dashboard.py (no conflict — different file)"
sleep 1

# --- Act 4: THE CONFLICT — Cursor tries to edit beverages.py ---
echo ""
echo "── Act 4: Cursor tries to edit beverages.py — CONFLICT! ──"
echo "   Claude is already in there updating the matcha budget..."
echo ""
CONFLICT_ID="$(date +%s%N 2>/dev/null || date +%s)-fight"
echo '{"session_id":"cursor-burnrate","cwd":"'"$CWD"'","hook_event_name":"PreToolUse","hook_type":"pre-tool-use","tool_name":"Edit","tool_input":{"file_path":"'"$CWD"'/src/beverages.py","old_string":"DRINK_PRICES = {","new_string":"DRINK_PRICES = {\n    \"nitro_cold_brew\": 6.00,\n    \"pour_over\": 5.50,"},"tool_use_id":"cursor-edit-conflict","request_id":"'"$CONFLICT_ID"'"}' \
  > "$EVENTS_CURSOR/$CONFLICT_ID.json"
echo "  ☕ vs 🍵 CONFLICT: Both agents want to edit beverages.py!"
echo "  Claude is adding matcha alerts, Cursor wants to add coffee drinks"
echo "  → Press ⌘⇧N to see the conflict in the notch"
echo "  → Click Allow or Block (auto-approves in 12s)"
sleep 3

# --- Act 5: Claude runs the tests ---
echo ""
echo "── Act 5: Claude runs the test suite ──"
echo '{"session_id":"claude-burnrate","cwd":"'"$CWD"'","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"python -m pytest tests/ -v","description":"Run spend tracker tests"},"tool_use_id":"bash-1"}' \
  | "$HOOK" pre-tool-use > /dev/null
sleep 0.5
echo '{"session_id":"claude-burnrate","cwd":"'"$CWD"'","hook_event_name":"PostToolUse","tool_name":"Bash","tool_input":{"command":"python -m pytest tests/ -v","description":"Run spend tracker tests"},"tool_response":{"stdout":"test_submit_expense PASSED\ntest_approve_within_budget PASSED\ntest_reject_over_budget PASSED\ntest_matcha_vs_coffee PASSED\ntest_over_budget FAILED — matcha budget increased to $200","stderr":"","interrupted":false},"tool_use_id":"bash-1"}' \
  | "$HOOK" post-tool-use
echo "  Tests: 4 passed, 1 failed (matcha budget was raised, test expected \$150)"
sleep 0.5

# --- Act 6: MCP coordination ---
echo ""
echo "── Act 6: Testing Notchboard MCP tools ──"
if [ -f "$MCP" ]; then
    RESPONSE=$(printf '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test","version":"1.0"}}}\n{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"list_active_agents","arguments":{}}}\n{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"share_context","arguments":{"message":"beverages.py BEVERAGE_BUDGET_PER_PERSON raised to $200 and MATCHA_INTERVENTION_THRESHOLD added at $100. Tests need updating.","agent_name":"claude-burnrate"}}}\n{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"read_context","arguments":{}}}\n{"jsonrpc":"2.0","id":6,"method":"tools/call","params":{"name":"claim_file","arguments":{"file_path":"'"$CWD"'/src/reports.py","agent_name":"cursor-burnrate"}}}\n{"jsonrpc":"2.0","id":7,"method":"tools/call","params":{"name":"get_file_activity","arguments":{"file_path":"'"$CWD"'/src/beverages.py"}}}\n{"jsonrpc":"2.0","id":8,"method":"tools/call","params":{"name":"get_conflicts","arguments":{}}}\n' | "$MCP" 2>/dev/null)

    echo "$RESPONSE" | python3 -c "
import json, sys
labels = {1:'init', 3:'list_active_agents', 4:'share_context', 5:'read_context', 6:'claim_file', 7:'get_file_activity', 8:'get_conflicts'}
for line in sys.stdin:
    line = line.strip()
    if not line: continue
    try:
        msg = json.loads(line)
        mid = msg.get('id', '?')
        label = labels.get(mid, '?')
        if 'result' in msg:
            r = msg['result']
            if 'serverInfo' in r:
                print(f'  ✓ [{label}] Server: {r[\"serverInfo\"][\"name\"]} v{r[\"serverInfo\"][\"version\"]}')
            elif 'content' in r:
                text = r['content'][0]['text']
                lines = text.split(chr(10))
                print(f'  ✓ [{label}] {lines[0]}')
                for l in lines[1:]:
                    print(f'       {l}')
            else:
                print(f'  ✓ [{label}] OK')
        elif 'error' in msg:
            print(f'  ✗ [{label}] ERROR: {msg[\"error\"][\"message\"]}')
    except:
        pass
" 2>/dev/null
    echo ""
else
    echo "  MCP server not found. Install from menu bar → Install MCP Server"
fi

echo ""
echo "=== Demo Complete ==="
echo ""
echo "What you should see in the notch (⌘⇧N to expand):"
echo "  • claude-burnrate (orange) — edited beverages.py, created slack_alerts.py"
echo "  • cursor-burnrate (purple) — created coffee_dashboard.py, tried to edit beverages.py"
echo "  • Conflict on beverages.py (matcha vs coffee — the eternal startup debate)"
echo "  • Stats: conflicts prevented, files coordinated, context shared"
echo ""
echo "The key moment: Cursor got blocked from editing beverages.py because Claude"
echo "was already updating the matcha budget. The Notchboard auto-shared context"
echo "so Cursor knows WHY it was blocked and can pivot to a different file."
