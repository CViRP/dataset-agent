from typing import Any, Literal

from pydantic import BaseModel, ConfigDict, Field, model_validator


class Input(BaseModel):
    model_config = ConfigDict(extra="forbid", allow_inf_nan=False)


class DatasetInput(Input):
    dataset_id: str = Field(description="Immutable dataset version ID")


class InspectInput(DatasetInput):
    preview_rows: int = Field(default=5, ge=0, le=20)


class ProfileInput(DatasetInput):
    columns: list[str] | None = None


class QueryInput(Input):
    tables: dict[str, str] = Field(
        min_length=1,
        max_length=5,
        description="Map SQL table aliases to immutable dataset version IDs, e.g. sales: dataset_...",
    )
    sql: str = Field(min_length=1, max_length=20_000)
    limit: int = Field(default=1000, ge=1, le=5000)


Scalar = str | int | float | bool | None


class FilterCondition(Input):
    column: str
    operator: Literal[
        "eq", "ne", "gt", "gte", "lt", "lte", "in", "not_in", "contains", "is_null", "not_null"
    ]
    value: Scalar | list[Scalar] = None


class TransformStep(Input):
    operation: Literal[
        "select",
        "rename",
        "drop_duplicates",
        "drop_nulls",
        "fill_nulls",
        "cast",
        "drop_columns",
        "filter",
        "sort",
        "replace",
        "strip",
        "add_column",
        "calculate",
    ]
    columns: list[str] = Field(default_factory=list)
    mapping: dict[str, Any] = Field(default_factory=dict)
    conditions: list[FilterCondition] = Field(default_factory=list, max_length=20)
    ascending: bool = True
    column: str | None = None
    source_column: str | None = None
    operator: Literal["add", "subtract", "multiply", "divide"] = "add"
    operand_column: str | None = None
    value: Scalar = None


class TransformInput(DatasetInput):
    steps: list[TransformStep] = Field(min_length=1, max_length=20)


class CellEdit(Input):
    row_index: int = Field(ge=0, description="Zero-based row position in this dataset version")
    column: str
    value: Scalar


class EditInput(DatasetInput):
    cells: list[CellEdit] = Field(default_factory=list, max_length=1000)
    delete_rows: list[int] = Field(default_factory=list, max_length=1000)
    append_rows: list[dict[str, Scalar]] = Field(default_factory=list, max_length=1000)

    @model_validator(mode="after")
    def has_edits(self):
        if not (self.cells or self.delete_rows or self.append_rows):
            raise ValueError("Supply cells, delete_rows or append_rows")
        if any(index < 0 for index in self.delete_rows):
            raise ValueError("Row positions must be nonnegative")
        locations = [(cell.row_index, cell.column) for cell in self.cells]
        if len(locations) != len(set(locations)):
            raise ValueError("Each cell may only be edited once per request")
        if any(cell.row_index in self.delete_rows for cell in self.cells):
            raise ValueError("Cannot edit and delete the same row")
        return self


class ExportInput(DatasetInput):
    format: Literal["csv", "json", "xlsx", "parquet"] = "csv"


class StatisticsInput(DatasetInput):
    method: Literal["describe", "correlation", "ttest", "regression"]
    columns: list[str] = Field(min_length=1, max_length=20)
    missing: Literal["error", "drop"] = "error"
    confidence: float = Field(default=0.95, gt=0, lt=1)


class SearchInput(Input):
    dataset_ids: list[str] = Field(min_length=1, max_length=10)
    query: str = Field(min_length=1, max_length=2000)
    top_k: int = Field(default=5, ge=1, le=20)


class ReadDocumentInput(DatasetInput):
    chunk_id: str
    neighbors: int = Field(default=0, ge=0, le=2)


class ExtractInput(DatasetInput):
    pattern: str = Field(
        min_length=1,
        max_length=500,
        description="Regular expression with named groups, e.g. (?P<email>...). Runs in bounded worker.",
    )
    fields: dict[str, Literal["string", "integer", "number"]] = Field(min_length=1, max_length=20)
    limit: int = Field(default=100, ge=1, le=1000)


class ChartInput(Input):
    result_id: str
    chart_type: Literal["bar", "line", "scatter", "histogram", "box"]
    x: str
    y: str | None = None
    title: str = Field(default="", max_length=200)
    x_label: str | None = Field(default=None, max_length=100)
    y_label: str | None = Field(default=None, max_length=100)


class Finding(Input):
    text: str = Field(min_length=1, max_length=4000)
    result_ids: list[str] = Field(min_length=1, max_length=30)


class BuildReportInput(Input):
    title: str = Field(default="Dataset analysis report", max_length=200)
    question: str = Field(default="", max_length=4000)
    result_ids: list[str] = Field(min_length=1, max_length=30)
    artifact_ids: list[str] = Field(default_factory=list, max_length=20)
    findings: list[Finding] = Field(default_factory=list, max_length=30)
    limitations: list[str] = Field(default_factory=list, max_length=30)
    format: Literal["html", "pdf", "markdown"] = "html"


class ChatInput(Input):
    prompt: str = Field(min_length=1, max_length=8000)
    dataset_ids: list[str] = Field(min_length=1, max_length=10)
    conversation_id: str | None = None
    provider: Literal["offline", "openai", "anthropic"] | None = None
    model: str | None = Field(default=None, max_length=200)


class ReportInput(ChatInput):
    format: Literal["html", "pdf", "markdown"] = "html"
    title: str = Field(default="Dataset analysis report", max_length=200)


class Citation(Input):
    result_id: str
    chunk_id: str | None = None


class Answer(Input):
    kind: Literal["answer", "clarification", "insufficient_evidence"] = "answer"
    answer: str = Field(min_length=1, max_length=30_000)
    citations: list[Citation] = Field(default_factory=list, max_length=100)
    artifact_ids: list[str] = Field(default_factory=list, max_length=30)
    limitations: list[str] = Field(default_factory=list, max_length=30)


class ToolRequest(Input):
    arguments: dict[str, Any]


class ToolContext(Input):
    tenant: str
    run_id: str | None = None
    allowed_dataset_ids: list[str] | None = None

    @model_validator(mode="after")
    def valid_tenant(self):
        if not self.tenant:
            raise ValueError("tenant is required")
        return self
