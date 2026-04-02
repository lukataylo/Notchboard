"""Report generation for BurnRate spend tracker.

Generates summaries, alerts, and charts (ok, just ASCII charts)
for the finance team to panic over.
"""

from src.spend_tracker import SpendTracker, BUDGETS


def budget_status(tracker: SpendTracker) -> list[dict]:
    """Returns budget status for each category."""
    statuses = []
    for category, budget in BUDGETS.items():
        spent = tracker.category_total(category)
        remaining = budget - spent
        pct = (spent / budget * 100) if budget > 0 else 0
        statuses.append({
            "category": category,
            "budget": budget,
            "spent": spent,
            "remaining": remaining,
            "percent_used": round(pct, 1),
            "alert": pct >= 80,
        })
    return statuses


def burn_rate_summary(tracker: SpendTracker) -> str:
    """Generate a plain text burn rate summary."""
    lines = ["=== BurnRate Monthly Summary ===", ""]
    total_spent = sum(e.amount for e in tracker.expenses if e.approved)
    total_budget = sum(BUDGETS.values())

    for status in budget_status(tracker):
        bar_len = int(status["percent_used"] / 5)
        bar = "█" * bar_len + "░" * (20 - bar_len)
        alert = " ⚠️" if status["alert"] else ""
        lines.append(
            f"  {status['category']:12s} [{bar}] "
            f"${status['spent']:>8,.2f} / ${status['budget']:>8,.2f} "
            f"({status['percent_used']}%){alert}"
        )

    lines.append("")
    lines.append(f"  Total: ${total_spent:,.2f} / ${total_budget:,.2f}")

    top = tracker.top_spenders(3)
    if top:
        lines.append("")
        lines.append("  Top spenders:")
        for name, amount in top:
            lines.append(f"    {name}: ${amount:,.2f}")

    return "\n".join(lines)


# TODO: add Slack webhook integration for budget alerts
# TODO: add CSV export
# TODO: add forecast based on current burn rate
