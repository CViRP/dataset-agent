# Dataset Analysis Agent — Implementation Plan

## 1. Goal and scope

Build a professional assistant for data scientists: upload datasets, ask follow-up questions, perform reproducible analysis, and download reports containing evidence, tables, and charts. Support configurable GPT or Claude models through provider adapters.

**Initial formats:** CSV, TSV, XLSX, Parquet, JSON/JSONL for structured or semi-structured data; TXT, Markdown, text-based PDF, and DOCX for documents. Preserve originals; normalize tables to Parquet and documents to text chunks with file/page/section references. Explicitly report parsing failures and unsupported inputs. Add OCR for scanned documents later.

## 2. Architecture and dependencies

```text
Chat/upload UI → FastAPI → Agent loop → GPT / Claude API
                              ↓ validated tool requests
                         Tool registry → Analysis workers
                              ↓                 ↓
                    Metadata + search     Datasets + artifacts
```

- **API:** FastAPI, Pydantic, Uvicorn; official `openai` and `anthropic` SDKs. Keep API keys on the server.
- **Analysis:** pandas, NumPy, PyArrow, openpyxl, DuckDB, SciPy, statsmodels, Matplotlib. Use DuckDB queries and bounded samples when tables exceed pandas memory limits.
- **Documents:** pypdf, python-docx; PostgreSQL full-text search plus pgvector and a configurable embedding provider for hybrid retrieval.
- **Persistence:** PostgreSQL for ownership, dataset versions, conversations, runs, and provenance; local files in development, S3-compatible storage in production.
- **Jobs:** Celery + Redis for ingestion, expensive analysis, and reports; job status, cancellation, timeouts, and SSE progress events. Keep CPU-heavy work outside FastAPI's request/event loop.
- **Reports:** Jinja2 HTML templates and Playwright PDF export; downloadable Markdown and analysis bundles.
- Verify dependency compatibility with the repository's Python `>=3.14` requirement before locking dependencies with uv; adjust the supported Python version if needed.

## 3. FastAPI endpoints and LLM tools

Public endpoints: `POST /datasets` (multipart upload), `GET /datasets/{id}`, `POST /chat`, `POST /reports`, `GET /jobs/{id}`, `POST /jobs/{id}/cancel`, `GET /runs/{id}/events` (SSE), and `GET /artifacts/{id}` (authorized download). Upload/report endpoints return `202` with a job ID; only ready dataset versions can be analyzed.

Expose these typed operations as `POST /tools/{name}` and register their JSON Schemas for the LLM:

| Tool | Main inputs | Output / implementation |
|---|---|---|
| `inspect_dataset` | Dataset version, optional columns | Schema, units if known, row counts, bounded preview, document inventory |
| `profile_dataset` | Version, scope, sampling policy | Missingness, duplicates, distributions, outliers, quality warnings |
| `query_table` | Versions, SQL, result limit | Filter, aggregate, join, window calculations via restricted DuckDB |
| `transform_dataset` | Version, typed transformation steps | New version plus change log; originals remain immutable |
| `statistical_analysis` | Version, method, columns, options | Tests, confidence intervals, effect sizes, regression diagnostics |
| `search_documents` | Versions, query, filters, top-k | Ranked passages with file/page/chunk citations |
| `read_document` | Version, document ID, bounded range | Source context around a retrieved passage |
| `extract_records` | Document IDs, output schema | Validated records with source spans and extraction uncertainty |
| `create_chart` | Result ID, chart type, axes, grouping | Matplotlib PNG artifact, plotted data, labels, description |
| `build_report` | Verified findings, evidence IDs, artifact IDs, format | Downloadable report and reproducibility bundle |

All calls carry a run ID and immutable dataset version IDs. Return a common envelope: `status`, `result_id`, bounded `data`, `artifacts`, `provenance`, `warnings`, and structured `error`. Large results become paginated results or downloadable artifacts. Record filters, sample sizes, sampling seed, methods, and tool versions. Convert NaN/Infinity to JSON-safe values with explicit warnings.

Advanced phase: add `run_python` for custom analysis only after an isolated execution service exists; never execute generated Python inside the API process.

## 4. How the agent calls tools

