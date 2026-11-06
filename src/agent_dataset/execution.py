"""Bounded subprocess execution, including cancellation and RSS monitoring.

This is process isolation for trusted operations, NOT a sandbox for arbitrary Python.
"""

import logging
import multiprocessing
import threading
import time

import psutil
from pydantic import SecretStr, ValidationError

from .config import ServiceError, Settings
from .ingest import ingest, public_dataset
from .models import ToolContext
from .store import Store

logger = logging.getLogger(__name__)


def worker_entry(connection, settings: Settings, tenant: str, action: str, payload: dict):
    try:
        store = Store(settings.data_dir)
        if action == "ingest":
            result = public_dataset(ingest(store, settings, tenant, **payload))
        elif action == "tool":
            from .tools import Analysis, build_registry

            context = ToolContext(tenant=tenant, **payload.get("context", {}))
            result = Analysis(store, settings, context).execute(
                build_registry(settings.enabled_plugins), payload["name"], payload["arguments"]
            )
        else:
            raise ServiceError("invalid_action", "Unknown worker action")
        connection.send({"ok": True, "value": result})
    except ServiceError as exc:
        connection.send(
            {"ok": False, "code": exc.code, "message": exc.message, "status": exc.status}
        )
    except ValidationError as exc:
        connection.send(
            {"ok": False, "code": "validation_error", "message": str(exc)[:1000], "status": 422}
        )
    except (ValueError, TypeError, KeyError, UnicodeError) as exc:
        connection.send(
            {"ok": False, "code": "invalid_data", "message": str(exc)[:1000], "status": 422}
        )
    except Exception as exc:  # noqa: BLE001 - process boundary must return a structured failure
        # No raw source content, API keys, or exception messages in logs.
        logger.error("Analysis worker failed: %s", type(exc).__name__)
        connection.send(
            {
                "ok": False,
                "code": "analysis_failed",
                "message": f"Analysis failed ({type(exc).__name__}); check input format and tool arguments.",
                "status": 422,
            }
        )
    finally:
        connection.close()


class Executor:
    def __init__(self, settings: Settings):
        self.settings = settings
        self.slots = threading.BoundedSemaphore(settings.max_workers)

    def run(
        self,
        tenant: str,
        action: str,
        payload: dict,
        cancel: threading.Event | None = None,
        timeout: float | None = None,
    ):
        timeout = timeout or self.settings.tool_timeout_seconds
        started = time.monotonic()
        while not self.slots.acquire(timeout=0.1):
            self._check(started, timeout, cancel)
        process = None
        receiver = sender = None
        try:
            self._check(started, timeout, cancel)
            ctx = multiprocessing.get_context("spawn")
            receiver, sender = ctx.Pipe(duplex=False)
            isolated_settings = self.settings.model_copy(
                update={
                    "openai_api_key": SecretStr(""),
                    "anthropic_api_key": SecretStr(""),
                    "api_keys": {},
                }
            )
            process = ctx.Process(
                target=worker_entry,
                args=(sender, isolated_settings, tenant, action, payload),
                daemon=True,
            )
            process.start()
            sender.close()
            monitor = psutil.Process(process.pid)
            while True:
                self._check(started, timeout, cancel)
                if receiver.poll(0.05):
                    try:
                        result = receiver.recv()
                    except EOFError as exc:
                        raise ServiceError(
                            "worker_failed", "Analysis worker exited without a result", 500
                        ) from exc
                    if not result["ok"]:
                        raise ServiceError(result["code"], result["message"], result["status"])
                    return result["value"]
                if not process.is_alive():
                    raise ServiceError(
                        "worker_failed", "Analysis worker exited without a result", 500
                    )
                try:
                    if monitor.memory_info().rss > self.settings.worker_memory_mb * 1024**2:
                        raise ServiceError(
                            "memory_limit", "Analysis exceeded the worker memory limit", 422
                        )
                except psutil.NoSuchProcess:
                    pass
        finally:
            if process is not None:
                process.join(timeout=0.2)
                if process.is_alive():
                    process.terminate()
                    process.join(timeout=2)
                process.close()
            if receiver is not None:
                receiver.close()
            if sender is not None:
                sender.close()
            self.slots.release()

    @staticmethod
    def _check(started, timeout, cancel):
        if cancel and cancel.is_set():
            raise ServiceError("cancelled", "Operation cancelled", 409)
        if time.monotonic() - started > timeout:
            raise ServiceError("timeout", "Operation exceeded its execution time limit", 408)
