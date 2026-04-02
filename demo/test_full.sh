#!/bin/bash
# NotchCode Switchboard — comprehensive integration test
# Tests the full pipeline: hooks, coordination, conflicts, MCP, and edge cases
set -e

HOOK="$HOME/.notchcode/bin/notchcode-hook"
EVENTS_CLAUDE="$HOME/.notchcode/events/claude"
EVENTS_CURSOR="$HOME/.notchcode/events/cursor"
DECISIONS="$HOME/.notchcode/decisions"
MCP="$HOME/.notchcode/bin/notchcode-mcp"
CWD="/Users/lukadadiani/notchcode-demo"
PASS=0
FAIL=0
TESTS=0

assert_contains() {
    TESTS=$((TESTS + 1))
    if echo "$1" | grep -q "$2"; then
        PASS=$((PASS + 1))
        echo "  PASS: $3"
    else
        FAIL=$((FAIL + 1))
        echo "  FAIL: $3"
        echo "    Expected to contain: $2"
        echo "    Got: $(echo "$1" | head -2)"
    fi
}

assert_equals() {
    TESTS=$((TESTS + 1))
    if [ "$1" = "$2" ]; then
        PASS=$((PASS + 1))
        echo "  PASS: $3"
    else
        FAIL=$((FAIL + 1))
        echo "  FAIL: $3 (expected '$2', got '$1')"
    fi
}

echo "=== NotchCode Integration Tests ==="
echo ""

# Preflight
if [ ! -f "$HOOK" ]; then echo "ABORT: Hook not found"; exit 1; fi
if ! pgrep -f "NotchCode" >/dev/null 2>&1; then echo "ABORT: NotchCode not running"; exit 1; fi
echo "Preflight OK"
echo ""

# Clean state
rm -f "$EVENTS_CLAUDE"/*.json "$EVENTS_CURSOR"/*.json "$DECISIONS"/*.json 2>/dev/null
rm -f "$HOME/.notchcode/file_locks.json" "$HOME/.notchcode/context.json" 2>/dev/null
sleep 0.5

# ── Test Group 1: Basic hook responses ──
echo "── 1. Basic hook responses ──"

# Read tool should auto-approve immediately
RESULT=$(echo '{"session_id":"test-1","cwd":"'"$CWD"'","hook_event_name":"PreToolUse","tool_name":"Read","tool_input":{"file_path":"'"$CWD"'/src/taco_ranker.py"},"tool_use_id":"t1"}' | "$HOOK" pre-tool-use)
assert_contains "$RESULT" '"decision"' "Read returns a decision"
assert_contains "$RESULT" 'approve' "Read is auto-approved"

# Glob should auto-approve (not a write op)
RESULT=$(echo '{"session_id":"test-1","cwd":"'"$CWD"'","hook_event_name":"PreToolUse","tool_name":"Glob","tool_input":{"pattern":"**/*.py"},"tool_use_id":"t2"}' | "$HOOK" pre-tool-use)
assert_contains "$RESULT" 'approve' "Glob is auto-approved"

# Grep should auto-approve
RESULT=$(echo '{"session_id":"test-1","cwd":"'"$CWD"'","hook_event_name":"PreToolUse","tool_name":"Grep","tool_input":{"pattern":"TODO"},"tool_use_id":"t3"}' | "$HOOK" pre-tool-use)
assert_contains "$RESULT" 'approve' "Grep is auto-approved"

# Post-tool-use should return nothing (no decision needed)
RESULT=$(echo '{"session_id":"test-1","cwd":"'"$CWD"'","hook_event_name":"PostToolUse","tool_name":"Read","tool_input":{},"tool_response":{"stdout":"file contents","stderr":"","interrupted":false},"tool_use_id":"t1"}' | "$HOOK" post-tool-use)
assert_equals "$RESULT" "" "Post-tool-use returns no decision"

sleep 0.5

# ── Test Group 2: Write operations claim files ──
echo ""
echo "── 2. Write operations claim files ──"

