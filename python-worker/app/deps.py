"""Application dependencies: configuration and Supabase client."""

from __future__ import annotations

from functools import lru_cache

from pydantic_settings import BaseSettings, SettingsConfigDict
from supabase import Client, create_client
from supabase.lib.client_options import ClientOptions

# Keep well under Railway's proxy timeout so FastAPI can write the error body
# before the connection is closed. Default in supabase-py may be higher.
_POSTGREST_TIMEOUT = 8  # seconds


class Settings(BaseSettings):
    """Runtime configuration loaded from environment."""

    supabase_url: str
    supabase_service_role_key: str
    worker_auth_token: str = ""

    log_level: str = "info"

    min_cluster_size_floor: int = 5
    lsi_distance_threshold: float = 0.15
    long_tail_distance_threshold: float = 0.35

    model_config = SettingsConfigDict(
        env_file=".env",
        env_prefix="",
        extra="ignore",
        env_nested_delimiter="__",
    )


@lru_cache(maxsize=1)
def get_settings() -> Settings:
    return Settings()  # type: ignore[call-arg]


@lru_cache(maxsize=1)
def get_supabase() -> Client:
    settings = get_settings()
    return create_client(
        settings.supabase_url,
        settings.supabase_service_role_key,
        options=ClientOptions(postgrest_client_timeout=_POSTGREST_TIMEOUT),
    )
