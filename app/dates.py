"""Gregorian <-> Jalali (Solar Hijri) date helpers.

The conversion is implemented in pure Python (a port of the well known
jalaali algorithm) so the app needs no extra calendar dependency. Jalali
dates are represented as plain (year, month, day) tuples and formatted as
YYYY/MM/DD.
"""

from __future__ import annotations

import datetime as dt
from typing import Tuple

JALALI_MONTHS = [
    "فروردین",
    "اردیبهشت",
    "خرداد",
    "تیر",
    "مرداد",
    "شهریور",
    "مهر",
    "آبان",
    "آذر",
    "دی",
    "بهمن",
    "اسفند",
]

# Python's weekday() starts on Monday; the Persian week starts on Saturday.
_WEEKDAYS_FA = {
    5: "شنبه",
    6: "یکشنبه",
    0: "دوشنبه",
    1: "سه‌شنبه",
    2: "چهارشنبه",
    3: "پنجشنبه",
    4: "جمعه",
}

_BREAKS = [
    -61, 9, 38, 199, 426, 686, 756, 818, 1111, 1181,
    1210, 1635, 2060, 2097, 2192, 2262, 2324, 2394, 2456, 3178,
]


def _div(a: int, b: int) -> int:
    """Truncating integer division (matches the reference algorithm)."""
    return int(a / b)


def _mod(a: int, b: int) -> int:
    return a - _div(a, b) * b


def _jal_cal(jy: int) -> Tuple[int, int, int]:
    """Return (leap, gregorian_year, march_day) for a Jalali year."""
    gy = jy + 621
    leap_j = -14
    jp = _BREAKS[0]
    jump = 0
    for jm in _BREAKS[1:]:
        jump = jm - jp
        if jy < jm:
            break
        leap_j += _div(jump, 33) * 8 + _div(_mod(jump, 33), 4)
        jp = jm

    n = jy - jp
    leap_j += _div(n, 33) * 8 + _div(_mod(n, 33) + 3, 4)
    if _mod(jump, 33) == 4 and jump - n == 4:
        leap_j += 1

    leap_g = _div(gy, 4) - _div((_div(gy, 100) + 1) * 3, 4) - 150
    march = 20 + leap_j - leap_g

    if jump - n < 6:
        n = n - jump + _div(jump + 4, 33) * 33

    leap = _mod(_mod(n + 1, 33) - 1, 4)
    if leap == -1:
        leap = 4

    return leap, gy, march


def _g2d(gy: int, gm: int, gd: int) -> int:
    """Gregorian date -> Julian day number."""
    d = _div((gy + _div(gm - 8, 6) + 100100) * 1461, 4)
    d += _div(153 * _mod(gm + 9, 12) + 2, 5)
    d += gd - 34840408
    d -= _div(_div(gy + 100100 + _div(gm - 8, 6), 100) * 3, 4) - 752
    return d


def _d2g(jdn: int) -> Tuple[int, int, int]:
    """Julian day number -> Gregorian (year, month, day)."""
    j = 4 * jdn + 139361631
    j += _div(_div(4 * jdn + 183187720, 146097) * 3, 4) * 4 - 3908
    i = _div(_mod(j, 1461), 4) * 5 + 308
    gd = _div(_mod(i, 153), 5) + 1
    gm = _mod(_div(i, 153), 12) + 1
    gy = _div(j, 1461) - 100100 + _div(8 - gm, 6)
    return gy, gm, gd


def _j2d(jy: int, jm: int, jd: int) -> int:
    """Jalali date -> Julian day number."""
    _, gy, march = _jal_cal(jy)
    return _g2d(gy, 3, march) + (jm - 1) * 31 - _div(jm, 7) * (jm - 7) + jd - 1


def _d2j(jdn: int) -> Tuple[int, int, int]:
    """Julian day number -> Jalali (year, month, day)."""
    gy = _d2g(jdn)[0]
    jy = gy - 621
    leap, _, march = _jal_cal(jy)
    jdn1f = _g2d(gy, 3, march)
    k = jdn - jdn1f

    if k >= 0:
        if k <= 185:
            return jy, 1 + _div(k, 31), _mod(k, 31) + 1
        k -= 186
    else:
        jy -= 1
        k += 179
        if leap == 1:
            k += 1

    return jy, 7 + _div(k, 30), _mod(k, 30) + 1


def gregorian_to_jalali(value: dt.date) -> Tuple[int, int, int]:
    """Convert a datetime.date to a Jalali (year, month, day) tuple."""
    return _d2j(_g2d(value.year, value.month, value.day))


def jalali_to_gregorian(jy: int, jm: int, jd: int) -> dt.date:
    """Convert a Jalali date to datetime.date."""
    if not (1 <= jm <= 12 and 1 <= jd <= 31):
        raise ValueError("invalid Jalali month/day")
    gy, gm, gd = _d2g(_j2d(jy, jm, jd))
    return dt.date(gy, gm, gd)


def jalali_string(value: dt.date) -> str:
    """Format the Jalali date of a Gregorian date as YYYY/MM/DD."""
    jy, jm, jd = gregorian_to_jalali(value)
    return f"{jy}/{jm:02d}/{jd:02d}"


def parse_jalali(text: str) -> dt.date:
    """Parse 1403/05/02 (accepts dashes and Persian digits too)."""
    if not text:
        raise ValueError("empty Jalali date")

    normalised = _to_ascii_digits(text.strip()).replace("-", "/").replace(".", "/")
    parts = [p for p in normalised.split("/") if p != ""]
    if len(parts) != 3:
        raise ValueError(f"could not parse Jalali date: {text!r}")

    jy, jm, jd = (int(p) for p in parts)
    return jalali_to_gregorian(jy, jm, jd)


def _to_ascii_digits(text: str) -> str:
    """Translate Persian/Arabic-Indic digits to ASCII digits."""
    return text.translate(
        str.maketrans(
            "۰۱۲۳۴۵۶۷۸۹٠١٢٣٤٥٦٧٨٩",
            "01234567890123456789",
        )
    )


def weekday_fa(value: dt.date) -> str:
    """Persian weekday name for a Gregorian date."""
    return _WEEKDAYS_FA[value.weekday()]


def month_fa(month: int) -> str:
    """Persian name of a Jalali month (1-12)."""
    return JALALI_MONTHS[month - 1]


def long_jalali(value: dt.date) -> str:
    """Human readable Jalali date such as: دوشنبه ۱۸ آبان ۱۴۰۵."""
    jy, jm, jd = gregorian_to_jalali(value)
    year = _to_persian_digits(str(jy))
    day = _to_persian_digits(str(jd))
    return f"{weekday_fa(value)} {day} {month_fa(jm)} {year}"


def _to_persian_digits(text: str) -> str:
    return text.translate(str.maketrans("0123456789", "۰۱۲۳۴۵۶۷۸۹"))


def describe(value: dt.date) -> dict:
    """Bundle every representation of a date the templates need."""
    jy, jm, jd = gregorian_to_jalali(value)
    return {
        "gregorian": value.isoformat(),
        "jalali": f"{jy}/{jm:02d}/{jd:02d}",
        "jalali_short": f"{_to_persian_digits(str(jd))} {month_fa(jm)}",
        "jalali_long": long_jalali(value),
        "jalali_year": jy,
        "jalali_month": jm,
        "jalali_day": jd,
        "month_fa": month_fa(jm),
        "weekday_fa": weekday_fa(value),
    }
