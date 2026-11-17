# Dataset Analysis Agent

A data-science assistant built with FastAPI and a Persian Flutter web frontend. Upload tables or documents, edit and transform datasets, ask GPT or Claude questions, and download datasets, charts, and reports. `/docs` and `/redoc` are disabled; the machine-readable OpenAPI specification is at `/openapi.json`.

## Quick start from GitHub

Prerequisites: Git, [uv](https://docs.astral.sh/uv/getting-started/installation/), and Python 3.14 (uv can install Python automatically). For the optional browser interface, also install the [Flutter SDK](https://docs.flutter.dev/install) and Chrome. The commands below use PowerShell on Windows.

```powershell
git clone https://github.com/CViRP/dataset-agent.git
Set-Location dataset-agent
uv sync --locked --python 3.14
Copy-Item .env.example .env
uv run --locked agent-dataset
```

Keep that terminal running. The API is available at `http://127.0.0.1:8000`; check `http://127.0.0.1:8000/health`. In a second terminal, open the cloned repository and run a complete offline example:

```powershell
uv run --locked python examples/api_demo.py
```

To use the browser interface instead, run these commands from the repository root in a second terminal:

```powershell
Set-Location frontend
flutter pub get
flutter run -d chrome --web-hostname localhost --web-port 8080
```

The example `.env` already allows this frontend origin. Open `http://localhost:8080`, upload `examples/sales.csv` from the repository, select the dataset, and inspect or edit its cells. Use the transformation controls to clean/filter data, download an exported version, or generate a report. Every edit creates a new version, so earlier versions remain available. Local defaults require no project token; if you configure authentication, enter the project token in connection settings.

The default provider is `offline`: direct tools, edits, charts, and reports work without a model key, while chat returns profiles and document keyword matches. For natural-language analysis or editing, configure OpenAI or Anthropic as described in [Enable GPT or Claude later](#enable-gpt-or-claude-later), then restart the API. Stop either process with `Ctrl+C`.

## Persian Flutter web frontend

The `frontend/` application provides a right-to-left workspace with a bundled Persian font, uploads, paginated previews, cell edits, row insertion/deletion, cleanup and transformation forms, version selection, chat, evidence citations, reports, and authenticated downloads. Every edit creates a new immutable version; select any earlier version in the dataset list to return to it.

Start the API from this repository (the origin allowlist is required for browser requests):

```powershell
$env:DATA_AGENT_BROWSER_ORIGINS='["http://localhost:8080","http://127.0.0.1:8080"]'
.\.venv\Scripts\agent-dataset.exe
```

In a second terminal:

```powershell
# From the cloned repository root:
Set-Location frontend
flutter pub get
flutter run -d chrome --web-hostname localhost --web-port 8080
```

Open `http://localhost:8080`. The default API is `http://127.0.0.1:8000`; change it and enter a **project API token** through the connection settings button. Tokens remain in page memory; model provider keys stay on the server. To set a different build-time API default, add `--dart-define=API_BASE_URL=https://your-api.example`.

Direct editing and transformation work without a model key. Offline chat only profiles tables and searches documents; configure a provider and model below to interpret Persian natural-language editing requests. Chat/report jobs display progress and can be cancelled. HTML reports preserve Persian text; PDF Unicode support remains limited.

Build and verify:

```powershell
flutter analyze
flutter test
flutter build web --release --no-web-resources-cdn
```

The static bundle is `frontend/build/web/`. Serve it with an HTTP server, configure its exact origin in `DATA_AGENT_BROWSER_ORIGINS`, and deploy the FastAPI backend separately. See [frontend/README.md](frontend/README.md) for details.

## Run locally

Dependencies are installed into `.venv`; `uv.lock` pins the tested environment. Python 3.14 or newer is required; the quick start selects Python 3.14.

```powershell
# From the cloned repository root:
uv sync --locked --python 3.14
# Optional configuration; skip this if .env already exists.
Copy-Item .env.example .env
.\.venv\Scripts\agent-dataset.exe
```

The API listens at `http://127.0.0.1:8000`. Persistent data lives in `.data/`. Run **one API process per data directory**; a file lock prevents accidentally starting a second process over the same store.

No LLM key is needed for uploads, analysis tools, document search, charts, reports, or `provider: "offline"`. Offline chat explicitly returns dataset profiles and keyword matches; it does not interpret arbitrary natural-language questions.

In another terminal, run the complete upload → query → chart → PDF example:

```powershell
.\.venv\Scripts\python.exe examples/api_demo.py
```

The demo prints actual artifact download paths. It uses synthetic sales data from `examples/sales.csv` and makes no external model calls.

## API workflow

For container deployment, see [Docker Compose](#docker-compose) below.

1. Upload a file with `POST /datasets` as multipart form data. It returns `202` and a job `id`.
2. Poll `GET /jobs/{id}` until `status` is `succeeded`, `failed`, or `cancelled`. On success, `result.id` is the immutable dataset version ID.
3. Call `/tools/{name}` for deterministic analysis, or `/chat` and `/reports` for agent workflows.
4. Chat/report submissions return a job ID, run ID, and conversation ID. Poll the job for the answer, or consume `GET /runs/{run_id}/events` as SSE. Use `?after=N` to resume after an event sequence number.
5. Fetch referenced results and artifacts using the same project credentials. Send `conversation_id` and the returned `dataset_ids` to continue a conversation.

```powershell
curl.exe -sS -F "file=@examples/sales.csv" http://127.0.0.1:8000/datasets
```

Example `POST /chat` JSON, after replacing the dataset ID with the upload result:

```json
{
  "prompt": "Compare total revenue by region and create a bar chart.",
  "dataset_ids": ["dataset_REPLACE_WITH_UPLOAD_RESULT"],
  "provider": "openai",
  "model": "YOUR_AVAILABLE_MODEL_ID"
}
```

Use `"provider": "offline"` and omit `model` to exercise the local workflow before acquiring a key. For a report, send the same request to `POST /reports`, adding `"format": "pdf"` and optionally `"title": "Sales analysis"`. Formats are `html`, `pdf`, and `markdown`.

Direct tool calls accept `{"arguments": {...}}`. For example, `POST /tools/query_table`:

```json
{
  "arguments": {
    "tables": {"sales": "dataset_REPLACE_WITH_UPLOAD_RESULT"},
    "sql": "SELECT region, SUM(revenue) AS revenue FROM sales GROUP BY region ORDER BY region",
    "limit": 1000
  }
}
```

Then `POST /tools/create_chart`:

```json
{
  "arguments": {
    "result_id": "result_REPLACE_WITH_QUERY_RESULT",
    "chart_type": "bar",
    "x": "region",
    "y": "revenue",
    "title": "Revenue by region"
  }
}
```

Tools return `status`, `result_id`, `data`, `artifacts`, `provenance`, `warnings`, and `error`. Row previews are capped at 100; paginate stored results with `GET /results/{id}?offset=100&limit=100`. Queries store at most 5,000 rows by default, disclose truncation, and export those rows as CSV. Aggregate inside SQL for full-population totals.

| Endpoint | Purpose |
|---|---|
| `GET /health` | Liveness |
| `GET /capabilities` | Available providers, formats, tools, and limits |
| `POST /datasets` | Upload; optional `sheet` form field selects an XLSX worksheet by name |
| `GET /datasets` | List versions; `limit` and `offset` pagination |
| `GET /datasets/{id}` | Metadata without filesystem paths |
| `GET /datasets/{id}/download` | Normalized Parquet; `?original=true` downloads the original source |
| `GET /tools` | Full tool schemas and plugin metadata |
| `POST /tools/{name}` | Execute a validated analysis operation |
| `GET /results/{id}` | Retrieve saved evidence |
| `POST /chat` | Start an analysis job |
| `POST /reports` | Start analysis and report generation |
| `GET /jobs/{id}` | Status, result, or structured error |
| `POST /jobs/{id}/cancel` | Cancel queued/active work |
| `GET /runs/{id}` | Inspect events and intermediate result IDs |
| `GET /runs/{id}/events` | SSE progress stream |
| `GET /conversations/{id}` | Saved conversation and dataset scope |
| `GET /artifacts/{id}` | Authorized file download |

## Analysis capabilities

- **Tables:** CSV, TSV, XLSX, Parquet, JSON record arrays, and JSONL. JSON objects are flattened; nested arrays are kept as JSON strings. XLSX defaults to the first sheet. Originals are preserved.
- **Documents:** UTF-8 TXT/Markdown, text PDFs, and DOCX paragraphs/tables. Source references retain page, paragraph, table, chunk, and character positions. Scanned PDFs requiring OCR are reported as unsupported when no text is extractable.
- **Inspection/profile:** schema, samples, row counts, duplicates, missingness, cardinality, numeric distributions, and IQR outliers.
- **Queries:** DuckDB SQL joins, filtering, aggregation, and window functions over explicitly mapped tables. External access, dynamic query functions, mutations, and multiple statements are blocked.
- **Transformations:** selection, rename, deduplication, drop/fill nulls, type casts, dropping columns, literal replacements, trimming strings, filters, sorting, constant columns, and numeric calculations create new versions. Filter conditions combine with AND; comparisons exclude nulls (use `is_null`/`not_null` explicitly). Calculations support add/subtract/multiply/divide with a numeric constant or another column; division by zero is rejected.
- **Editing:** `edit_dataset` updates cells, deletes rows, and appends records. Positions are zero-based in the input version. Updates happen first, then deletions, then appends; editing and deleting the same row is rejected. Missing fields in appended records become null. Cast a column first when changing its type. Original data and parent/version lineage are preserved.
- **Exports:** `export_dataset` exports the entire selected version to CSV, JSON, XLSX, or Parquet. CSV/XLSX neutralize formula-like text. JSON/Parquet retain literal values. Exports return authenticated artifact downloads.
- **Statistics:** descriptive statistics, Pearson correlation, independent Welch t-tests with confidence intervals/effect size, and OLS regression. Missing values require an explicit policy. The first regression column is the target; remaining columns are predictors.
- **Documents:** BM25 lexical retrieval, neighboring source reads, and exhaustive regex extraction with typed named groups and exact spans. Extraction counts all matches even when the returned record list is capped.
- **Charts:** bar, line, scatter, histogram, and box plots, generated from saved query results with Matplotlib's `Agg` backend.

`GET /tools` is the authoritative input-schema reference. Tool code is shared by REST, the LLM loop, and MCP.

## Charts, citations, and reports

Answers contain readable `answer` text, a `kind` (`answer`, `clarification`, or `insufficient_evidence`), result/chunk citations, artifact IDs, limitations, and resolved artifact metadata. A PNG artifact includes `download_path`, `mime_type`, `alt_text`, and `data_result_id`. The Flutter frontend displays answers and citations and downloads artifacts with project credentials.

The model receives computed chart data and metadata, not the image pixels. Hermes can explicitly fetch pixels with the MCP `get_chart_image` tool. A URL in a text result does not automatically give a model vision.

HTML/PDF reports embed charts; the ZIP bundle includes a self-contained HTML report, selected output format, result JSON, query CSV exports, chart PNGs, dataset checksums, tool arguments, and dependency versions. Source datasets remain in storage and are downloadable separately. Standalone Markdown uses authenticated artifact paths; Markdown inside the ZIP uses relative image paths. CSV exports neutralize cells that spreadsheet applications could interpret as formulas. HTML preserves multilingual text; PDF base fonts currently have limited Unicode coverage.

## Enable GPT or Claude later

Set these in `.env`, then restart the server:

```dotenv
DATA_AGENT_PROVIDER=openai
DATA_AGENT_MODEL=YOUR_AVAILABLE_OPENAI_MODEL_ID
OPENAI_API_KEY=YOUR_KEY
```

Or:

```dotenv
DATA_AGENT_PROVIDER=anthropic
DATA_AGENT_MODEL=YOUR_AVAILABLE_CLAUDE_MODEL_ID
ANTHROPIC_API_KEY=YOUR_KEY
```

The provider/model can also be selected per request; keys stay on the server. A missing key produces `503 provider_not_configured`; the server never silently substitutes mock reasoning. Only selected dataset content needed for analysis is sent to the configured provider. API adapters use [OpenAI Responses function calling](https://developers.openai.com/api/docs/guides/function-calling) and [Claude Messages tool use](https://platform.claude.com/docs/en/agents-and-tools/tool-use/how-tool-use-works).

Both adapters are covered by simulated tool-call tests. Real model calls have not been tested without API credentials. Citation validation checks reference integrity; it cannot guarantee every sentence is scientifically correct. Inspect saved evidence and methods for consequential analyses.

## Hermes integration

Start the Dataset API, then merge `examples/hermes-mcp.yaml` into your existing `~/.hermes/config.yaml`. The example uses this project's `.venv` Python to run a stdio MCP bridge. Adjust the absolute path if you move the repository. It exposes all analysis tools plus dataset listing, saved-result retrieval, and PNG image retrieval. Hermes supplies the reasoning model; it does not require a second GPT/Claude configuration in this server.

The bridge uses the same API credentials, ownership checks, and worker limits. Set `DATA_AGENT_MCP_API_KEY` in its environment when server authentication is enabled. Restart Hermes or reload its MCP connections as described in the [Hermes MCP documentation](https://hermes-agent.nousresearch.com/docs/user-guide/features/mcp).

If your Hermes installation reports `no dependency environment is committed for this install`, repair it with `hermes pm repair` before attempting the Hermes-side connection. The bridge itself is tested through a real MCP stdio client, including chart image transfer.

## Configuration and operations

Without configured API tokens, access is limited to local clients and trusted localhost hostnames. Browser requests are disabled unless their exact origin is listed in `DATA_AGENT_BROWSER_ORIGINS` (a JSON array; see `.env.example`). Allowlisted origins receive CORS responses and support preflight requests; project authentication still applies. Restart after changing this setting. To expose the API beyond loopback, configure a JSON map from strong tokens to project IDs:

```dotenv
DATA_AGENT_API_KEYS={"YOUR_RANDOM_TOKEN":"research-project"}
```

Send `Authorization: Bearer YOUR_RANDOM_TOKEN` with every data/tool/job/artifact request. The project is derived from the token, never from client-supplied ownership fields. Use a TLS gateway for remote deployment.

Defaults: 25 MB uploads, 500,000 rows, 500 columns, 2 million document characters, two workers, 16 pending jobs, 30 seconds per operation, 1 GB worker RSS, 180 seconds per agent run, and 12 model steps. Configuration names and validated ranges are in `src/agent_dataset/config.py`. Each model request has a maximum 60-second timeout; cancellation during a model request takes effect when that request returns or times out. Tool workers can be terminated immediately.

SQLite and files keep a local installation simple. Job state survives restarts, but interrupted jobs are marked failed and must be resubmitted. Do not run multiple Uvicorn workers against one data directory. Back up `.data/` while the server is stopped. There is no automatic retention/cleanup policy yet.

Trusted tool operations run in time-limited subprocesses with sampled RSS monitoring. This is **not an arbitrary-code sandbox**. Uploaded text is treated as data; generated Python execution is deliberately unavailable. OCR, embeddings/hybrid retrieval, semantic record extraction, distributed Celery workers, PostgreSQL/S3 storage, and a hardened Python sandbox remain extensions from the original plan.

## Trusted plugins

Server-installed packages may register an `agent_dataset.plugins` entry point. Its callable receives `ToolRegistry` and calls `registry.register(Tool(...))` with a Pydantic input schema and handler `(analysis, parsed_arguments) -> (data, artifacts)`. Use `analysis.dataset()`, `analysis.frame()`, `analysis.result()`, and `analysis.artifact()` to enforce ownership and conversation scope. Enable explicit entry point names through `DATA_AGENT_ENABLED_PLUGINS=["name"]`; nothing is loaded from uploaded files. Plugins are trusted server code, not tenant-provided code.

## Docker Compose

Use Docker Desktop with **Linux containers** and Docker Compose 2.24 or newer. The multi-stage Dockerfile installs locked production dependencies into a Linux `/app/.venv`; it never copies the Windows `.venv` or installs packages globally. The final image runs as a non-root user. Compose adds a persistent volume, health checks, resource limits, a read-only root filesystem, and localhost-only port publishing. The build follows the [uv Docker guidance](https://docs.astral.sh/uv/guides/integration/docker/) and [Compose service configuration](https://docs.docker.com/reference/compose-file/services/).

1. Copy `.env.example` to `.env` if you do not already have one.
2. Generate a token for **this API**, using the existing virtual environment:

   ```powershell
   .\.venv\Scripts\python.exe -c "import secrets; print(secrets.token_urlsafe(32))"
   ```

3. Set the following in `.env`, replacing the token with the generated value:

   ```dotenv
   DATA_AGENT_API_KEYS={"YOUR_GENERATED_TOKEN":"local"}
   DATA_AGENT_PROVIDER=offline
   ```

4. Start the service:

   ```powershell
   docker compose up --build -d --wait
   docker compose ps
   curl.exe http://127.0.0.1:8000/health
   ```

The application must bind to `0.0.0.0` **inside** the container, so an API token is required even though the published host port is restricted to localhost. Send `Authorization: Bearer YOUR_GENERATED_TOKEN` for dataset, tool, report, and chat requests. No GPT/Claude key is needed in offline mode. To run the existing demo or connect local Hermes, set `DATA_AGENT_MCP_API_KEY` to that token in the client's environment. Hermes stays installed on the host and connects to the published API; it does not need to be installed in the container.

Set `DATA_AGENT_PORT=8001` in `.env` if port 8000 is in use. The container always listens on port 8000; only the published host port changes. Update the demo/Hermes `DATA_AGENT_API_URL` accordingly.

```powershell
docker compose logs --follow api
docker compose stop
docker compose up -d --wait
# Remove the container/network while keeping saved data:
docker compose down
```

The named `dataset-data` volume stores SQLite metadata, original datasets, normalized files, and artifacts under `/data`. It is separate from the host's existing `.data` directory and survives container recreation. Do not add `--volumes` to `docker compose down` unless you intend to delete that data. Keep one API service instance per volume. The default memory budget is 3 GiB; raise it alongside worker limits for larger workloads.

When LLM keys become available, set the provider/model/key in `.env` as described above and run `docker compose up -d --wait` to recreate the container with the new environment. A plain `docker compose restart` does not reload changed environment values. Keys are supplied at runtime and excluded from the image build context. For image releases, pin the Python/uv image references to tested digests through the Dockerfile build arguments.

## Tests

```powershell
.\.venv\Scripts\python.exe -m pytest -q
.\.venv\Scripts\ruff.exe check src tests examples
.\.venv\Scripts\ruff.exe format --check src tests examples
```

Tests cover ingestion formats, known numerical answers, statistics, transformations, source spans, SQL restrictions, ownership, chart/report files, cancellation/timeouts, restart state, API workflows, MCP interoperability, and provider protocols. Network-enabled tests bind only loopback; they never call paid model services. A restricted Windows sandbox may block Python's local async socket pair, so run the tests in a normal local terminal.