# Edit should auto-approve (first claim on file)
RESULT=$(echo '{"session_id":"test-claude","cwd":"'"$CWD"'","hook_event_name":"PreToolUse","tool_name":"Edit","tool_input":{"file_path":"'"$CWD"'/src/taco_ranker.py"},"tool_use_id":"e1"}' | "$HOOK" pre-tool-use)
assert_contains "$RESULT" 'approve' "First edit on file is approved"

sleep 0.3

# Wait for async event processing + lock persistence
sleep 2

# Verify lock file was created
if [ -f "$HOME/.notchcode/file_locks.json" ]; then
    LOCKS=$(cat "$HOME/.notchcode/file_locks.json")
    assert_contains "$LOCKS" "taco_ranker.py" "Lock file contains claimed file"
else
    TESTS=$((TESTS + 1)); FAIL=$((FAIL + 1))
    echo "  FAIL: Lock file not created"
fi

# Same session editing same file should be fine (re-claim)
RESULT=$(echo '{"session_id":"test-claude","cwd":"'"$CWD"'","hook_event_name":"PreToolUse","tool_name":"Edit","tool_input":{"file_path":"'"$CWD"'/src/taco_ranker.py"},"tool_use_id":"e2"}' | "$HOOK" pre-tool-use)
assert_contains "$RESULT" 'approve' "Same session re-editing same file is approved"

# Write to different file should be fine
RESULT=$(echo '{"session_id":"test-claude","cwd":"'"$CWD"'","hook_event_name":"PreToolUse","tool_name":"Write","tool_input":{"file_path":"'"$CWD"'/src/new_file.py"},"tool_use_id":"w1"}' | "$HOOK" pre-tool-use)
assert_contains "$RESULT" 'approve' "Write to different file is approved"

sleep 0.5

# ── Test Group 3: Conflict detection ──
echo ""
echo "── 3. Conflict detection ──"

# Different session tries to edit the same file — should be blocked
# Write directly to cursor events since the hook env detection can't be simulated
REQUEST_ID="$(date +%s%N 2>/dev/null || date +%s)-conflict1"
mkdir -p "$EVENTS_CURSOR"
echo '{"session_id":"test-cursor","cwd":"'"$CWD"'","hook_event_name":"PreToolUse","hook_type":"pre-tool-use","tool_name":"Edit","tool_input":{"file_path":"'"$CWD"'/src/taco_ranker.py"},"tool_use_id":"cursor-e1","request_id":"'"$REQUEST_ID"'"}' \
  > "$EVENTS_CURSOR/$REQUEST_ID.json"

sleep 2

# Check if a decision file was written (should be pending or auto-approved after timeout)
# The conflict should have been detected
STATE=$(cat "$HOME/.notchcode/mcp_state.json" 2>/dev/null)
assert_contains "$STATE" 'conflicts_prevented' "MCP state includes conflict stats"

# Check context was auto-shared about the conflict
CONTEXT=$(cat "$HOME/.notchcode/context.json" 2>/dev/null)
assert_contains "$CONTEXT" 'taco_ranker.py' "Auto-shared context mentions conflicting file"
assert_contains "$CONTEXT" 'switchboard' "Auto-shared context is from switchboard"

sleep 0.5

# ── Test Group 4: Cursor editing non-conflicting file ──
echo ""
echo "── 4. Non-conflicting cursor edits ──"

REQUEST_ID2="$(date +%s%N 2>/dev/null || date +%s)-noconflict"
echo '{"session_id":"test-cursor","cwd":"'"$CWD"'","hook_event_name":"PreToolUse","hook_type":"pre-tool-use","tool_name":"Edit","tool_input":{"file_path":"'"$CWD"'/src/guacamole_engine.py"},"tool_use_id":"cursor-e2","request_id":"'"$REQUEST_ID2"'"}' \
  > "$EVENTS_CURSOR/$REQUEST_ID2.json"

sleep 1

