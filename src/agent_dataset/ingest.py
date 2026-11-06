import hashlib
import json
import re
import zipfile
from pathlib import Path

from .config import ServiceError, Settings
from .store import Store, identifier

FORMATS = {".csv", ".tsv", ".xlsx", ".parquet", ".json", ".jsonl", ".txt", ".md", ".pdf", ".docx"}


def validate_archive(path: Path, max_bytes: int):
    if path.suffix.lower() in {".xlsx", ".docx"}:
        with zipfile.ZipFile(path) as archive:
            if sum(item.file_size for item in archive.infolist()) > max_bytes * 10:
                raise ServiceError("archive_too_large", "Expanded archive exceeds the size limit")


def save_table(
    store: Store,
    settings: Settings,
    tenant: str,
    frame,
    name: str,
    source: dict,
    parent_id: str | None = None,
    steps: list | None = None,
):
    import pandas as pd

    if len(frame) > settings.max_rows or len(frame.columns) > settings.max_columns:
        raise ServiceError("table_too_large", "Table exceeds configured row or column limit")
    if len(frame.columns) == 0:
        raise ServiceError("empty_schema", "Dataset has no columns")
    frame.columns = [str(c) for c in frame.columns]
    if len(set(frame.columns)) != len(frame.columns):
        raise ServiceError("duplicate_columns", "Column names must be unique after normalization")
    warnings = []
    for column in frame.columns:
        if (
            pd.api.types.is_object_dtype(frame[column])
            and frame[column].map(lambda v: isinstance(v, (dict, list))).any()
        ):
            frame[column] = frame[column].map(
                lambda v: json.dumps(v, ensure_ascii=False) if isinstance(v, (dict, list)) else v
            )
            warnings.append(f"Nested values in {column} were serialized to JSON strings.")
    relative, path = store.allocate("tables", ".parquet")
    try:
        frame.to_parquet(path, index=False)
    except Exception as exc:
        path.unlink(missing_ok=True)
        raise ServiceError(
            "normalization_failed", "Mixed column types; clean the input first"
        ) from exc
    checksum = hashlib.sha256(path.read_bytes()).hexdigest()
    return store.put(
        "dataset",
        tenant,
        {
            "name": name,
            "kind": "table",
            "status": "ready",
            "path": relative,
            "rows": len(frame),
            "columns": [{"name": c, "dtype": str(frame[c].dtype)} for c in frame.columns],
            "sha256": checksum,
            "source": source,
            "parent_id": parent_id,
            "transformations": steps or [],
            "warnings": warnings,
        },
    )


def ingest(
    store: Store,
    settings: Settings,
    tenant: str,
    relative: str,
    filename: str,
    sheet: str | None = None,
) -> dict:
    path = store.path(relative)
    extension = path.suffix.lower()
    validate_archive(path, settings.max_upload_mb * 1024 * 1024)
    source = {
        "filename": filename,
        "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
        "original_path": relative,
        "sheet": sheet,
    }
    if extension in {".csv", ".tsv", ".xlsx", ".parquet", ".json", ".jsonl"}:
        import pandas as pd

        if extension in {".csv", ".tsv"}:
            frame = pd.read_csv(
                path, sep="\t" if extension == ".tsv" else ",", nrows=settings.max_rows + 1
            )
        elif extension == ".xlsx":
            frame = pd.read_excel(
                path,
                sheet_name=sheet if sheet is not None else 0,
                nrows=settings.max_rows + 1,
                engine="openpyxl",
            )
        elif extension == ".parquet":
            import pyarrow.parquet as pq

            metadata = pq.read_metadata(path)
            if metadata.num_rows > settings.max_rows or metadata.num_columns > settings.max_columns:
                raise ServiceError("table_too_large", "Parquet exceeds row or column limits")
            if (
                sum(metadata.row_group(i).total_byte_size for i in range(metadata.num_row_groups))
                > 512 * 1024**2
            ):
                raise ServiceError("table_too_large", "Expanded Parquet exceeds 512 MB")
            frame = pd.read_parquet(path)
        elif extension == ".jsonl":
            frame = pd.read_json(path, lines=True, nrows=settings.max_rows + 1)
        else:
            value = json.loads(path.read_text(encoding="utf-8-sig"))
            if not isinstance(value, list) or any(not isinstance(row, dict) for row in value):
                raise ServiceError(
                    "invalid_json", "JSON must be an array of records; use JSONL for lines"
                )
            frame = pd.json_normalize(value)
        return save_table(store, settings, tenant, frame, filename, source)

    sections: list[tuple[str, str]] = []
    if extension in {".txt", ".md"}:
        sections = [("text", path.read_text(encoding="utf-8-sig"))]
    elif extension == ".pdf":
        from pypdf import PdfReader

        reader = PdfReader(path)
        if reader.is_encrypted:
            raise ServiceError("encrypted_pdf", "Encrypted PDFs are not supported")
        sections = [
            (f"page:{i + 1}", page.extract_text() or "") for i, page in enumerate(reader.pages)
        ]
    elif extension == ".docx":
        from docx import Document

        document = Document(path)
        sections = [(f"paragraph:{i + 1}", p.text) for i, p in enumerate(document.paragraphs)]
        sections += [
            (
                f"table:{i + 1}",
                "\n".join("\t".join(c.text for c in row.cells) for row in table.rows),
            )
            for i, table in enumerate(document.tables)
        ]
    else:
        raise ServiceError("unsupported_format", f"Unsupported extension: {extension}")
    if sum(len(text) for _, text in sections) > settings.max_document_chars:
        raise ServiceError("document_too_large", "Document exceeds the character limit")
    chunks = []
    for location, text in sections:
        # Non-overlapping chunks make exhaustive regex extraction/counts reproducible.
        text = re.sub(r"\x00", "", text)
        for start in range(0, len(text), 2000):
            part = text[start : start + 2000]
            if part.strip():
                chunks.append(
                    {
                        "chunk_id": identifier("chunk"),
                        "location": location,
                        "start": start,
                        "end": start + len(part),
                        "text": part,
                    }
                )
    if not chunks:
        raise ServiceError(
            "no_extractable_text", "No text found; scanned documents require OCR (not enabled)"
        )
    relative_text, text_path = store.allocate("documents", ".json")
    text_path.write_text(json.dumps(chunks, ensure_ascii=False), encoding="utf-8")
    warnings = (
        ["OCR is not enabled; images and scanned pages are not analyzed."]
        if extension == ".pdf"
        else []
    )
    return store.put(
        "dataset",
        tenant,
        {
            "name": filename,
            "kind": "document",
            "status": "ready",
            "path": relative_text,
            "source": source,
            "sha256": source["sha256"],
            "chunk_count": len(chunks),
            "characters": sum(len(c["text"]) for c in chunks),
            "warnings": warnings,
        },
    )


def public_dataset(record: dict) -> dict:
    result = {k: v for k, v in record.items() if k != "path"}
    result["source"] = {k: v for k, v in record.get("source", {}).items() if k != "original_path"}
    return result
