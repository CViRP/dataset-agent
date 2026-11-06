import threading
import time

import pytest

from agent_dataset.config import ServiceError
from agent_dataset.execution import Executor


def test_cancellation_before_execution(settings):
    event = threading.Event()
    event.set()
    with pytest.raises(ServiceError) as error:
        Executor(settings).run("local", "tool", {}, event)
    assert error.value.code == "cancelled"


def test_worker_timeout_terminates_expensive_regex(settings, ingest_bytes):
    document = ingest_bytes("a" * 100 + "!", "regex.txt")
    started = time.monotonic()
    with pytest.raises(ServiceError) as error:
        Executor(settings).run(
            "local",
            "tool",
            {
                "name": "extract_records",
                "arguments": {
                    "dataset_id": document["id"],
                    "pattern": r"^(?P<text>a+)+$",
                    "fields": {"text": "string"},
                },
            },
            timeout=2,
        )
    assert error.value.code == "timeout"
    assert time.monotonic() - started < 8


def test_restart_marks_jobs_and_runs_failed(store):
    job = store.put("job", "local", {"status": "running"})
    run = store.put("run", "local", {"status": "running", "events": []})
    store.interrupt_jobs()
    assert store.get("job", "local", job["id"])["error"]["code"] == "server_restarted"
    assert store.get("run", "local", run["id"])["status"] == "failed"
