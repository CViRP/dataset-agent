"""Typed, reproducible analysis operations shared by REST, the agent, and MCP."""

import io
import json
import math
import re
from collections.abc import Callable
from dataclasses import dataclass
from importlib.metadata import entry_points, version

from pydantic import BaseModel

from . import models as m
from .config import ServiceError, Settings
from .ingest import public_dataset, save_table
from .store import Store, clean


@dataclass
class Tool:
    name: str
    description: str
    schema: type[BaseModel]
    handler: Callable
    permission: str = "read"
    plugin: str = "builtin"


class ToolRegistry:
    def __init__(self):
        self.tools: dict[str, Tool] = {}

    def register(self, tool: Tool):
        if tool.name in self.tools or not re.fullmatch(r"[a-z][a-z0-9_]{0,63}", tool.name):
            raise ValueError(f"Invalid or duplicate tool: {tool.name}")
        self.tools[tool.name] = tool

    def definitions(self) -> list[dict]:
        return [
            {
                "name": t.name,
                "description": t.description,
                "input_schema": t.schema.model_json_schema(),
                "permission": t.permission,
                "plugin": t.plugin,
                "version": "1",
            }
            for t in self.tools.values()
        ]


class Analysis:
    def __init__(self, store: Store, settings: Settings, context: m.ToolContext):
        self.store, self.settings, self.context = store, settings, context
        self.dataset_ids: set[str] = set()
        self.warnings: list[str] = []

    @property
    def tenant(self):
        return self.context.tenant

    def check_scope(self, ids: list[str]):
        allowed = self.context.allowed_dataset_ids
        if allowed is not None and not set(ids).issubset(allowed):
            raise ServiceError(
                "dataset_scope", "Tool references datasets outside this conversation", 403
            )

    def dataset(self, dataset_id: str, kind: str | None = None) -> dict:
        self.check_scope([dataset_id])
        dataset = self.store.get("dataset", self.tenant, dataset_id)
        if kind and dataset["kind"] != kind:
            raise ServiceError("wrong_dataset_type", f"This operation requires a {kind} dataset")
        self.dataset_ids.add(dataset_id)
        self.warnings.extend(dataset.get("warnings", []))
        return dataset

    def frame(self, dataset_id: str):
        import pandas as pd

        dataset = self.dataset(dataset_id, "table")
        return pd.read_parquet(self.store.path(dataset["path"]))

    def chunks(self, dataset_id: str) -> list[dict]:
        dataset = self.dataset(dataset_id, "document")
        return json.loads(self.store.path(dataset["path"]).read_text(encoding="utf-8"))

    def result(self, result_id: str) -> dict:
        result = self.store.get("result", self.tenant, result_id)
        ids = result["provenance"]["dataset_ids"]
        self.check_scope(ids)
        self.dataset_ids.update(ids)
        return result

    def artifact(self, artifact_id: str) -> dict:
        artifact = self.store.get("artifact", self.tenant, artifact_id)
        self.check_scope(artifact["dataset_ids"])
        self.dataset_ids.update(artifact["dataset_ids"])
        return artifact

    def execute(self, registry: ToolRegistry, name: str, arguments: dict) -> dict:
        if name not in registry.tools:
            raise ServiceError("unknown_tool", f"Unknown tool: {name}", 404)
        tool = registry.tools[name]
        parsed = tool.schema.model_validate(arguments)
        data, artifacts = tool.handler(self, parsed)
        provenance = {
            "dataset_ids": sorted(self.dataset_ids),
            "run_id": self.context.run_id,
            "tool": name,
            "tool_version": "1",
            "arguments": parsed.model_dump(),
            "libraries": {p: version(p) for p in ("pandas", "numpy", "duckdb", "matplotlib")},
        }
        # A generic notice makes conversion of undefined numerical results explicit.
        warnings = list(dict.fromkeys(self.warnings))
        if contains_nonfinite(data):
            warnings.append("Undefined or non-finite values are represented as null.")
        result = self.store.put(
            "result",
            self.tenant,
            {
                "status": "ok",
                "data": clean(data),
                "artifacts": artifacts,
                "provenance": provenance,
                "warnings": warnings,
                "error": None,
            },
        )
        return result_envelope(result)


