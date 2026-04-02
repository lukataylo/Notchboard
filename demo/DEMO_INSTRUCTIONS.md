# Notchboard Demo — BurnRate Spend Tracker

## The Scenario

Two AI agents are building **BurnRate**, a spend tracker for startups. The codebase has a shared `beverages.py` module that tracks the team's matcha and coffee spend (the hidden line item that destroys startup budgets).

- **Claude Code** is updating the matcha tracking — raising the per-person budget and adding a matcha intervention alert
- **Cursor** is adding new coffee drinks to the same module

Both agents need to edit `beverages.py`. The Notchboard catches the conflict.

---

## Pre-flight

1. Notchboard is running — `</>` icon in menu bar
2. Hooks installed — menu bar → Install Hooks
3. MCP server installed — menu bar → Install MCP Server
4. `Cmd+Shift+N` opens/closes the notch panel

---

## Quick Simulated Demo (no agents needed)

```bash
cd /Users/lukadadiani/notchcode-demo
./test_hooks.sh
```

Runs the full scenario in ~15 seconds with simulated events. Press `Cmd+Shift+N` to watch.

---

## Live Demo with Real Agents

### Step 1: Open Claude Code

```bash
cd /Users/lukadadiani/notchcode-demo
claude
```

Orange session appears in the notch.

### Step 2: Give Claude the matcha task

```
Look at src/beverages.py — there are TODOs at the bottom. I need you to:
1. Raise BEVERAGE_BUDGET_PER_PERSON from $150 to $200
2. Add a MATCHA_INTERVENTION_THRESHOLD constant at $100
3. Add a method needs_matcha_intervention(person) that returns True if their matcha spend exceeds the threshold
4. Create a new file src/slack_alerts.py that sends a Slack message when someone triggers the matcha intervention
5. Run the tests in tests/test_beverages.py
```

Watch the notch — Claude reads files, edits beverages.py, creates slack_alerts.py, runs tests.

### Step 3: Open Cursor

```bash
cursor /Users/lukadadiani/notchcode-demo
```

Purple session appears in the notch.

### Step 4: Give Cursor the coffee task (this creates the conflict)

Open Cursor's chat (`Cmd+L`) or Composer (`Cmd+I`):

```
Open src/beverages.py and add two new drinks to DRINK_PRICES: "nitro_cold_brew" at $6.00 and "pour_over" at $5.50. Also add a method coffee_addiction_score(person) that returns a score based on how many coffee drinks they've ordered.
```

**This is the conflict moment** — Cursor tries to edit `beverages.py` which Claude already claimed.

Press `Cmd+Shift+N` to see:
- The conflict visualization with both agent icons and a red line
- Allow/Block buttons
- Stats updating (conflicts prevented count goes up)

### Step 5: Non-conflicting parallel work

After resolving the conflict, give them tasks on different files:

**Claude Code:**
```
Look at src/reports.py and add a beverage_report() function that generates an ASCII chart of matcha vs coffee spending per team member. Run tests/test_spend_tracker.py.
```

**Cursor:**
```
Open src/spend_tracker.py and add a "beverages" category to CATEGORIES and BUDGETS with a $2000 monthly budget. Also add a method forecast_monthly_burn() that estimates the month-end total based on current spend rate.
```

Different files — both agents work simultaneously, no conflict.

---

## What to Point Out to Judges

1. **The conflict visual** — two agent icons connected by a red line over the filename
2. **The stats bar** — "X conflicts prevented, Y files coordinated, Z context shared"
3. **Auto-shared context** — when the conflict fires, the Notchboard auto-posts context so Cursor can read it via MCP and pivot autonomously
4. **The block reason** — the blocked agent gets a rich JSON response explaining who owns the file and how to coordinate
5. **Zero agent modifications** — neither Claude Code nor Cursor was changed. The Notchboard works by sitting between them.

### The 30-Second Pitch

"AI coding agents are blind to each other. Two agents on the same repo will stomp on each other's files. The Notchboard is an MCP server that gives any agent real-time awareness of every other agent — file locks, shared context, conflict prevention — all visible in your MacBook's notch. It took two agents from destructive to collaborative with zero changes to the agents themselves."
