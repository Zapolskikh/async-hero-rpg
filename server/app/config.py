"""Settings from environment variables (see .env.example)."""
import os
from dataclasses import dataclass, field
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]  # repository root = Godot project


def _list(name: str, default: str) -> list[str]:
    return [x.strip() for x in os.getenv(name, default).split(",") if x.strip()]


@dataclass
class Settings:
    database_url: str = os.getenv("DATABASE_URL", "sqlite+aiosqlite:///./hero.db")
    godot_bin: str = os.getenv("GODOT_BIN", "godot")
    project_dir: str = os.getenv("PROJECT_DIR", str(ROOT))
    workers: int = int(os.getenv("WORKERS", "2"))
    worker_timeout: float = float(os.getenv("WORKER_TIMEOUT", "15"))
    cors_origins: list[str] = field(default_factory=lambda: _list("CORS_ORIGINS", "*"))
    # economy guards (concept 8.1 / 12)
    assist_daily_gold_cap: int = int(os.getenv("ASSIST_DAILY_GOLD_CAP", "3000"))   # per owner per day
    assist_pair_daily_events: int = int(os.getenv("ASSIST_PAIR_DAILY_EVENTS", "30"))  # owner<-hirer per day
    pool_level_range: int = int(os.getenv("POOL_LEVEL_RANGE", "3"))
    pool_size: int = int(os.getenv("POOL_SIZE", "12"))
    snapshot_max_age_days: int = int(os.getenv("SNAPSHOT_MAX_AGE_DAYS", "14"))
    rate_per_sec: float = float(os.getenv("RATE_PER_SEC", "8"))
    rate_burst: int = int(os.getenv("RATE_BURST", "30"))


settings = Settings()
