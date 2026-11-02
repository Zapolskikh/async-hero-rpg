"""Season report from the command line (inside the api container):

    docker exec -it <api container> python -m app.report_cli --days 90 --out /tmp/report.html
    docker exec -it <api container> python -m app.report_cli --json > report.json
"""
import argparse
import asyncio
import json
import sys

from . import analytics, db
from .config import settings


async def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--days", type=float, default=90)
    ap.add_argument("--out", default="")
    ap.add_argument("--json", action="store_true")
    a = ap.parse_args()
    await db.init_db(settings.database_url)
    r = await analytics.report(a.days)
    await db.close_db()
    text = json.dumps(r, ensure_ascii=False, indent=1) if a.json else analytics.render_html(r)
    if a.out:
        with open(a.out, "w", encoding="utf-8") as f:
            f.write(text)
    else:
        sys.stdout.write(text)


if __name__ == "__main__":
    asyncio.run(main())
