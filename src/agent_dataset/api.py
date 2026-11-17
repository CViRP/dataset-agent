import asyncio
import hmac
from contextlib import asynccontextmanager
from pathlib import Path
from typing import Annotated

from fastapi import Depends, FastAPI, File, Form, Query, Request, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse, JSONResponse, StreamingResponse
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from pydantic import ValidationError
from starlette.middleware.trustedhost import TrustedHostMiddleware

from .config import ServiceError, Settings
from .ingest import FORMATS, public_dataset
from .jobs import Jobs
from .models import ChatInput, ReportInput, ToolRequest
from .store import Store, dumps
from .tools import build_registry, result_envelope

bearer = HTTPBearer(auto_error=False)


def create_app(settings: Settings | None = None) -> FastAPI:
    settings = settings or Settings()
    store = Store(settings.data_dir)
    registry = build_registry(settings.enabled_plugins)

    @asynccontextmanager
    async def lifespan(app):
        # Prevent two API processes from marking each other's jobs interrupted.
        import portalocker

        lock = portalocker.Lock(str(store.root / "server.lock"), timeout=0)
        try:
            lock.acquire()
        except portalocker.LockException as exc:
            raise RuntimeError(
                "Another API process is using this data directory; run one Uvicorn worker."
            ) from exc
        try:
            app.state.jobs = Jobs(store, settings)
            try:
                yield
            finally:
                await asyncio.to_thread(app.state.jobs.close)
        finally:
            lock.release()

    app = FastAPI(
        title="Dataset Analysis API",
        version="0.1.0",
        lifespan=lifespan,
        docs_url=None,
        redoc_url=None,
    )
    app.state.settings, app.state.store = settings, store
    if not settings.api_keys:
        app.add_middleware(
            TrustedHostMiddleware, allowed_hosts=["127.0.0.1", "localhost", "[::1]", "testserver"]
        )

    @app.exception_handler(ServiceError)
    async def service_error(request, exc):
        return JSONResponse(
            {"error": {"code": exc.code, "message": exc.message}}, status_code=exc.status
        )

    @app.middleware("http")
    async def request_limits(request, call_next):
        # Keep the browser surface opt-in, including simple cross-origin form submissions.
        origin = request.headers.get("origin")
        if origin and origin not in settings.browser_origins:
            return JSONResponse(
                {
                    "error": {
                        "code": "origin_not_allowed",
                        "message": "Browser origin is not in DATA_AGENT_BROWSER_ORIGINS",
                    }
                },
                status_code=403,
            )
        length = request.headers.get("content-length")
        if length:
            try:
                oversized = int(length) > settings.max_upload_mb * 1024**2 + 1024**2
            except ValueError:
                return JSONResponse(
                    {"error": {"code": "invalid_length", "message": "Invalid Content-Length"}},
                    status_code=400,
                )
            if oversized:
                return JSONResponse(
                    {
                        "error": {
                            "code": "upload_too_large",
                            "message": "Request exceeds upload limit",
                        }
                    },
                    status_code=413,
                )
        if request.method == "POST" and request.url.path == "/datasets" and not length:
            return JSONResponse(
                {
                    "error": {
                        "code": "length_required",
                        "message": "Upload requests require Content-Length",
                    }
                },
                status_code=411,
            )
        response = await call_next(request)
        response.headers["X-Content-Type-Options"] = "nosniff"
        response.headers["Cache-Control"] = "no-store"
        return response

    def tenant(
        request: Request,
        credentials: Annotated[HTTPAuthorizationCredentials | None, Depends(bearer)],
    ):
        if settings.api_keys:
            token = credentials.credentials if credentials else ""
            for expected, project in settings.api_keys.items():
                if expected and hmac.compare_digest(token, expected):
                    return project
            raise ServiceError("unauthorized", "Valid Bearer token required", 401)
        if credentials:
            raise ServiceError("auth_not_configured", "Server has no API key map configured", 401)
        if not request.client or request.client.host not in {"127.0.0.1", "::1", "testclient"}:
            raise ServiceError("local_only", "Configure DATA_AGENT_API_KEYS for remote access", 403)
        return "local"

    Tenant = Annotated[str, Depends(tenant)]

    @app.get("/health")
    def health():
        return {"status": "ok", "version": "0.1.0"}

    @app.get("/capabilities")
    def capabilities(project: Tenant):
        return {
            "provider": settings.provider,
            "model": settings.model or None,
            "providers": {
                "offline": True,
                "openai": bool(settings.openai_api_key.get_secret_value()),
                "anthropic": bool(settings.anthropic_api_key.get_secret_value()),
            },
            "formats": sorted(FORMATS),
            "tools": registry.definitions(),
            "limits": {
                "upload_mb": settings.max_upload_mb,
                "rows": settings.max_rows,
                "result_rows": settings.max_result_rows,
                "tool_seconds": settings.tool_timeout_seconds,
            },
            "execution": "bounded trusted-operation subprocesses; arbitrary Python disabled",
            "document_search": "lexical BM25; embeddings and OCR not enabled",
        }

    @app.post("/datasets", status_code=202)
    async def upload(
        request: Request,
        project: Tenant,
        file: Annotated[UploadFile, File()],
        sheet: Annotated[str | None, Form()] = None,
    ):
        filename = (file.filename or "upload").replace("\\", "/").rsplit("/", 1)[-1]
        extension = Path(filename).suffix.lower()
        if extension not in FORMATS:
            await file.close()
            raise ServiceError(
                "unsupported_format", f"Supported formats: {', '.join(sorted(FORMATS))}", 415
            )
        relative, path = store.allocate("originals", extension)
        size = 0
        try:
            with path.open("wb") as output:
                while chunk := await file.read(1024 * 1024):
                    size += len(chunk)
                    if size > settings.max_upload_mb * 1024**2:
                        raise ServiceError("upload_too_large", "File exceeds upload limit", 413)
                    output.write(chunk)
            if not size:
                raise ServiceError("empty_file", "Uploaded file is empty", 422)
            return app.state.jobs.submit(
                project, "ingest", {"relative": relative, "filename": filename, "sheet": sheet}
            )
        except Exception:
            path.unlink(missing_ok=True)
            raise
        finally:
            await file.close()

    @app.get("/datasets")
    def datasets(
        project: Tenant, limit: int = Query(100, ge=1, le=100), offset: int = Query(0, ge=0)
    ):
        return {
            "datasets": [public_dataset(d) for d in store.list("dataset", project, limit, offset)]
        }

    @app.get("/datasets/{dataset_id}")
    def dataset(dataset_id: str, project: Tenant):
        return public_dataset(store.get("dataset", project, dataset_id))

    @app.get("/datasets/{dataset_id}/download")
    def download_dataset(dataset_id: str, project: Tenant, original: bool = False):
        record = store.get("dataset", project, dataset_id)
        if original:
            return FileResponse(
                store.path(record["source"]["original_path"]),
                filename=record["source"]["filename"],
                media_type="application/octet-stream",
            )
        if record["kind"] != "table":
            raise ServiceError("not_tabular", "Use original=true to download the source document")
        return FileResponse(
            store.path(record["path"]),
            filename=f"{record['id']}.parquet",
            media_type="application/vnd.apache.parquet",
        )

    @app.get("/tools")
    def tools(project: Tenant):
        return {"tools": registry.definitions()}

    @app.post("/tools/{name}")
    def execute_tool(name: str, body: ToolRequest, project: Tenant):
        if name not in registry.tools:
            raise ServiceError("unknown_tool", "Unknown tool", 404)
        try:
            registry.tools[name].schema.model_validate(body.arguments)
        except ValidationError as exc:
            raise ServiceError("validation_error", str(exc)[:1000], 422) from exc
        return app.state.jobs.executor.run(
            project, "tool", {"name": name, "arguments": body.arguments}
        )

    @app.get("/results/{result_id}")
    def result(
        result_id: str,
        project: Tenant,
        offset: int = Query(0, ge=0),
        limit: int = Query(100, ge=1, le=1000),
    ):
        record = store.get("result", project, result_id)
        if isinstance(record["data"].get("rows"), list):
            total = len(record["data"]["rows"])
            record["data"]["rows"] = record["data"]["rows"][offset : offset + limit]
            record["data"].update(total_stored_rows=total, offset=offset)
        return result_envelope(record, preview_rows=limit)

    @app.post("/chat", status_code=202)
    def chat(body: ChatInput, project: Tenant):
        return app.state.jobs.submit(project, "chat", body.model_dump())

    @app.post("/reports", status_code=202)
    def reports(body: ReportInput, project: Tenant):
        return app.state.jobs.submit(project, "report", body.model_dump())

    @app.get("/jobs/{job_id}")
    def job(job_id: str, project: Tenant):
        return store.get("job", project, job_id)

    @app.post("/jobs/{job_id}/cancel")
    def cancel(job_id: str, project: Tenant):
        return app.state.jobs.cancel(project, job_id)

    @app.get("/runs/{run_id}")
    def run(run_id: str, project: Tenant):
        return store.get("run", project, run_id)

    @app.get("/conversations/{conversation_id}")
    def conversation(conversation_id: str, project: Tenant):
        return store.get("conversation", project, conversation_id)

    @app.get("/runs/{run_id}/events")
    async def events(run_id: str, request: Request, project: Tenant, after: int = Query(0, ge=0)):
        store.get("run", project, run_id)

        async def stream():
            cursor = after
            while not await request.is_disconnected():
                record = await asyncio.to_thread(store.get, "run", project, run_id)
                for event in record["events"]:
                    if event["sequence"] > cursor:
                        cursor = event["sequence"]
                        yield f"id: {cursor}\nevent: {event['type']}\ndata: {dumps(event)}\n\n"
                if record["status"] in {"succeeded", "failed", "cancelled"}:
                    break
                yield ": keepalive\n\n"
                await asyncio.sleep(1)

        return StreamingResponse(
            stream(), media_type="text/event-stream", headers={"X-Accel-Buffering": "no"}
        )

    @app.get("/artifacts/{artifact_id}")
    def artifact(artifact_id: str, project: Tenant):
        record = store.get("artifact", project, artifact_id)
        # HTML is served as a download with a restrictive CSP, never as an application UI.
        return FileResponse(
            store.path(record["path"]),
            media_type=record["mime_type"],
            filename=record["filename"],
            headers={
                "Content-Security-Policy": "default-src 'none'; img-src data:; style-src 'unsafe-inline'"
            },
        )

    # Add last so preflight handling and CORS headers wrap the request/auth middleware.
    if settings.browser_origins:
        app.add_middleware(
            CORSMiddleware,
            allow_origins=settings.browser_origins,
            allow_methods=["GET", "POST"],
            allow_headers=["Authorization", "Content-Type"],
            expose_headers=["Content-Disposition"],
        )
    return app
