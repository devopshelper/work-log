"""Date conversion tests: run with 'pytest -q'."""

import datetime as dt

from app import dates


def test_known_nowruz_dates():
    assert dates.parse_jalali("1403/01/01") == dt.date(2024, 3, 20)
    assert dates.parse_jalali("1402/01/01") == dt.date(2023, 3, 21)
    assert dates.parse_jalali("1405/01/01") == dt.date(2026, 3, 21)


def test_roundtrip_every_day_for_five_years():
    day = dt.date(2024, 1, 1)
    end = dt.date(2028, 12, 31)
    while day <= end:
        assert dates.parse_jalali(dates.jalali_string(day)) == day
        day += dt.timedelta(days=1)


def test_persian_digits_are_accepted():
    assert dates.parse_jalali("۱۴۰۵/۰۸/۱۸") == dt.date(2026, 11, 9)


def test_dashes_are_accepted():
    assert dates.parse_jalali("1405-8-18") == dt.date(2026, 11, 9)


def test_describe_labels():
    info = dates.describe(dt.date(2026, 11, 9))
    assert info["jalali"] == "1405/08/18"
    assert info["gregorian"] == "2026-11-09"
    assert info["month_fa"] == "آبان"
    assert info["weekday_fa"] == "دوشنبه"


def test_invalid_input_raises():
    for bad in ["", "1405/13/40", "not-a-date", "1405/08"]:
        try:
            dates.parse_jalali(bad)
        except ValueError:
            continue
        raise AssertionError(f"expected ValueError for {bad!r}")
