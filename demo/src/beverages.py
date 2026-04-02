"""Beverage spend tracking — the hidden line item that destroys startup budgets.

Tracks matcha, coffee, and other caffeinated expenses that somehow
end up being 40% of the office budget.
"""

from datetime import datetime

DRINK_PRICES = {
    "matcha_latte": 6.50,
    "oat_matcha": 7.00,
    "drip_coffee": 3.50,
    "cold_brew": 5.00,
    "espresso": 4.00,
    "chai_latte": 5.50,
}

# Monthly beverage budget per person (USD)
BEVERAGE_BUDGET_PER_PERSON = 150.00


class BeverageExpense:
    def __init__(self, drink: str, quantity: int, person: str):
        self.drink = drink
        self.quantity = quantity
        self.person = person
        self.unit_price = DRINK_PRICES.get(drink, 5.00)
        self.total = self.unit_price * quantity
        self.timestamp = datetime.now()

    def __repr__(self):
        return f"{self.person}: {self.quantity}x {self.drink} (${self.total:.2f})"


class BeverageTracker:
    def __init__(self):
        self.orders: list[BeverageExpense] = []

    def order(self, drink: str, quantity: int, person: str) -> BeverageExpense:
        if drink not in DRINK_PRICES:
            raise ValueError(f"Unknown drink: {drink}. We're not that fancy.")
        expense = BeverageExpense(drink, quantity, person)
        self.orders.append(expense)
        return expense

    def person_total(self, person: str) -> float:
        return sum(o.total for o in self.orders if o.person == person)

    def is_over_budget(self, person: str) -> bool:
        return self.person_total(person) > BEVERAGE_BUDGET_PER_PERSON

    def matcha_vs_coffee(self) -> dict:
        """The eternal debate, settled with data."""
        matcha = sum(o.total for o in self.orders if "matcha" in o.drink)
        coffee = sum(o.total for o in self.orders if o.drink in ["drip_coffee", "cold_brew", "espresso"])
        return {"matcha": matcha, "coffee": coffee, "winner": "matcha" if matcha > coffee else "coffee"}

    def biggest_spender(self) -> tuple[str, float]:
        totals: dict[str, float] = {}
        for o in self.orders:
            totals[o.person] = totals.get(o.person, 0) + o.total
        if not totals:
            return ("nobody", 0.0)
        return max(totals.items(), key=lambda x: x[1])

    def monthly_report(self) -> str:
        total = sum(o.total for o in self.orders)
        stats = self.matcha_vs_coffee()
        top = self.biggest_spender()
        return (
            f"Beverage Report\n"
            f"  Total: ${total:.2f}\n"
            f"  Matcha: ${stats['matcha']:.2f} | Coffee: ${stats['coffee']:.2f}\n"
            f"  Winner: {stats['winner']}\n"
            f"  Top spender: {top[0]} (${top[1]:.2f})"
        )


# TODO: add team-wide matcha intervention alerts
# TODO: track caffeine intake per person (health & safety)
# TODO: integrate with spend_tracker.py office category