def contains_nonfinite(value):
    if isinstance(value, dict):
        return any(contains_nonfinite(v) for v in value.values())
    if isinstance(value, (list, tuple)):
        return any(contains_nonfinite(v) for v in value)
    if isinstance(value, float):
        return not math.isfinite(value)
    return False


def result_envelope(result: dict, preview_rows: int = 100) -> dict:
    data = dict(result["data"])
    if isinstance(data.get("rows"), list):
        data["returned_rows"] = len(data["rows"])
        data["rows"] = data["rows"][:preview_rows]
        data["preview_truncated"] = data["returned_rows"] > preview_rows
    return {
        "status": result["status"],
        "result_id": result["id"],
        "data": data,
        "artifacts": result["artifacts"],
        "provenance": result["provenance"],
        "warnings": result["warnings"],
        "error": result["error"],
    }


def columns_exist(frame, columns):
    missing = set(columns) - set(frame.columns)
    if missing:
        raise ServiceError("unknown_column", f"Unknown columns: {', '.join(sorted(missing))}")


def inspect(a: Analysis, args: m.InspectInput):
    dataset = a.dataset(args.dataset_id)
    data = {"dataset": public_dataset(dataset)}
    if dataset["kind"] == "table":
        frame = a.frame(args.dataset_id)
        data["rows"] = json.loads(
            frame.head(args.preview_rows).to_json(orient="records", date_format="iso")
        )
    else:
        data["chunks"] = a.chunks(args.dataset_id)[: args.preview_rows]
    return data, []


def profile(a: Analysis, args: m.ProfileInput):
    import numpy as np
    import pandas as pd

    frame = a.frame(args.dataset_id)
    if args.columns is not None:
        columns_exist(frame, args.columns)
        frame = frame[args.columns]
    descriptions = {}
    for column in frame:
        series = frame[column]
        description = {
            "dtype": str(series.dtype),
            "missing": int(series.isna().sum()),
            "unique": int(series.nunique()),
            "non_null": int(series.notna().sum()),
        }
        if pd.api.types.is_numeric_dtype(series) and not pd.api.types.is_bool_dtype(series):
            numeric = series.replace([np.inf, -np.inf], np.nan).dropna()
            description.update(numeric.describe().to_dict())
            description["nonfinite"] = int(series.notna().sum() - len(numeric))
            if len(numeric):
                q1, q3 = numeric.quantile([0.25, 0.75])
                description["iqr_outliers"] = int(
                    ((numeric < q1 - 1.5 * (q3 - q1)) | (numeric > q3 + 1.5 * (q3 - q1))).sum()
                )
        else:
            description["top_values"] = [
                {"value": clean(k), "count": int(v)}
                for k, v in series.value_counts().head(10).items()
            ]
        descriptions[column] = clean(description)
    return {
        "row_count": len(frame),
        "column_count": len(frame.columns),
        "duplicate_rows": int(frame.duplicated().sum()),
        "columns": descriptions,
        "sampled": False,
    }, []


