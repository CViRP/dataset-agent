"""Typed dataset mutations: no generated code, expressions, or filesystem inputs."""

import io

from . import models as m
from .config import ServiceError
from .ingest import public_dataset, save_table


def invalid(message):
    raise ServiceError("invalid_transform", message)


def filter_mask(frame, conditions):
    import pandas as pd

    from .tools import columns_exist

    mask = pd.Series(True, index=frame.index)
    for condition in conditions:
        columns_exist(frame, [condition.column])
        series, value, op = frame[condition.column], condition.value, condition.operator
        if op in {"is_null", "not_null"}:
            selected = series.isna() if op == "is_null" else series.notna()
        elif op in {"in", "not_in"}:
            if not isinstance(value, list):
                invalid(f"{op} requires a list value")
            selected = series.isin(value)
            if op == "not_in":
                selected = ~selected
        elif op == "contains":
            if not isinstance(value, str):
                invalid("contains requires a string value")
            selected = series.astype("string").str.contains(value, regex=False, na=False)
        else:
            if value is None or isinstance(value, list):
                invalid("Comparison requires a scalar value; use is_null/not_null for nulls")
            methods = {"eq": "eq", "ne": "ne", "gt": "gt", "gte": "ge", "lt": "lt", "lte": "le"}
            selected = getattr(series, methods[op])(value) & series.notna()
        mask &= selected.fillna(False)
    return mask


def transform_step(frame, step: m.TransformStep):
    """Apply additional operations; called after the legacy cleanup operations."""
    import numpy as np
    import pandas as pd

    from .tools import columns_exist

    op = step.operation
    if op == "drop_columns":
        if not step.columns:
            invalid("drop_columns requires columns")
        frame = frame.drop(columns=step.columns)
    elif op == "filter":
        if not step.conditions:
            invalid("filter requires conditions (combined with AND)")
        frame = frame.loc[filter_mask(frame, step.conditions)]
    elif op == "sort":
        if not step.columns:
            invalid("sort requires columns")
        frame = frame.sort_values(step.columns, ascending=step.ascending, kind="stable")
    elif op == "replace":
        # mapping is {column: {old_value: new_value}}; string keys are literal values.
        columns_exist(frame, step.mapping)
        for column, replacements in step.mapping.items():
            if not isinstance(replacements, dict):
                invalid("replace mapping must map columns to replacement dictionaries")
            frame[column] = frame[column].replace(replacements)
    elif op == "strip":
        if not step.columns:
            invalid("strip requires columns")
        for column in step.columns:
            if not pd.api.types.is_string_dtype(frame[column]):
                invalid("strip requires string columns")
            frame[column] = frame[column].str.strip()
    elif op in {"add_column", "calculate"}:
        if not step.column or not step.column.strip() or step.column in frame.columns:
            invalid("Supply a nonempty, new column name")
        if op == "add_column":
            frame[step.column] = step.value
        else:
            if not step.source_column:
                invalid("calculate requires source_column")
            columns_exist(frame, [step.source_column])
            left = frame[step.source_column]
            if not pd.api.types.is_numeric_dtype(left) or pd.api.types.is_bool_dtype(left):
                invalid("calculate requires numeric columns")
            if step.operand_column:
                columns_exist(frame, [step.operand_column])
                right = frame[step.operand_column]
                if not pd.api.types.is_numeric_dtype(right) or pd.api.types.is_bool_dtype(right):
                    invalid("calculate requires numeric operands")
            else:
                right = step.value
                if isinstance(right, bool) or not isinstance(right, (int, float)):
                    invalid("calculate requires a numeric value or operand_column")
            if step.operator == "divide":
                zero = (right == 0).any() if isinstance(right, pd.Series) else right == 0
                if zero:
                    invalid("Division by zero; filter or fill zero denominators first")
            result = getattr(
                left,
                {"add": "add", "subtract": "sub", "multiply": "mul", "divide": "div"}[
                    step.operator
                ],
            )(right)
            if np.isinf(result.dropna().astype(float)).any():
                invalid("Calculation produced non-finite values")
            frame[step.column] = result
    return frame.reset_index(drop=True)


def save_child(a, dataset_id, frame, steps):
    parent = a.dataset(dataset_id)
    child = save_table(
        a.store,
        a.settings,
        a.tenant,
        frame.reset_index(drop=True),
        parent["name"],
        parent["source"],
        parent_id=parent["id"],
        steps=steps,
    )
    return {"dataset": public_dataset(child)}, []


def edit(a, args: m.EditInput):
    import pandas as pd

    from .tools import columns_exist

    frame = a.frame(args.dataset_id).reset_index(drop=True)
    positions = args.delete_rows + [cell.row_index for cell in args.cells]
    if any(index >= len(frame) for index in positions):
        raise ServiceError("invalid_row", "Row position is outside this dataset version")
    columns_exist(frame, [cell.column for cell in args.cells])
    for row in args.append_rows:
        columns_exist(frame, row)
    if len(frame) - len(set(args.delete_rows)) + len(args.append_rows) > a.settings.max_rows:
        raise ServiceError("table_too_large", "Edited table exceeds the row limit")
    try:
        for cell in args.cells:
            # Nullable integer/boolean types support explicitly clearing a value.
            dtype = frame[cell.column].dtype
            if cell.value is None and pd.api.types.is_integer_dtype(dtype):
                frame[cell.column] = frame[cell.column].astype("Int64")
            elif cell.value is None and pd.api.types.is_bool_dtype(dtype):
                frame[cell.column] = frame[cell.column].astype("boolean")
            frame.at[cell.row_index, cell.column] = cell.value
        frame = frame.drop(index=list(set(args.delete_rows)))
        if args.append_rows:
            frame = pd.concat(
                [frame, pd.DataFrame(args.append_rows, columns=frame.columns)], ignore_index=True
            )
    except (ValueError, TypeError, OverflowError) as exc:
        raise ServiceError(
            "invalid_edit", "Value is incompatible with the column type; cast first"
        ) from exc
    return save_child(
        a,
        args.dataset_id,
        frame,
        [{"operation": "edit", **args.model_dump(exclude={"dataset_id"})}],
    )


def export(a, args: m.ExportInput):
    from .tools import safe_csv

    frame = a.frame(args.dataset_id)
    if args.format == "csv":
        content, mime = safe_csv(frame), "text/csv"
    elif args.format == "json":
        content = frame.to_json(orient="records", date_format="iso", force_ascii=False).encode(
            "utf-8"
        )
        mime = "application/json"
    elif args.format == "parquet":
        content, mime = frame.to_parquet(index=False), "application/vnd.apache.parquet"
    else:
        # Reuse CSV's formula neutralization for spreadsheet strings.
        safe = pd_safe_excel(frame)
        buffer = io.BytesIO()
        safe.to_excel(buffer, index=False, engine="openpyxl")
        content, mime = (
            buffer.getvalue(),
            "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        )
    artifact = a.store.artifact(
        a.tenant, content, f".{args.format}", mime, f"dataset.{args.format}", [args.dataset_id]
    )
    return {"dataset_id": args.dataset_id, "format": args.format, "rows": len(frame)}, [artifact]


def pd_safe_excel(frame):
    result = frame.copy()
    for column in frame:
        result[column] = frame[column].map(
            lambda value: (
                "'" + value
                if isinstance(value, str)
                and value.lstrip().startswith(("=", "+", "-", "@", "\t", "\r"))
                else value
            )
        )
    return result
