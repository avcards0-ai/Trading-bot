"""Number formatting shared by the scorer's sentences and the web pages."""

from __future__ import annotations


def pct(value: float | None, digits: int = 0) -> str:
    if value is None:
        return "–"
    return f"{value * 100:.{digits}f}%"


def money(value: float | None) -> str:
    if value is None:
        return "–"
    sign = "-" if value < 0 else ""
    value = abs(value)
    for size, suffix in ((1e12, "T"), (1e9, "B"), (1e6, "M"), (1e3, "K")):
        if value >= size:
            return f"{sign}${value / size:.1f}{suffix}"
    return f"{sign}${value:,.0f}"


def price(value: float | None) -> str:
    return "–" if value is None else f"${value:,.2f}"


def times(value: float | None, digits: int = 1) -> str:
    return "–" if value is None else f"{value:.{digits}f}×"