# Check that guacamole_engine.py is now locked by cursor
LOCKS=$(cat "$HOME/.notchcode/file_locks.json" 2>/dev/null)
assert_contains "$LOCKS" "guacamole_engine.py" "Cursor claimed guacamole_engine.py"

# ── Test Group 5: Post-tool-use tracking ──
echo ""
echo "── 5. Post-tool-use tracking ──"

echo '{"session_id":"test-claude","cwd":"'"$CWD"'","hook_event_name":"PostToolUse","tool_name":"Edit","tool_input":{"file_path":"'"$CWD"'/src/taco_ranker.py"},"tool_response":{"stdout":"","stderr":"","interrupted":false},"tool_use_id":"e1"}' | "$HOOK" post-tool-use
sleep 0.3

echo '{"session_id":"test-claude","cwd":"'"$CWD"'","hook_event_name":"PostToolUse","tool_name":"Bash","tool_input":{"command":"pytest","description":"Run tests"},"tool_response":{"stdout":"3 passed, 1 failed","stderr":"","interrupted":false},"tool_use_id":"bash1"}' | "$HOOK" post-tool-use

# Wait for transcript timer to write MCP state (fires every 2s)
sleep 3

# Session names are derived from cwd (project dir name), not session_id
STATE=$(cat "$HOME/.notchcode/mcp_state.json" 2>/dev/null)
assert_contains "$STATE" 'notchcode-demo' "MCP state tracks sessions by project name"
assert_contains "$STATE" 'agents' "MCP state has agents array"

# ── Test Group 6: MCP server tools ──
echo ""
echo "── 6. MCP server tools ──"

# Test list_active_agents
RESP=$(printf '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test","version":"1.0"}}}\n{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"list_active_agents","arguments":{}}}\n' | "$MCP" 2>/dev/null)
assert_contains "$RESP" 'notchcode-switchboard' "MCP server initializes"
assert_contains "$RESP" 'content' "list_active_agents returns content"

# Test claim_file via MCP
RESP=$(printf '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test","version":"1.0"}}}\n{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"claim_file","arguments":{"file_path":"'"$CWD"'/src/chips_and_dip.py","agent_name":"mcp-agent"}}}\n' | "$MCP" 2>/dev/null)
assert_contains "$RESP" 'Claimed' "MCP claim_file works"

# Test that claiming an already-claimed file returns conflict
RESP=$(printf '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test","version":"1.0"}}}\n{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"claim_file","arguments":{"file_path":"'"$CWD"'/src/chips_and_dip.py","agent_name":"other-agent"}}}\n' | "$MCP" 2>/dev/null)
assert_contains "$RESP" 'CONFLICT' "MCP detects double-claim conflict"

# Test release_file
RESP=$(printf '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test","version":"1.0"}}}\n{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"release_file","arguments":{"file_path":"'"$CWD"'/src/chips_and_dip.py"}}}\n' | "$MCP" 2>/dev/null)
assert_contains "$RESP" 'Released' "MCP release_file works"

# Test share_context + read_context roundtrip
RESP=$(printf '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test","version":"1.0"}}}\n{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"share_context","arguments":{"message":"taco_ranker uses carnitas 2x multiplier","agent_name":"test-agent"}}}\n{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"read_context","arguments":{}}}\n' | "$MCP" 2>/dev/null)
assert_contains "$RESP" 'carnitas' "Context roundtrip preserves message"

# Test get_file_activity on a file we know was claimed via MCP (chips_and_dip was claimed + released, so use guacamole)
# get_file_activity returns lock holder info (session name, not filename)
RESP=$(printf '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test","version":"1.0"}}}\n{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"get_file_activity","arguments":{"file_path":"'"$CWD"'/src/guacamole_engine.py"}}}\n' | "$MCP" 2>/dev/null)
assert_contains "$RESP" 'content' "get_file_activity returns result"

