#!/usr/bin/env python3
"""Fetch Proteus daily wallpaper from a configured feed.

Reads ~/.config/proteus/settings.json (or --settings PATH).
Writes the image under ~/.local/share/proteus/backgrounds/daily/.
Prints one JSON object to stdout:

  {"ok": true, "path": "...", "title": "...", "copyright": "", "fetchedAt": "...", "provider": "bing"}

Providers:
  bing      — Bing HPImageArchive (no key)
  unsplash  — Unsplash random photo (API key as Client-ID)
  custom    — user URL; optional {api_key} placeholder; auth none|bearer|client-id|query
              Direct image URLs or JSON with common image URL fields.

The API key is read from PROTEUS_DAILY_API_KEY (falling back to settings.json)
and is deliberately not accepted on the command line, since argv is visible to
every local process via /proc.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import sys
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

UA = "ProteusDailyWallpaper/1.0"
API_KEY_ENV = "PROTEUS_DAILY_API_KEY"


def die(msg: str, code: int = 1) -> None:
    print(json.dumps({"ok": False, "error": msg}), flush=True)
    sys.exit(code)


def load_settings(path: Path) -> dict[str, Any]:
    if not path.is_file():
        return {}
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception as e:
        die(f"settings read failed: {e}")


def http_get(url: str, headers: dict[str, str] | None = None, timeout: int = 45) -> tuple[bytes, str]:
    h = {"User-Agent": UA, "Accept": "*/*"}
    if headers:
        h.update(headers)
    req = urllib.request.Request(url, headers=h, method="GET")
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            ctype = (resp.headers.get("Content-Type") or "").split(";")[0].strip().lower()
            return resp.read(), ctype
    except urllib.error.HTTPError as e:
        body = e.read().decode("utf-8", errors="replace")[:240]
        die(f"HTTP {e.code} for {url}: {body}")
    except Exception as e:
        die(f"request failed: {e}")


def expand_url(url: str, api_key: str) -> str:
    return url.replace("{api_key}", urllib.parse.quote(api_key, safe=""))


def auth_headers(auth: str, api_key: str) -> dict[str, str]:
    key = (api_key or "").strip()
    mode = (auth or "none").strip().lower()
    if not key or mode in ("", "none"):
        return {}
    if mode == "bearer":
        return {"Authorization": f"Bearer {key}"}
    if mode in ("client-id", "client_id", "unsplash"):
        return {"Authorization": f"Client-ID {key}"}
    if mode == "query":
        return {}
    return {}


def append_query_key(url: str, api_key: str, auth: str) -> str:
    if (auth or "").strip().lower() != "query" or not (api_key or "").strip():
        return url
    parts = urllib.parse.urlsplit(url)
    q = urllib.parse.parse_qsl(parts.query, keep_blank_values=True)
    q = [(k, v) for k, v in q if k not in ("api_key", "client_id", "access_key")]
    q.append(("api_key", api_key.strip()))
    return urllib.parse.urlunsplit(
        (parts.scheme, parts.netloc, parts.path, urllib.parse.urlencode(q), parts.fragment)
    )


def pick_image_url(data: Any) -> tuple[str, str, str]:
    """Return (image_url, title, copyright) from nested JSON."""
    title = ""
    copyright_ = ""

    def walk(obj: Any) -> str | None:
        nonlocal title, copyright_
        if isinstance(obj, dict):
            for k in ("copyright", "credit", "attribution"):
                if isinstance(obj.get(k), str) and obj[k].strip() and not copyright_:
                    copyright_ = obj[k].strip()
            for k in ("title", "description", "alt_description", "name"):
                if isinstance(obj.get(k), str) and obj[k].strip() and not title:
                    title = obj[k].strip()

            # Bing
            if isinstance(obj.get("url"), str) and obj["url"].startswith("/"):
                return "https://www.bing.com" + obj["url"]
            if isinstance(obj.get("urlbase"), str) and "images" in obj:
                pass

            # Unsplash-ish
            urls = obj.get("urls")
            if isinstance(urls, dict):
                for k in ("full", "raw", "regular", "thumb"):
                    if isinstance(urls.get(k), str) and urls[k].startswith("http"):
                        return urls[k]

            for k in (
                "url",
                "image",
                "imageUrl",
                "image_url",
                "hdurl",
                "hdUrl",
                "uri",
                "href",
                "src",
            ):
                v = obj.get(k)
                if isinstance(v, str) and v.startswith("http") and _looks_like_media(v):
                    return v

            for v in obj.values():
                found = walk(v)
                if found:
                    return found
        elif isinstance(obj, list):
            for v in obj:
                found = walk(v)
                if found:
                    return found
        return None

    url = walk(data)
    if not url:
        die("could not find an image URL in feed JSON")
    return url, title, copyright_


def _looks_like_media(url: str) -> bool:
    path = urllib.parse.urlsplit(url).path.lower()
    if re.search(r"\.(jpe?g|png|webp|bmp|gif)(\?|$)", path):
        return True
    # Many CDNs omit extensions — accept http(s) that aren't obvious HTML pages
    return not path.endswith((".html", ".htm", ".php", ".aspx", ".json", ".xml"))


def ext_for(ctype: str, url: str) -> str:
    if "png" in ctype:
        return ".png"
    if "webp" in ctype:
        return ".webp"
    if "gif" in ctype:
        return ".gif"
    if "jpeg" in ctype or "jpg" in ctype:
        return ".jpg"
    path = urllib.parse.urlsplit(url).path.lower()
    m = re.search(r"\.(jpe?g|png|webp|bmp|gif)$", path)
    if m:
        return "." + m.group(1).replace("jpeg", "jpg")
    return ".jpg"


def active_source(settings: dict[str, Any]) -> dict[str, Any]:
    """Resolve the selected daily source profile (multi-source) or legacy flat fields."""
    sources = settings.get("wallpaperDailySources")
    if isinstance(sources, list) and sources:
        sid = str(settings.get("wallpaperDailySourceId") or "")
        for s in sources:
            if isinstance(s, dict) and str(s.get("id") or "") == sid:
                return s
        first = sources[0]
        return first if isinstance(first, dict) else {}
    # Legacy single-source fields
    return {
        "provider": settings.get("wallpaperDailyProvider") or "bing",
        "url": settings.get("wallpaperDailyUrl") or "",
        "apiKey": settings.get("wallpaperDailyApiKey") or "",
        "auth": settings.get("wallpaperDailyAuth") or "none",
        "market": settings.get("wallpaperDailyMarket") or "en-US",
    }


def resolve_feed(settings: dict[str, Any], overrides: dict[str, Any] | None = None) -> tuple[str, dict[str, str], str, str]:
    """Return (fetch_url, headers, title_hint, provider)."""
    src = dict(active_source(settings))
    if overrides:
        for k, v in overrides.items():
            if v is None:
                continue
            if isinstance(v, str) and not v and k not in ("url", "apiKey", "auth", "market", "provider"):
                continue
            src[k] = v

    provider = str(src.get("provider") or settings.get("wallpaperDailyProvider") or "bing").strip().lower()
    api_key = str(src.get("apiKey") if src.get("apiKey") is not None else settings.get("wallpaperDailyApiKey") or "")
    auth = str(src.get("auth") if src.get("auth") is not None else settings.get("wallpaperDailyAuth") or "none")
    custom_url = str(src.get("url") if src.get("url") is not None else settings.get("wallpaperDailyUrl") or "").strip()

    if provider == "bing":
        mkt = str(src.get("market") or settings.get("wallpaperDailyMarket") or "en-US").strip() or "en-US"
        url = f"https://www.bing.com/HPImageArchive.aspx?format=js&idx=0&n=1&mkt={urllib.parse.quote(mkt)}"
        return url, {}, "", "bing"

    if provider == "unsplash":
        if not api_key.strip():
            die("Unsplash requires an API key (Settings → Background → Daily)")
        url = custom_url or "https://api.unsplash.com/photos/random?orientation=landscape"
        url = expand_url(url, api_key)
        return url, auth_headers("client-id", api_key), "", "unsplash"

    if provider == "custom":
        if not custom_url:
            die("Custom feed needs a URL")
        url = expand_url(custom_url, api_key)
        url = append_query_key(url, api_key, auth)
        return url, auth_headers(auth, api_key), "", "custom"

    die(f"unknown wallpaperDailyProvider: {provider}")


def fetch_image(
    settings: dict[str, Any],
    cache_dir: Path,
    overrides: dict[str, Any] | None = None,
) -> dict[str, Any]:
    feed_url, headers, _hint, provider = resolve_feed(settings, overrides=overrides)
    body, ctype = http_get(feed_url, headers=headers)

    title = ""
    copyright_ = ""
    image_url = feed_url

    if ctype.startswith("image/") or (
        provider == "custom"
        and _looks_like_media(feed_url)
        and not ctype.startswith("application/json")
        and not ctype.startswith("text/")
    ):
        img_bytes = body
        img_ctype = ctype if ctype.startswith("image/") else "image/jpeg"
    else:
        # JSON / text feed
        try:
            text = body.decode("utf-8")
            data = json.loads(text)
        except Exception:
            die(f"feed is not JSON or image (content-type={ctype or 'unknown'})")

        if provider == "bing":
            images = data.get("images") if isinstance(data, dict) else None
            if not isinstance(images, list) or not images:
                die("Bing feed returned no images")
            img0 = images[0]
            rel = img0.get("url") or ""
            if not isinstance(rel, str) or not rel:
                die("Bing image missing url")
            image_url = "https://www.bing.com" + rel
            title = str(img0.get("title") or "").strip()
            copyright_ = str(img0.get("copyright") or "").strip()
        else:
            image_url, title, copyright_ = pick_image_url(data)

        img_bytes, img_ctype = http_get(image_url, headers=headers)

    cache_dir.mkdir(parents=True, exist_ok=True)
    ext = ext_for(img_ctype, image_url)
    stamp = datetime.now(timezone.utc).strftime("%Y%m%d")
    dated = cache_dir / f"{provider}-{stamp}{ext}"
    current = cache_dir / f"current{ext}"
    dated.write_bytes(img_bytes)
    current.write_bytes(img_bytes)

    # Remove other current.* variants
    for p in cache_dir.glob("current.*"):
        if p.resolve() != current.resolve():
            try:
                p.unlink()
            except OSError:
                pass

    fetched_at = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    return {
        "ok": True,
        "path": str(current),
        "title": title,
        "copyright": copyright_,
        "fetchedAt": fetched_at,
        "provider": provider,
        "sourceUrl": image_url,
    }


def main() -> None:
    ap = argparse.ArgumentParser(description="Fetch Proteus daily wallpaper")
    ap.add_argument(
        "--settings",
        default=os.path.expanduser("~/.config/proteus/settings.json"),
        help="Path to settings.json",
    )
    ap.add_argument(
        "--cache-dir",
        default=os.path.expanduser("~/.local/share/proteus/backgrounds/daily"),
        help="Directory for downloaded images",
    )
    ap.add_argument("--provider", default=None, help="Override provider (bing|unsplash|custom)")
    ap.add_argument("--url", default=None, help="Override feed/image URL")
    ap.add_argument("--auth", default=None, help="Override auth mode")
    ap.add_argument("--market", default=None, help="Override Bing market")
    args = ap.parse_args()
    # The API key arrives via the environment, never argv: /proc/<pid>/cmdline
    # is world-readable, /proc/<pid>/environ is owner-only.
    api_key = os.environ.get(API_KEY_ENV)
    settings = load_settings(Path(args.settings))
    overrides: dict[str, Any] = {}
    if args.provider is not None:
        overrides["provider"] = args.provider
    if args.url is not None:
        overrides["url"] = args.url
    if api_key is not None:
        overrides["apiKey"] = api_key
    if args.auth is not None:
        overrides["auth"] = args.auth
    if args.market is not None:
        overrides["market"] = args.market
    result = fetch_image(settings, Path(args.cache_dir), overrides=overrides or None)
    print(json.dumps(result), flush=True)


if __name__ == "__main__":
    main()