def query(a: Analysis, args: m.QueryInput):
    import duckdb
    import numpy as np
    import pyarrow.parquet as pq
    import sqlglot
    from sqlglot import exp

    for alias in args.tables:
        if not re.fullmatch(r"[A-Za-z][A-Za-z0-9_]{0,63}", alias):
            raise ServiceError("invalid_alias", "SQL aliases must be simple identifiers")
    if len({alias.casefold() for alias in args.tables}) != len(args.tables):
        raise ServiceError("invalid_alias", "SQL aliases must be unique ignoring case")
    try:
        statements = sqlglot.parse(args.sql, read="duckdb")
    except sqlglot.errors.ParseError as exc:
        raise ServiceError("invalid_sql", "SQL could not be parsed") from exc
    if len(statements) != 1 or not isinstance(
        statements[0], (exp.Select, exp.Union, exp.Intersect, exp.Except)
    ):
        raise ServiceError("unsafe_sql", "Only one read-only SELECT query is allowed")
    tree = statements[0]
    forbidden = (exp.Insert, exp.Update, exp.Delete, exp.Create, exp.Drop, exp.Command, exp.Into)
    if any(isinstance(node, forbidden) for node in tree.walk()):
        raise ServiceError("unsafe_sql", "SQL mutations and commands are disabled")
    ctes = {node.alias.lower() for node in tree.find_all(exp.CTE)}
    allowed = {name.lower() for name in args.tables} | ctes
    for table in tree.find_all(exp.Table):
        if (
            not isinstance(table.this, exp.Identifier)
            or table.db
            or table.catalog
            or table.name.lower() not in allowed
        ):
            raise ServiceError(
                "unsafe_sql", "Only explicitly registered dataset tables are available"
            )
    # Block dynamic query functions even when used in expression positions.
    for function in tree.find_all(exp.Func):
        name = (
            function.name.lower()
            if isinstance(function, exp.Anonymous)
            else function.sql_name().lower()
        )
        if name.startswith(("read_", "scan_", "pragma_", "sqlite_", "postgres_")) or name in {
            "query",
            "query_table",
            "glob",
            "getenv",
            "current_setting",
            "write_log",
            "http_get",
        }:
            raise ServiceError(
                "unsafe_sql", "External access and dynamic SQL functions are disabled"
            )
    connection = duckdb.connect(
        config={
            "enable_external_access": "false",
            "autoload_known_extensions": "false",
            "autoinstall_known_extensions": "false",
            "threads": "2",
            "memory_limit": a.settings.sql_memory_limit,
        }
    )
    try:
        for alias, dataset_id in args.tables.items():
            dataset = a.dataset(dataset_id, "table")
            connection.register(alias, pq.read_table(a.store.path(dataset["path"])))
        limit = min(args.limit, a.settings.max_result_rows)
        frame = connection.execute(
            f"SELECT * FROM ({tree.sql(dialect='duckdb')}) AS result LIMIT {limit + 1}"
        ).fetchdf()
    except duckdb.Error as exc:
        raise ServiceError("query_failed", str(exc)[:1000]) from exc
    finally:
        connection.close()
    truncated = len(frame) > limit
    frame = frame.head(limit)
    if len(set(frame.columns)) != len(frame.columns):
        raise ServiceError("duplicate_columns", "Use unique column aliases in the SELECT")
    if truncated:
        a.warnings.append(f"Result capped at {limit} rows. Aggregate in SQL for complete totals.")
    numeric = frame.select_dtypes(include="number").to_numpy(dtype=float, na_value=np.nan)
    if np.isinf(numeric).any():
        a.warnings.append("Infinite query values are represented as null in JSON.")
    rows = json.loads(frame.to_json(orient="records", date_format="iso"))
    artifact = a.store.artifact(
        a.tenant,
        safe_csv(frame),
        ".csv",
        "text/csv",
        "query-result.csv",
        sorted(a.dataset_ids),
        truncated=truncated,
    )
    return {
        "columns": list(frame.columns),
        "rows": rows,
        "truncated": truncated,
        "row_count": len(frame),
        "sql": args.sql,
    }, [artifact]


def safe_csv(frame) -> bytes:
    # Spreadsheet programs may evaluate formula-looking cells from untrusted data.
    export = frame.copy()
    for column in export:
        export[column] = export[column].map(
            lambda v: (
                "'" + v
                if isinstance(v, str) and v.lstrip().startswith(("=", "+", "-", "@", "\t", "\r"))
                else v
            )
        )
    return export.to_csv(index=False).encode("utf-8-sig")


def transform(a: Analysis, args: m.TransformInput):
    frame = a.frame(args.dataset_id)
    for step in args.steps:
        columns_exist(frame, step.columns)
        if step.operation == "select":
            if not step.columns:
                raise ServiceError("invalid_transform", "select requires columns")
            frame = frame[step.columns]
        elif step.operation == "rename":
            columns_exist(frame, step.mapping)
            if any(not isinstance(v, str) or not v for v in step.mapping.values()):
                raise ServiceError("invalid_transform", "New names must be nonempty strings")
            frame = frame.rename(columns=step.mapping)
        elif step.operation == "drop_duplicates":
            frame = frame.drop_duplicates(subset=step.columns or None)
        elif step.operation == "drop_nulls":
            frame = frame.dropna(subset=step.columns or None)
        elif step.operation == "fill_nulls":
            columns_exist(frame, step.mapping)
            frame = frame.fillna(step.mapping)
        elif step.operation == "cast":
            columns_exist(frame, step.mapping)
            supported = {"string", "Int64", "Float64", "boolean", "datetime64[ns]"}
            if any(dtype not in supported for dtype in step.mapping.values()):
                raise ServiceError("invalid_dtype", f"Supported cast types: {sorted(supported)}")
            frame = frame.astype(step.mapping)
    parent = a.dataset(args.dataset_id)
    child = save_table(
        a.store,
        a.settings,
        a.tenant,
        frame,
        parent["name"],
        parent["source"],
        parent_id=parent["id"],
        steps=[step.model_dump() for step in args.steps],
    )
    return {"dataset": public_dataset(child)}, []


