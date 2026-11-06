import pytest

from agent_dataset.config import Settings
from agent_dataset.ingest import ingest
from agent_dataset.models import ToolContext
from agent_dataset.store import Store
from agent_dataset.tools import Analysis, build_registry


@pytest.fixture
def settings(tmp_path):
    return Settings(
        _env_file=None,
        data_dir=tmp_path / "data",
        provider="offline",
        openai_api_key="",
        anthropic_api_key="",
        api_keys={},
        tool_timeout_seconds=30,
        agent_timeout_seconds=180,
    )


@pytest.fixture
def store(settings):
    return Store(settings.data_dir)


@pytest.fixture
def ingest_bytes(store, settings):
    def load(content, name="data.csv", tenant="local", sheet=None):
        from pathlib import Path

        relative, path = store.allocate("originals", Path(name).suffix)
        path.write_bytes(content if isinstance(content, bytes) else content.encode("utf-8"))
        return ingest(store, settings, tenant, relative, name, sheet)

    return load


@pytest.fixture
def sales(ingest_bytes):
    return ingest_bytes("region,revenue,orders\nNorth,100,2\nSouth,80,1\nNorth,50,1\nSouth,20,1\n")


@pytest.fixture
def execute(store, settings):
    def run(name, arguments, tenant="local", allowed=None):
        return Analysis(
            store, settings, ToolContext(tenant=tenant, allowed_dataset_ids=allowed)
        ).execute(build_registry(), name, arguments)

    return run
