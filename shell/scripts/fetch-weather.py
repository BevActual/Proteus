#!/usr/bin/env python3
"""Fetch current conditions, or search for a place, via Open-Meteo.

Open-Meteo needs no API key and no account, so there is no credential to
store or leak — unlike most weather backends.

Two modes, each printing one JSON object to stdout:

  --search "<name>"          {"ok": true, "results": [{name, admin1, country,
                              countryCode, latitude, longitude, timezone}, ...]}
  --lat <f> --lon <f>        {"ok": true, "current": {...}, "today": {...},
                              "daily": [{date, high, low, sunrise, sunset,
                              code, description}, ...] }  # up to 5 days

Only the coordinates you set are sent, and only to api.open-meteo.com. Nothing
about the machine goes with them.
"""
from __future__ import annotations

import argparse
import json
import sys
import urllib.error
import urllib.parse
import urllib.request

UA = "ProteusWeather/1.0"
FORECAST_URL = "https://api.open-meteo.com/v1/forecast"
GEOCODE_URL = "https://geocoding-api.open-meteo.com/v1/search"
TIMEOUT = 20

# WMO 4677 weather codes → short label. Open-Meteo returns these as `weather_code`.
WMO = {
    0: "Clear",
    1: "Mainly clear",
    2: "Partly cloudy",
    3: "Overcast",
    45: "Fog",
    48: "Rime fog",
    51: "Light drizzle",
    53: "Drizzle",
    55: "Heavy drizzle",
    56: "Freezing drizzle",
    57: "Freezing drizzle",
    61: "Light rain",
    63: "Rain",
    65: "Heavy rain",
    66: "Freezing rain",
    67: "Freezing rain",
    71: "Light snow",
    73: "Snow",
    75: "Heavy snow",
    77: "Snow grains",
    80: "Light showers",
    81: "Showers",
    82: "Violent showers",
    85: "Snow showers",
    86: "Heavy snow showers",
    95: "Thunderstorm",
    96: "Thunderstorm, hail",
    99: "Thunderstorm, heavy hail",
}


def fail(message: str) -> int:
    print(json.dumps({"ok": False, "error": str(message)}), flush=True)
    return 1


def get_json(url: str, params: dict) -> dict:
    full = url + "?" + urllib.parse.urlencode(params)
    req = urllib.request.Request(full, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=TIMEOUT) as resp:
        return json.loads(resp.read().decode("utf-8", errors="replace"))


def describe(code: object) -> str:
    try:
        return WMO.get(int(code), "Unknown")
    except (TypeError, ValueError):
        return "Unknown"


def geocode(name: str) -> list:
    data = get_json(GEOCODE_URL, {
        "name": name,
        "count": 12,
        "language": "en",
        "format": "json",
    })
    return data.get("results") or []


def matches_qualifiers(entry: dict, qualifiers: list[str]) -> bool:
    """Does this result sit in the region/country the user also typed?"""
    haystack = " ".join(str(entry.get(k) or "") for k in ("admin1", "country", "country_code")).lower()
    return all(q in haystack for q in qualifiers)


def search(name: str) -> int:
    query = name.strip()
    if not query:
        return fail("Empty search")

    raw = geocode(query)

    # The geocoder only matches place names, so "springfield illinois" and
    # "paris france" both return nothing even though they are the most natural
    # way to disambiguate. Peel qualifier words off the end and use them to
    # filter instead, so the obvious query does the obvious thing.
    tokens = query.split()
    if not raw and len(tokens) > 1:
        for keep in range(len(tokens) - 1, 0, -1):
            candidates = geocode(" ".join(tokens[:keep]))
            if not candidates:
                continue
            qualifiers = [t.lower() for t in tokens[keep:]]
            filtered = [c for c in candidates if matches_qualifiers(c, qualifiers)]
            if filtered:
                raw = filtered
                break
            raw = raw or candidates

    results = []
    for r in raw:
        results.append({
            "name": r.get("name") or "",
            # admin1 is the state/province — the field that separates the
            # five Springfields from each other.
            "admin1": r.get("admin1") or "",
            "country": r.get("country") or "",
            "countryCode": r.get("country_code") or "",
            "latitude": r.get("latitude"),
            "longitude": r.get("longitude"),
            "timezone": r.get("timezone") or "",
        })
    print(json.dumps({"ok": True, "results": results}), flush=True)
    return 0