def statistics(a: Analysis, args: m.StatisticsInput):
    import numpy as np
    import pandas as pd
    from scipy import stats

    frame = a.frame(args.dataset_id)
    columns_exist(frame, args.columns)
    frame = frame[args.columns]
    if any(not pd.api.types.is_numeric_dtype(frame[c]) for c in frame):
        raise ServiceError("not_numeric", "Statistical columns must be numeric")
    frame = frame.replace([np.inf, -np.inf], np.nan)
    before = len(frame)
    if frame.isna().any().any() and args.missing == "error":
        raise ServiceError(
            "missing_values", "Missing/non-finite values found; set missing='drop' explicitly"
        )
    if args.method == "ttest":
        if len(args.columns) != 2:
            raise ServiceError(
                "invalid_columns", "Welch t-test requires two independent sample columns"
            )
        x, y = (frame[c].dropna().to_numpy(dtype=float) for c in args.columns)
        if min(len(x), len(y)) < 2:
            raise ServiceError("insufficient_data", "Each sample needs at least two observations")
        test = stats.ttest_ind(x, y, equal_var=False)
        interval = test.confidence_interval(args.confidence)
        pooled = np.sqrt(
            ((len(x) - 1) * x.var(ddof=1) + (len(y) - 1) * y.var(ddof=1)) / (len(x) + len(y) - 2)
        )
        data = {
            "method": "Welch independent t-test",
            "n": [len(x), len(y)],
            "dropped": [before - len(x), before - len(y)],
            "statistic": float(test.statistic),
            "p_value": float(test.pvalue),
            "mean_difference": float(x.mean() - y.mean()),
            "confidence": args.confidence,
            "confidence_interval": [float(interval.low), float(interval.high)],
            "cohens_d": float((x.mean() - y.mean()) / pooled) if pooled else None,
            "assumptions": [
                "Independent samples",
                "Check distribution and outliers for small samples",
            ],
        }
    else:
        frame = frame.dropna().astype(float)
        if len(frame) < 2:
            raise ServiceError("insufficient_data", "At least two complete rows are required")
        data = {"method": args.method, "n": len(frame), "dropped_rows": before - len(frame)}
        if args.method == "describe":
            data["statistics"] = frame.describe().to_dict()
        elif args.method == "correlation":
            if len(args.columns) < 2:
                raise ServiceError("invalid_columns", "Correlation requires at least two columns")
            data["pearson"] = frame.corr().to_dict()
            data["assumptions"] = ["Linear relationships; correlation does not establish causation"]
        else:
            import statsmodels.api as sm

            if len(args.columns) < 2 or len(frame) <= len(args.columns):
                raise ServiceError(
                    "insufficient_data",
                    "Regression needs a target, predictors, and more rows than parameters",
                )
            design = sm.add_constant(frame[args.columns[1:]], has_constant="add")
            if np.linalg.matrix_rank(design.to_numpy()) < design.shape[1]:
                raise ServiceError(
                    "singular_design", "Regression predictors are linearly dependent"
                )
            fit = sm.OLS(frame[args.columns[0]], design).fit()
            data.update(
                target=args.columns[0],
                coefficients=fit.params.to_dict(),
                p_values=fit.pvalues.to_dict(),
                r_squared=fit.rsquared,
                confidence=args.confidence,
                confidence_intervals=fit.conf_int(alpha=1 - args.confidence).T.to_dict("list"),
                condition_number=fit.condition_number,
                assumptions=[
                    "Linear model",
                    "Independent, homoscedastic residuals",
                    "Inspect residuals; this is descriptive, not causal",
                ],
            )
    a.warnings.append("Exploratory inference; multiple-comparison corrections are not applied.")
    return data, []


