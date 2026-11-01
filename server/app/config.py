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
    # prototype: "Купить (тест)" grants crystals for free. Set ALLOW_FAKE_PURCHASES=0 before real payments.
    allow_fake_purchases: bool = os.getenv("ALLOW_FAKE_PURCHASES", "1") == "1"
    # Mythic+ seasons: closing a season pays the places (POST /v1/admin/season/close, header X-Admin-Token).
    # Empty token disables the admin endpoint.
    admin_token: str = os.getenv("ADMIN_TOKEN", "")
    season_reward_places: int = int(os.getenv("SEASON_REWARD_PLACES", "50"))   # tiers live in Rules.MYTHIC_SEASON_REWARDS
    mythic_board_size: int = int(os.getenv("MYTHIC_BOARD_SIZE", "50"))


settings = Settings()
