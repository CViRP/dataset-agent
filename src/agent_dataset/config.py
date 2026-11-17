from pathlib import Path
from typing import Literal

from pydantic import AliasChoices, Field, SecretStr
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_prefix="DATA_AGENT_", env_file=".env", extra="ignore", populate_by_name=True
    )
    data_dir: Path = Path(".data")
    provider: Literal["offline", "openai", "anthropic"] = "offline"
    model: str = ""
    openai_base_url: str | None = Field(
        default=None,
        validation_alias=AliasChoices(
            "OPENAI_BASE_URL", "DATA_AGENT_OPENAI_BASE_URL", "openai_base_url"
        ),
    )
    openai_api_key: SecretStr = Field(
        default=SecretStr(""), validation_alias=AliasChoices("OPENAI_API_KEY", "openai_api_key")
    )
    anthropic_api_key: SecretStr = Field(
        default=SecretStr(""),
        validation_alias=AliasChoices("ANTHROPIC_API_KEY", "anthropic_api_key"),
    )
    api_keys: dict[str, str] = Field(default_factory=dict)
    browser_origins: list[str] = Field(default_factory=list)
    max_upload_mb: int = Field(default=25, ge=1, le=500)
    max_rows: int = Field(default=500_000, ge=1)
    max_columns: int = Field(default=500, ge=1)
    max_document_chars: int = Field(default=2_000_000, ge=1000)
    max_result_rows: int = Field(default=5000, ge=1, le=100_000)
    tool_timeout_seconds: int = Field(default=30, ge=1, le=300)
    agent_timeout_seconds: int = Field(default=180, ge=5, le=1800)
    max_agent_steps: int = Field(default=12, ge=1, le=50)
    max_workers: int = Field(default=2, ge=1, le=8)
    max_pending_jobs: int = Field(default=16, ge=1, le=100)
    max_context_chars: int = Field(default=80_000, ge=2000)
    sql_memory_limit: str = "256MB"
    worker_memory_mb: int = Field(default=1024, ge=128, le=16384)
    enabled_plugins: list[str] = Field(default_factory=list)


class ServiceError(Exception):
    def __init__(self, code: str, message: str, status: int = 400):
        self.code, self.message, self.status = code, message, status
        super().__init__(message)
