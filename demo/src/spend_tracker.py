"""BurnRate — Spend tracker for startups that burn through cash and matcha lattes.

Tracks team spending by category, enforces budgets, and generates reports
so your CFO can cry with actual data.
"""

from datetime import datetime

CATEGORIES = ["engineering", "marketing", "office", "travel"]

# Monthly budget caps per category (USD)
BUDGETS = {
    "engineering": 15000,
    "marketing": 8000,
    "office": 3000,
    "travel": 5000,
}


class Expense:
    def __init__(self, amount: float, category: str, description: str, submitter: str):
        self.amount = amount
        self.category = category
        self.description = description
        self.submitter = submitter
        self.submitted_at = datetime.now()
        self.approved = False

    def __repr__(self):
        status = "approved" if self.approved else "pending"
        return f"Expense(${self.amount:.2f}, {self.category}, {status})"


class SpendTracker:
    def __init__(self):
        self.expenses: list[Expense] = []

    def submit(self, amount: float, category: str, description: str, submitter: str) -> Expense:
        if category not in CATEGORIES:
            raise ValueError(f"Unknown category: {category}. Valid: {CATEGORIES}")
        if amount <= 0:
            raise ValueError("Expense amount must be positive")
        expense = Expense(amount, category, description, submitter)
        self.expenses.append(expense)
        return expense

    def approve(self, expense: Expense) -> bool:
        total = self.category_total(expense.category) + expense.amount
        if total > BUDGETS.get(expense.category, 0):
            return False  # Over budget
        expense.approved = True
        return True

    def category_total(self, category: str) -> float:
        return sum(e.amount for e in self.expenses if e.category == category and e.approved)

    def budget_remaining(self, category: str) -> float:
        return BUDGETS.get(category, 0) - self.category_total(category)

    def top_spenders(self, limit: int = 5) -> list[tuple[str, float]]:
        totals: dict[str, float] = {}
        for e in self.expenses:
            if e.approved:
                totals[e.submitter] = totals.get(e.submitter, 0) + e.amount
        return sorted(totals.items(), key=lambda x: x[1], reverse=True)[:limit]


# TODO: add beverage tracking — matcha and coffee are killing the office budget
# TODO: add recurring expense support
# TODO: generate monthly PDF reports
# TODO: Slack notifications when a category hits 80% budget
