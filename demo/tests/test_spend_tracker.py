"""Tests for the spend tracker."""
from src.spend_tracker import SpendTracker, BUDGETS


def test_submit_expense():
    tracker = SpendTracker()
    expense = tracker.submit(100, "engineering", "AWS bill", "alice")
    assert expense.amount == 100
    assert expense.category == "engineering"
    assert not expense.approved


def test_approve_within_budget():
    tracker = SpendTracker()
    expense = tracker.submit(500, "office", "Standing desks", "bob")
    assert tracker.approve(expense)
    assert expense.approved


def test_reject_over_budget():
    tracker = SpendTracker()
    # Fill up the office budget
    for i in range(6):
        e = tracker.submit(500, "office", f"Furniture #{i}", "bob")
        tracker.approve(e)
    # This should be rejected (3000 budget, already spent 3000)
    over = tracker.submit(500, "office", "More furniture", "bob")
    assert not tracker.approve(over)


def test_budget_remaining():
    tracker = SpendTracker()
    e = tracker.submit(1000, "marketing", "Google ads", "carol")
    tracker.approve(e)
    assert tracker.budget_remaining("marketing") == 7000


def test_invalid_category():
    tracker = SpendTracker()
    try:
        tracker.submit(50, "snacks", "Chips", "dave")
        assert False, "Should have raised ValueError"
    except ValueError:
        pass


def test_top_spenders():
    tracker = SpendTracker()
    for name, amount in [("alice", 5000), ("bob", 3000), ("carol", 8000)]:
        e = tracker.submit(amount, "engineering", "Stuff", name)
        tracker.approve(e)
    top = tracker.top_spenders(2)
    assert top[0][0] == "carol"
    assert len(top) == 2