def search(a: Analysis, args: m.SearchInput):
    from collections import Counter

    tokenize = lambda text: re.findall(r"\w+", text.casefold())
    terms = set(tokenize(args.query))
    corpus = [
        (dataset_id, chunk) for dataset_id in args.dataset_ids for chunk in a.chunks(dataset_id)
    ]
    counters = [Counter(tokenize(chunk["text"])) for _, chunk in corpus]
    average = sum(sum(c.values()) for c in counters) / max(len(counters), 1)
    frequencies = {term: sum(term in c for c in counters) for term in terms}
    hits = []
    for (dataset_id, chunk), counter in zip(corpus, counters):
        score = 0.0
        length = sum(counter.values())
        for term in terms:
            tf = counter.get(term, 0)
            if tf:
                idf = math.log(
                    1 + (len(corpus) - frequencies[term] + 0.5) / (frequencies[term] + 0.5)
                )
                score += idf * tf * 2.2 / (tf + 1.2 * (0.25 + 0.75 * length / max(average, 1)))
        if score:
            hits.append({**chunk, "dataset_id": dataset_id, "score": score})
    hits.sort(key=lambda hit: hit["score"], reverse=True)
    a.warnings.append("Lexical BM25 retrieval; top passages are not an exhaustive corpus analysis.")
    return {
        "hits": hits[: args.top_k],
        "matching_chunks": len(hits),
        "total_chunks": len(corpus),
    }, []


def read_document(a: Analysis, args: m.ReadDocumentInput):
    chunks = a.chunks(args.dataset_id)
    index = next((i for i, c in enumerate(chunks) if c["chunk_id"] == args.chunk_id), None)
    if index is None:
        raise ServiceError("not_found", "Chunk not found", 404)
    return {"chunks": chunks[max(0, index - args.neighbors) : index + args.neighbors + 1]}, []


def extract(a: Analysis, args: m.ExtractInput):
    try:
        pattern = re.compile(args.pattern)
    except re.error as exc:
        raise ServiceError("invalid_pattern", "Invalid regular expression") from exc
    if set(pattern.groupindex) != set(args.fields):
        raise ServiceError("invalid_fields", "Named regex groups must match fields exactly")
    chunks = a.chunks(args.dataset_id)
    # Reassemble each source section so matches crossing chunk boundaries are not lost.
    sections = {}
    for chunk in chunks:
        sections.setdefault(chunk["location"], []).append(chunk)
    records = []
    count = 0
    for location, parts in sections.items():
        text = "".join(c["text"] for c in parts)
        for match in pattern.finditer(text):
            count += 1
            if len(records) >= args.limit:
                continue
            values = {}
            for field, dtype in args.fields.items():
                raw = match.group(field)
                try:
                    value = (
                        {"string": str, "integer": int, "number": float}[dtype](raw)
                        if raw is not None
                        else None
                    )
                    if isinstance(value, float) and not math.isfinite(value):
                        raise ValueError("Nonfinite")
                    values[field] = value
                except (ValueError, TypeError) as exc:
                    raise ServiceError(
                        "extraction_type_error", f"Match does not satisfy field type: {field}"
                    ) from exc
            records.append(
                {
                    "values": values,
                    "source": {
                        "location": location,
                        "start": match.start(),
                        "end": match.end(),
                        "quote": match.group(0),
                        "chunk_ids": [
                            c["chunk_id"]
                            for c in parts
                            if c["start"] < match.end() and c["end"] > match.start()
                        ],
                    },
                }
            )
    a.warnings.append("Regex matches are exact; semantic extraction and OCR are not enabled.")
    return {"records": records, "total_matches": count, "truncated": count > args.limit}, []


