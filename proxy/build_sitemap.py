#!/usr/bin/env python3
"""Build proxy/sitemap.xml from a Wiki.js public page list.

Internal/placeholder pages stay on the site but are omitted from the sitemap.
The Article Template (/about/article-template) is one of those: it is a
starter outline for new entries, not a public article.

Usage:
  python3 build_sitemap.py pages.json [out.xml]

pages.json is a list of Wiki.js page objects with path, isPublished,
isPrivate, and updatedAt. The static /studies/ index is always included.
The wiki path "home" is emitted as https://biohackerwiki.com/.
"""
from __future__ import annotations

import json, sys
from datetime import datetime, timezone
from pathlib import Path

# Keep these pages published; do not list them in sitemap.xml.
EXCLUDE_PATHS = frozenset({
    "about/article-template",
})

HOME = "https://biohackerwiki.com"
STUDIES_INDEX = "studies/"


def day(iso: str | None) -> str:
    if not iso:
        return datetime.now(timezone.utc).date().isoformat()
    # Wiki.js timestamps are UTC with a Z or offset.
    t = iso.replace("Z", "+00:00")
    return datetime.fromisoformat(t).date().isoformat()


def loc_for(path: str) -> str:
    if path in ("", "home"):
        return f"{HOME}/"
    return f"{HOME}/{path}"


def entries(pages: list[dict]) -> list[tuple[str, str]]:
    out = []
    seen = set()

    def add(url: str, lastmod: str):
        if url not in seen:
            seen.add(url)
            out.append((url, lastmod))

    # Home
    home = next((p for p in pages if p.get("path") == "home"), None)
    add(f"{HOME}/", day(home.get("updatedAt") if home else None))

    for p in pages:
        if not p.get("isPublished") or p.get("isPrivate"):
            continue
        path = (p.get("path") or "").strip("/")
        if not path or path == "home" or path in EXCLUDE_PATHS:
            continue
        add(loc_for(path), day(p.get("updatedAt")))

    # Static studies browser index (not a Wiki.js page)
    add(f"{HOME}/{STUDIES_INDEX}", day(None))
    out.sort(key=lambda x: x[0])
    return out


def render(rows: list[tuple[str, str]]) -> str:
    lines = [
        '<?xml version="1.0" encoding="UTF-8"?>',
        '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">',
    ]
    for url, lastmod in rows:
        lines.append(f"  <url><loc>{url}</loc><lastmod>{lastmod}</lastmod></url>")
    lines.append("</urlset>")
    lines.append("")
    return "\n".join(lines)


def main(argv: list[str]) -> int:
    src = Path(argv[1] if len(argv) > 1 else "pages.json")
    dest = Path(argv[2] if len(argv) > 2 else Path(__file__).resolve().parent / "sitemap.xml")
    pages = json.loads(src.read_text())
    xml = render(entries(pages))
    dest.write_text(xml)
    print(f"wrote {dest} ({xml.count('<url>')} URLs); excluded {sorted(EXCLUDE_PATHS)}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