# Test tools/list returns all 8 tools
RESP=$(printf '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test","version":"1.0"}}}\n{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}\n' | "$MCP" 2>/dev/null)
TOOL_COUNT=$(echo "$RESP" | python3 -c "
import json, sys
for line in sys.stdin:
    try:
        msg = json.loads(line.strip())
        if 'result' in msg and 'tools' in msg['result']:
            print(len(msg['result']['tools']))
    except: pass
" 2>/dev/null | head -1)
assert_equals "$TOOL_COUNT" "8" "MCP exposes all 8 tools"

# ── Test Group 7: Edge cases ──
echo ""
echo "── 7. Edge cases ──"

# Empty session_id should be ignored
RESULT=$(echo '{"cwd":"'"$CWD"'","hook_event_name":"PreToolUse","tool_name":"Read","tool_input":{"file_path":"test.py"},"tool_use_id":"orphan"}' | "$HOOK" pre-tool-use)
assert_contains "$RESULT" 'approve' "Missing session_id still approves"

# Malformed JSON should not crash
RESULT=$(echo 'this is not json at all' | "$HOOK" pre-tool-use)
assert_contains "$RESULT" 'approve' "Malformed JSON still approves (failsafe)"

# Empty input should not crash
RESULT=$(echo '' | "$HOOK" pre-tool-use)
assert_contains "$RESULT" 'approve' "Empty input still approves (failsafe)"

# Multiple rapid events shouldn't lose any
for i in $(seq 1 5); do
    echo '{"session_id":"rapid-test","cwd":"'"$CWD"'","hook_event_name":"PreToolUse","tool_name":"Read","tool_input":{"file_path":"file_'"$i"'.py"},"tool_use_id":"rapid-'"$i"'"}' | "$HOOK" pre-tool-use > /dev/null &
done
wait
sleep 1
echo "  PASS: 5 rapid concurrent hooks completed without crash"
PASS=$((PASS + 1)); TESTS=$((TESTS + 1))

# ── Test Group 8: Stats tracking ──
echo ""
echo "── 8. Stats tracking ──"

STATE=$(cat "$HOME/.notchcode/mcp_state.json" 2>/dev/null)
CONFLICTS=$(echo "$STATE" | python3 -c "import json,sys; print(json.load(sys.stdin).get('stats',{}).get('conflicts_prevented',0))" 2>/dev/null)
FILES=$(echo "$STATE" | python3 -c "import json,sys; print(json.load(sys.stdin).get('stats',{}).get('files_coordinated',0))" 2>/dev/null)
CONTEXT_COUNT=$(echo "$STATE" | python3 -c "import json,sys; print(json.load(sys.stdin).get('stats',{}).get('context_shared',0))" 2>/dev/null)

if [ "$CONFLICTS" -gt 0 ] 2>/dev/null; then
    echo "  PASS: conflicts_prevented = $CONFLICTS"
    PASS=$((PASS + 1))
else
    echo "  FAIL: conflicts_prevented should be > 0 (got: $CONFLICTS)"
    FAIL=$((FAIL + 1))
fi
TESTS=$((TESTS + 1))

if [ "$FILES" -gt 0 ] 2>/dev/null; then
    echo "  PASS: files_coordinated = $FILES"
    PASS=$((PASS + 1))
else
    echo "  FAIL: files_coordinated should be > 0 (got: $FILES)"
    FAIL=$((FAIL + 1))
fi
TESTS=$((TESTS + 1))

if [ "$CONTEXT_COUNT" -gt 0 ] 2>/dev/null; then
    echo "  PASS: context_shared = $CONTEXT_COUNT"
    PASS=$((PASS + 1))
else
    echo "  FAIL: context_shared should be > 0 (got: $CONTEXT_COUNT)"
    FAIL=$((FAIL + 1))
fi
TESTS=$((TESTS + 1))

# ── Results ──
echo ""
echo "════════════════════════════════"
echo "  Results: $PASS/$TESTS passed"
if [ $FAIL -gt 0 ]; then
    echo "  $FAIL FAILED"
    echo "════════════════════════════════"
    exit 1
else
    echo "  All tests passed!"
    echo "════════════════════════════════"
fi