def chart(a: Analysis, args: m.ChartInput):
    import matplotlib

    matplotlib.use("Agg")
    import pandas as pd
    from matplotlib.backends.backend_agg import FigureCanvasAgg
    from matplotlib.figure import Figure

    result = a.result(args.result_id)
    rows = result["data"].get("rows")
    if not isinstance(rows, list) or not rows:
        raise ServiceError("no_chart_data", "Chart requires a nonempty tabular query result")
    frame = pd.DataFrame(rows)
    columns_exist(frame, [args.x] + ([args.y] if args.y else []))
    if args.chart_type in {"bar", "line", "scatter"} and not args.y:
        raise ServiceError("missing_y", "This chart requires a y column")
    if args.chart_type in {"histogram", "box"} and args.y:
        raise ServiceError("unexpected_y", "Histogram and box plots use only the numeric x column")
    if args.chart_type == "bar" and len(frame) > 100:
        raise ServiceError("too_many_categories", "Aggregate to at most 100 bars before plotting")
    numeric_columns = [args.y] if args.y else [args.x]
    if args.chart_type == "scatter":
        numeric_columns.append(args.x)
    if any(not pd.api.types.is_numeric_dtype(frame[c]) for c in numeric_columns):
        raise ServiceError("not_numeric", "Chart value axes must be numeric")
    figure = Figure(figsize=(10, 6), dpi=150, layout="constrained")
    FigureCanvasAgg(figure)
    axes = figure.subplots()
    if args.chart_type == "bar":
        axes.bar(frame[args.x].astype(str), frame[args.y])
        axes.tick_params(axis="x", labelrotation=40)
    elif args.chart_type == "line":
        axes.plot(frame[args.x], frame[args.y], marker="o")
    elif args.chart_type == "scatter":
        axes.scatter(frame[args.x], frame[args.y], alpha=0.7)
    elif args.chart_type == "histogram":
        axes.hist(frame[args.x].dropna(), bins="auto")
    else:
        axes.boxplot(frame[args.x].dropna())
    title = args.title or f"{args.chart_type.title()}: {args.x}" + (
        f" / {args.y}" if args.y else ""
    )
    axes.set(
        title=title,
        xlabel=args.x_label or args.x,
        ylabel=args.y_label or args.y or ("Count" if args.chart_type == "histogram" else args.x),
    )
    axes.grid(axis="y", alpha=0.2)
    buffer = io.BytesIO()
    figure.savefig(buffer, format="png", metadata={"Software": "agent-dataset"})
    figure.clear()
    artifact = a.store.artifact(
        a.tenant,
        buffer.getvalue(),
        ".png",
        "image/png",
        "chart.png",
        sorted(a.dataset_ids),
        alt_text=title,
        data_result_id=args.result_id,
        chart_spec=args.model_dump(),
    )
    if result["data"].get("truncated"):
        a.warnings.append(
            "Chart uses a truncated query result; it does not represent the full dataset."
        )
    return {
        "artifact_id": artifact["id"],
        "alt_text": title,
        "data_result_id": args.result_id,
        "plotted_rows": len(frame),
    }, [artifact]


def build_registry(enabled_plugins: list[str] | None = None) -> ToolRegistry:
    from .reports import build_report

    registry = ToolRegistry()
    definitions = [
        (
            "inspect_dataset",
            "Inspect schema and a bounded preview before analysis.",
            m.InspectInput,
            inspect,
            "read",
        ),
        (
            "profile_dataset",
            "Full-table quality, missingness, distributions and IQR outliers.",
            m.ProfileInput,
            profile,
            "read",
        ),
        (
            "query_table",
            "Read-only DuckDB SQL over named dataset tables. Compute aggregates here.",
            m.QueryInput,
            query,
            "read",
        ),
        (
            "transform_dataset",
            "Create a new immutable version using explicit transformations.",
            m.TransformInput,
            transform,
            "write_derived",
        ),
        (
            "statistical_analysis",
            "Descriptive statistics, Pearson correlation, Welch t-test or OLS; explicit missing policy.",
            m.StatisticsInput,
            statistics,
            "read",
        ),
        (
            "search_documents",
            "BM25 keyword retrieval with source chunk citations; not exhaustive counts.",
            m.SearchInput,
            search,
            "read",
        ),
        (
            "read_document",
            "Read a cited chunk and optional neighboring chunks.",
            m.ReadDocumentInput,
            read_document,
            "read",
        ),
        (
            "extract_records",
            "Exhaustive regex extraction with typed named groups and exact source spans.",
            m.ExtractInput,
            extract,
            "read",
        ),
        (
            "create_chart",
            "Render a Matplotlib PNG from saved query rows; returns an artifact ID.",
            m.ChartInput,
            chart,
            "write_derived",
        ),
        (
            "build_report",
            "Render evidence and PNGs to HTML, PDF or Markdown, with a reproducibility ZIP.",
            m.BuildReportInput,
            build_report,
            "write_derived",
        ),
    ]
    for name, description, schema, handler, permission in definitions:
        registry.register(Tool(name, description, schema, handler, permission))
    installed = {ep.name: ep for ep in entry_points(group="agent_dataset.plugins")}
    for name in enabled_plugins or []:
        if name not in installed:
            raise RuntimeError(f"Configured plugin is not installed: {name}")
        installed[name].load()(registry)
    return registry