1. User selects datasets and asks a question; load their authorized versions, schema summaries, and relevant conversation context.
2. Send the question and tool definitions to the selected model. Inspect unfamiliar datasets before choosing an analysis; clarify ambiguous metrics, units, or joins when necessary.
3. The model returns a tool name and JSON arguments. The server validates schema, ownership, limits, and operation policy, then dispatches to the registered implementation. The model does not execute HTTP requests itself.
4. Return results using the provider's protocol: OpenAI Responses `function_call_output` matched by `call_id`; Claude Messages `tool_result` matched by `tool_use_id`. Preserve required conversation items. See [OpenAI function calling](https://developers.openai.com/api/docs/guides/function-calling) and [Claude tool use](https://platform.claude.com/docs/en/agents-and-tools/tool-use/how-tool-use-works).
5. Repeat until the model produces a final answer or reaches a configured time, cost, or tool-call limit. Handle failures, truncated responses, and incomplete jobs explicitly; parallelize only independent reads.
6. Validate the answer's evidence/artifact references before rendering it. Numerical claims must trace to computed results; document claims must cite passages. Retrieval samples are not evidence for corpus-wide counts—use exhaustive extraction plus aggregation for those requests.

Keep one Python service layer behind both REST endpoints and the tool registry; internal calls need not loop through HTTP. Use a small explicit orchestration loop initially, with provider adapters translating a shared tool contract.

## 5. Charts in answers and reports

`create_chart` uses Matplotlib's non-interactive `Agg` backend, saves a PNG, and registers an artifact owned by the dataset's project. It returns, for example:

```json
{
  "artifact_id": "chart_123",
  "mime_type": "image/png",
  "download_path": "/artifacts/chart_123",
  "alt_text": "Monthly revenue by region",
  "data_result_id": "result_456"
}
```

The final answer contains text, citations, and artifact IDs. The frontend resolves authorized artifact URLs and displays the actual chart inline beside the explanation, with a download button. Use authenticated blob loading or short-lived signed URLs. A Markdown client can render `![Monthly revenue](resolved-url)`.

The LLM receives chart metadata and underlying computed values. If visual review is useful, send the PNG separately through the provider's image-input interface using a vision-capable model; a URL inside tool-result text alone does not make the model see the chart. Reports embed the saved image bytes so downloads do not depend on expiring URLs.

## 6. Report workflow

User requests, for example: “Create an exploratory report on sales, compare regions, and summarize customer complaints.” The agent profiles tables, retrieves/extracts document evidence, computes comparisons, generates charts, and drafts findings. Build a report containing the question, executive summary, dataset versions, quality checks, methods, findings, charts/tables, source citations, and limitations.

Return an inline summary with HTML/PDF download links. Include CSV/Parquet result exports and a reproducibility bundle containing SQL, transformations, chart specifications, seeds, dependency versions, and executed Python when applicable. Reuse saved results for follow-up questions against the same versions.

## 7. Plugins, MCP, and Hermes

Implement plugins as trusted server-installed packages exposing a name, version, input/output schemas, permissions, and handler. Start with table, document, statistics, chart, and report plugins; later add read-only database or object-storage connectors.

Expose selected tools through an optional MCP adapter over the same service layer. Assuming “Hermes” means Nous Research's Hermes Agent, it can consume these tools as an external client through its [MCP integration](https://hermes-agent.nousresearch.com/docs/user-guide/features/mcp). Hermes is optional; the FastAPI application owns datasets, permissions, and artifacts. Do not run a second overlapping agent loop inside the default chat flow.

## 8. Quality controls and delivery order

- Enforce project isolation on every dataset, search, job, and artifact access. Treat uploaded text as untrusted data, never agent instructions; send only necessary, policy-approved content to model providers.
- Restrict SQL to approved read-only tables; disable external file/network access, extension loading, and writes. Apply upload, memory, CPU, query, and output limits. Run custom Python in disposable unprivileged containers with no network/secrets, read-only inputs, and capped writable output.
- Require explicit missing-data policies; report uncertainty and statistical assumptions, avoid causal conclusions from correlations, and disclose sampling. Log tool calls, latency, token cost, and failures without logging sensitive dataset contents by default.
- **Milestone 1:** uploads, versioning, inspection/query tools, provider adapters, chat loop, inline PNG charts, and ownership checks.
- **Milestone 2:** document retrieval/extraction, statistical tools, durable jobs, report downloads, and reproducibility exports.
- **Milestone 3:** sandboxed Python, MCP/Hermes integration, additional connectors, and performance hardening.
- **Acceptance:** evaluate both providers on fixed datasets/questions with known answers; verify aggregates, document citations, statistical results, chart values, report downloads, failure recovery, cross-user isolation, prompt injection, and execution limits. Track correctness, latency, and cost per completed analysis.