def forecast(lat: float, lon: float, imperial: bool) -> int:
    params = {
        "latitude": lat,
        "longitude": lon,
        "current": ",".join([
            "temperature_2m", "apparent_temperature", "relative_humidity_2m",
            "is_day", "weather_code", "wind_speed_10m",
        ]),
        "daily": ",".join([
            "weather_code",
            "temperature_2m_max",
            "temperature_2m_min",
            "sunrise",
            "sunset",
        ]),
        "forecast_days": 5,
        "timezone": "auto",
    }
    if imperial:
        params["temperature_unit"] = "fahrenheit"
        params["wind_speed_unit"] = "mph"

    data = get_json(FORECAST_URL, params)
    cur = data.get("current") or {}
    daily = data.get("daily") or {}
    units = data.get("current_units") or {}

    dates = daily.get("time") or []
    highs = daily.get("temperature_2m_max") or []
    lows = daily.get("temperature_2m_min") or []
    sunrises = daily.get("sunrise") or []
    sunsets = daily.get("sunset") or []
    codes = daily.get("weather_code") or []

    days = []
    for i, date in enumerate(dates):
        code = codes[i] if i < len(codes) else None
        days.append({
            "date": date or "",
            "high": highs[i] if i < len(highs) else None,
            "low": lows[i] if i < len(lows) else None,
            "sunrise": sunrises[i] if i < len(sunrises) else "",
            "sunset": sunsets[i] if i < len(sunsets) else "",
            "code": code,
            "description": describe(code),
        })

    today = days[0] if days else {
        "high": None,
        "low": None,
        "sunrise": "",
        "sunset": "",
    }

    out = {
        "ok": True,
        "current": {
            "temperature": cur.get("temperature_2m"),
            "apparent": cur.get("apparent_temperature"),
            "humidity": cur.get("relative_humidity_2m"),
            "windSpeed": cur.get("wind_speed_10m"),
            "isDay": bool(cur.get("is_day")),
            "code": cur.get("weather_code"),
            "description": describe(cur.get("weather_code")),
            "observedAt": cur.get("time") or "",
        },
        # Backward-compatible first-day slice for widgets / Conditions.
        "today": {
            "high": today.get("high"),
            "low": today.get("low"),
            "sunrise": today.get("sunrise") or "",
            "sunset": today.get("sunset") or "",
        },
        "daily": days,
        "units": {
            "temperature": units.get("temperature_2m") or ("°F" if imperial else "°C"),
            # Open-Meteo reports "mp/h"; normalise to the conventional spelling.
            "windSpeed": (units.get("wind_speed_10m") or "").replace("mp/h", "mph")
                         or ("mph" if imperial else "km/h"),
        },
        "timezone": data.get("timezone") or "",
    }
    print(json.dumps(out), flush=True)
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description="Proteus weather / place lookup")
    ap.add_argument("--search", default=None, help="Place name to geocode")
    ap.add_argument("--lat", type=float, default=None)
    ap.add_argument("--lon", type=float, default=None)
    ap.add_argument("--imperial", action="store_true", help="°F and mph")
    args = ap.parse_args()

    try:
        if args.search is not None:
            return search(args.search)
        if args.lat is None or args.lon is None:
            return fail("Need --search or both --lat and --lon")
        return forecast(args.lat, args.lon, args.imperial)
    except urllib.error.HTTPError as exc:
        return fail(f"HTTP {exc.code} from open-meteo")
    except urllib.error.URLError as exc:
        return fail(f"Network error: {exc.reason}")
    except (ValueError, KeyError, TypeError) as exc:
        return fail(f"Bad response: {exc}")


if __name__ == "__main__":
    sys.exit(main())
