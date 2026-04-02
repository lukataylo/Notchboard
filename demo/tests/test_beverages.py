"""Tests for the beverage tracker."""
from src.beverages import BeverageTracker, BEVERAGE_BUDGET_PER_PERSON


def test_order_drink():
    tracker = BeverageTracker()
    order = tracker.order("matcha_latte", 2, "alice")
    assert order.total == 13.00  # 6.50 * 2
    assert order.person == "alice"


def test_person_total():
    tracker = BeverageTracker()
    tracker.order("matcha_latte", 1, "alice")
    tracker.order("cold_brew", 1, "alice")
    assert tracker.person_total("alice") == 11.50  # 6.50 + 5.00


def test_over_budget():
    tracker = BeverageTracker()
    # Order enough to exceed $150 per person budget
    for _ in range(25):
        tracker.order("matcha_latte", 1, "bob")  # 25 * 6.50 = 162.50
    assert tracker.is_over_budget("bob")


def test_matcha_vs_coffee():
    tracker = BeverageTracker()
    tracker.order("matcha_latte", 10, "alice")  # 65.00
    tracker.order("drip_coffee", 10, "bob")     # 35.00
    result = tracker.matcha_vs_coffee()
    assert result["winner"] == "matcha"
    assert result["matcha"] > result["coffee"]


def test_unknown_drink():
    tracker = BeverageTracker()
    try:
        tracker.order("kombucha", 1, "carol")
        assert False, "Should have raised ValueError"
    except ValueError:
        pass


def test_monthly_report():
    tracker = BeverageTracker()
    tracker.order("oat_matcha", 3, "alice")
    tracker.order("espresso", 5, "bob")
    report = tracker.monthly_report()
    assert "Beverage Report" in report
    assert "Winner" in report
