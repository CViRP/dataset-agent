"""SQLite metadata and private, generated artifact paths; no user-supplied paths."""

import hashlib
import json
import math
import sqlite3
import uuid
from contextlib import contextmanager
from datetime import UTC, date, datetime
from pathlib import Path
from typing import Any

from .config import ServiceError


def clean(value: Any) -> Any:
    if isinstance(value, dict):
        return {str(k): clean(v) for k, v in value.items()}
    if isinstance(value, (tuple, list)):
        return [clean(v) for v in value]
    if isinstance(value, float):
        return value if math.isfinite(value) else None
    if isinstance(value, (datetime, date)):
        return value.isoformat()
    if value is None or isinstance(value, (str, int, bool)):
        return value
    if hasattr(value, "item"):
        return clean(value.item())
    return str(value)


def dumps(value: Any) -> str:
    return json.dumps(clean(value), ensure_ascii=False, allow_nan=False)


def identifier(prefix: str) -> str:
    return f"{prefix}_{uuid.uuid4().hex}"


class Store:
    def __init__(self, root: Path):
        self.root = root.resolve()
        self.root.mkdir(parents=True, exist_ok=True)
        self.db = self.root / "metadata.sqlite3"
        with self.connect() as db:
            db.execute("PRAGMA journal_mode=WAL")
            db.execute("""CREATE TABLE IF NOT EXISTS records (
                id TEXT PRIMARY KEY, kind TEXT NOT NULL, tenant TEXT NOT NULL,
                created_at TEXT NOT NULL, payload TEXT NOT NULL)""")
            db.execute("CREATE INDEX IF NOT EXISTS records_owner ON records(tenant, kind)")

    @contextmanager
    def connect(self):
        connection = sqlite3.connect(self.db, timeout=30)
        connection.row_factory = sqlite3.Row
        try:
            with connection:
                yield connection
        finally:
            connection.close()

    def put(self, kind: str, tenant: str, payload: dict, record_id: str | None = None) -> dict:
        record = {
            **payload,
            "id": record_id or identifier(kind),
            "created_at": datetime.now(UTC).isoformat(),
        }
        with self.connect() as db:
            db.execute(
                "INSERT INTO records VALUES (?, ?, ?, ?, ?)",
                (record["id"], kind, tenant, record["created_at"], dumps(record)),
            )
        return clean(record)

    def get(self, kind: str, tenant: str, record_id: str) -> dict:
        with self.connect() as db:
            row = db.execute(
                "SELECT payload FROM records WHERE id=? AND kind=? AND tenant=?",
                (record_id, kind, tenant),
            ).fetchone()
        if row is None:
            raise ServiceError("not_found", f"{kind} not found", 404)
        return json.loads(row["payload"])

    def update(self, kind: str, tenant: str, record_id: str, **changes) -> dict:
        with self.connect() as db:
            db.execute("BEGIN IMMEDIATE")
            row = db.execute(
                "SELECT payload FROM records WHERE id=? AND kind=? AND tenant=?",
                (record_id, kind, tenant),
            ).fetchone()
            if row is None:
                raise ServiceError("not_found", f"{kind} not found", 404)
            record = {**json.loads(row["payload"]), **clean(changes)}
            db.execute("UPDATE records SET payload=? WHERE id=?", (dumps(record), record_id))
        return record

    def list(self, kind: str, tenant: str, limit: int = 100, offset: int = 0) -> list[dict]:
        with self.connect() as db:
            rows = db.execute(
                "SELECT payload FROM records WHERE kind=? AND tenant=? "
                "ORDER BY created_at DESC LIMIT ? OFFSET ?",
                (kind, tenant, limit, offset),
            ).fetchall()
        return [json.loads(row["payload"]) for row in rows]

    def interrupt_jobs(self):
        # Single API process owns this store. Never silently replay mutations after restart.
        with self.connect() as db:
            rows = db.execute("SELECT id,payload FROM records WHERE kind='job'").fetchall()
            for row in rows:
                payload = json.loads(row["payload"])
                if payload["status"] in {"queued", "running"}:
                    payload.update(
                        status="failed",
                        error={
                            "code": "server_restarted",
                            "message": "Server stopped; submit the job again.",
                        },
                    )
                    db.execute(
                        "UPDATE records SET payload=? WHERE id=?", (dumps(payload), row["id"])
                    )
            runs = db.execute("SELECT id,payload FROM records WHERE kind='run'").fetchall()
            for row in runs:
                payload = json.loads(row["payload"])
                if payload["status"] in {"queued", "running"}:
                    payload["status"] = "failed"
                    payload["events"].append(
                        {
                            "sequence": len(payload["events"]) + 1,
                            "type": "failed",
                            "data": {
                                "code": "server_restarted",
                                "message": "Server stopped; submit the job again.",
                            },
                            "at": datetime.now(UTC).isoformat(),
                        }
                    )
                    db.execute(
                        "UPDATE records SET payload=? WHERE id=?", (dumps(payload), row["id"])
                    )

    def path(self, relative: str) -> Path:
        path = (self.root / relative).resolve()
        if not path.is_relative_to(self.root):
            raise ServiceError("invalid_path", "Path is outside storage", 400)
        return path

    def allocate(self, area: str, suffix: str) -> tuple[str, Path]:
        relative = f"{area}/{uuid.uuid4().hex}{suffix}"
        path = self.path(relative)
        path.parent.mkdir(parents=True, exist_ok=True)
        return relative, path

    def artifact(
        self,
        tenant: str,
        content: bytes,
        suffix: str,
        mime: str,
        filename: str,
        dataset_ids: list[str],
        **metadata,
    ) -> dict:
        relative, path = self.allocate("artifacts", suffix)
        path.write_bytes(content)
        record = self.put(
            "artifact",
            tenant,
            {
                "path": relative,
                "mime_type": mime,
                "filename": filename,
                "size_bytes": len(content),
                "sha256": hashlib.sha256(content).hexdigest(),
                "dataset_ids": dataset_ids,
                **metadata,
            },
        )
        return self.public_artifact(record)

    @staticmethod
    def public_artifact(record: dict) -> dict:
        return {
            **{k: v for k, v in record.items() if k != "path"},
            "download_path": f"/artifacts/{record['id']}",
        }
