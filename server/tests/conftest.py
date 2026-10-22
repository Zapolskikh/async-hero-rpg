import os
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
os.environ.setdefault("GODOT_BIN", "/opt/godot/godot")
os.environ.setdefault("WORKERS", "2")
os.environ.setdefault("RATE_PER_SEC", "1000")
os.environ.setdefault("RATE_BURST", "1000")


@pytest.fixture(scope="session")
def client():
    url = os.environ.get("TEST_DATABASE_URL", "sqlite+aiosqlite:///./test_hero.db")
    os.environ["DATABASE_URL"] = url
    if url.startswith("sqlite"):
        Path("test_hero.db").unlink(missing_ok=True)
    from app.config import settings
    settings.database_url = url
    if url.startswith("postgresql"):
        import asyncio
        from sqlalchemy.ext.asyncio import create_async_engine
        from app.db import Base

        async def reset():
            eng = create_async_engine(url)
            async with eng.begin() as c:
                await c.run_sync(Base.metadata.drop_all)
            await eng.dispose()
        asyncio.run(reset())
    from fastapi.testclient import TestClient
    from app.main import app
    with TestClient(app) as c:
        yield c
