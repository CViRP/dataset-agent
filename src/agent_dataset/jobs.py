import logging
import threading
from concurrent.futures import ThreadPoolExecutor
from datetime import UTC, datetime

from .agent import Agent
from .config import ServiceError, Settings
from .execution import Executor
from .models import ChatInput, ReportInput
from .store import Store

logger = logging.getLogger(__name__)


class Jobs:
    """Persistent job state, local bounded dispatch. One API process per data directory."""

    def __init__(self, store: Store, settings: Settings):
        self.store, self.settings = store, settings
        self.executor = Executor(settings)
        self.agent = Agent(store, settings, self.executor)
        self.pool = ThreadPoolExecutor(
            max_workers=settings.max_workers, thread_name_prefix="analysis-job"
        )
        self.capacity = threading.BoundedSemaphore(settings.max_pending_jobs)
        self.lock = threading.RLock()
        self.cancellations: dict[str, threading.Event] = {}
        self.busy_conversations: set[str] = set()
        self.closed = False
        self.store.interrupt_jobs()

    def submit(self, tenant: str, action: str, payload: dict) -> dict:
        with self.lock:
            if self.closed or not self.capacity.acquire(blocking=False):
                raise ServiceError("queue_full", "Job queue is full; retry later", 429)
            conversation_id = None
            run = None
            try:
                if action in {"chat", "report"}:
                    request = (ReportInput if action == "report" else ChatInput).model_validate(
                        payload
                    )
                    self.agent.validate(tenant, request)
                    conversation_id = request.conversation_id
                    if conversation_id in self.busy_conversations:
                        raise ServiceError(
                            "conversation_busy",
                            "Wait for the active conversation job to finish",
                            409,
                        )
                    if not conversation_id:
                        conversation = self.store.put(
                            "conversation",
                            tenant,
                            {
                                "dataset_ids": request.dataset_ids,
                                "turns": [],
                            },
                        )
                        conversation_id = conversation["id"]
                    self.busy_conversations.add(conversation_id)
                    run = self.store.put(
                        "run",
                        tenant,
                        {
                            "status": "queued",
                            "dataset_ids": request.dataset_ids,
                            "conversation_id": conversation_id,
                            "events": [],
                            "result_ids": [],
                        },
                    )
                job = self.store.put(
                    "job",
                    tenant,
                    {
                        "action": action,
                        "status": "queued",
                        "run_id": run["id"] if run else None,
                        "conversation_id": conversation_id,
                        "result": None,
                        "error": None,
                    },
                )
                cancel = threading.Event()
                self.cancellations[job["id"]] = cancel
                self.pool.submit(self._execute, tenant, job, payload, cancel)
                return job
            except Exception:
                if conversation_id:
                    self.busy_conversations.discard(conversation_id)
                self.capacity.release()
                raise

    def event(self, tenant, run_id, event_type, data):
        if not run_id:
            return
        with self.lock:
            run = self.store.get("run", tenant, run_id)
            events = run["events"]
            events.append(
                {
                    "sequence": len(events) + 1,
                    "type": event_type,
                    "data": data,
                    "at": datetime.now(UTC).isoformat(),
                }
            )
            result_ids = list(run["result_ids"])
            if event_type == "tool_completed":
                result_ids.append(data["result_id"])
            self.store.update("run", tenant, run_id, events=events, result_ids=result_ids)

    def _execute(self, tenant, job, payload, cancel):
        job_id, run_id = job["id"], job["run_id"]
        status = "failed"
        try:
            if cancel.is_set():
                raise ServiceError("cancelled", "Job cancelled", 409)
            self.store.update("job", tenant, job_id, status="running")
            if run_id:
                self.store.update("run", tenant, run_id, status="running")
            self.event(tenant, run_id, "started", {})
            if job["action"] == "ingest":
                result = self.executor.run(tenant, "ingest", payload, cancel)
            else:
                request = (ReportInput if job["action"] == "report" else ChatInput).model_validate(
                    payload
                )
                result = self.agent.run(
                    tenant,
                    request,
                    run_id,
                    job["conversation_id"],
                    cancel,
                    lambda name, data: self.event(tenant, run_id, name, data),
                )
            if cancel.is_set():
                raise ServiceError("cancelled", "Job cancelled", 409)
            status = "succeeded"
            self.store.update("job", tenant, job_id, status=status, result=result)
            self.event(tenant, run_id, "completed", {"job_id": job_id})
        except Exception as exc:  # noqa: BLE001 - persist failures at the job boundary
            if isinstance(exc, ServiceError):
                error = {"code": exc.code, "message": exc.message}
                status = "cancelled" if exc.code == "cancelled" else "failed"
            else:
                logger.error("Job failed: %s", type(exc).__name__)
                error = {"code": "internal_error", "message": "Unexpected job failure"}
            self.store.update("job", tenant, job_id, status=status, error=error)
            self.event(tenant, run_id, status, error)
        finally:
            if run_id:
                self.store.update("run", tenant, run_id, status=status)
            with self.lock:
                self.cancellations.pop(job_id, None)
                self.busy_conversations.discard(job["conversation_id"])
            self.capacity.release()

    def cancel(self, tenant, job_id):
        with self.lock:
            job = self.store.get("job", tenant, job_id)
            event = self.cancellations.get(job_id)
            if event:
                event.set()
                return {"id": job_id, "status": "cancellation_requested"}
            return {"id": job_id, "status": job["status"]}

    def close(self):
        with self.lock:
            self.closed = True
            for event in self.cancellations.values():
                event.set()
        self.pool.shutdown(wait=True, cancel_futures=False)
