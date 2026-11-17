import io
import json
import threading

import pandas as pd
import pytest
from fastapi.testclient import TestClient
from pydantic import ValidationError
from test_providers import DirectExecutor

from agent_dataset.agent import Agent
from agent_dataset.api import create_app
from agent_dataset.config import ServiceError
from agent_dataset.models import ChatInput, EditInput
from agent_dataset.providers import Call, Step
from agent_dataset.tools import build_registry


def frame(store, dataset):
    return pd.read_parquet(store.path(store.get("dataset", "local", dataset["id"])["path"]))


def test_edit_positions_append_delete_and_original(execute, sales, store):
    child = execute(
        "edit_dataset",
        {
            "dataset_id": sales["id"],
            "cells": [{"row_index": 2, "column": "revenue", "value": 99}],
            "delete_rows": [0],
            "append_rows": [{"region": "تهران", "revenue": 42, "orders": 3}],
        },
    )["data"]["dataset"]
    assert child["parent_id"] == sales["id"]
    assert frame(store, child)["revenue"].tolist() == [80, 99, 20, 42]
    assert frame(store, sales)["revenue"].tolist() == [100, 80, 50, 20]
    assert frame(store, child).iloc[-1]["region"] == "تهران"


def test_edit_clear_integer_and_delete_all(execute, sales, store):
    child = execute(
        "edit_dataset",
        {
            "dataset_id": sales["id"],
            "cells": [{"row_index": 0, "column": "revenue", "value": None}],
        },
    )["data"]["dataset"]
    assert pd.isna(frame(store, child).iloc[0]["revenue"])
    empty = execute("edit_dataset", {"dataset_id": sales["id"], "delete_rows": [0, 1, 2, 3]})[
        "data"
    ]["dataset"]
    assert empty["rows"] == 0 and len(empty["columns"]) == 3


@pytest.mark.parametrize(
    "arguments",
    [
        {},
        {"delete_rows": [-1]},
        {"cells": [{"row_index": 0, "column": "a", "value": 1}] * 2},
        {"cells": [{"row_index": 0, "column": "a", "value": 1}], "delete_rows": [0]},
    ],
)
def test_edit_validation(arguments):
    with pytest.raises(ValidationError):
        EditInput(dataset_id="dataset_example", **arguments)


@pytest.mark.parametrize(
    "arguments,code",
    [
        ({"delete_rows": [4]}, "invalid_row"),
        ({"cells": [{"row_index": 0, "column": "missing", "value": 0}]}, "unknown_column"),
        ({"append_rows": [{"missing": 0}]}, "unknown_column"),
        ({"cells": [{"row_index": 0, "column": "revenue", "value": "wrong"}]}, "invalid_edit"),
    ],
)
def test_invalid_edit_saves_no_version(execute, sales, store, arguments, code):
    with pytest.raises(ServiceError) as exc:
        execute("edit_dataset", {"dataset_id": sales["id"], **arguments})
    assert exc.value.code == code
    assert len(store.list("dataset", "local")) == 1


def test_transform_chain_and_position_reset(execute, sales, store):
    child = execute(
        "transform_dataset",
        {
            "dataset_id": sales["id"],
            "steps": [
                {
                    "operation": "filter",
                    "conditions": [{"column": "revenue", "operator": "gte", "value": 50}],
                },
                {"operation": "sort", "columns": ["revenue"], "ascending": False},
                {
                    "operation": "calculate",
                    "column": "per_order",
                    "source_column": "revenue",
                    "operator": "divide",
                    "operand_column": "orders",
                },
                {"operation": "drop_columns", "columns": ["orders"]},
                {"operation": "add_column", "column": "source", "value": "آزمون"},
            ],
        },
    )["data"]["dataset"]
    data = frame(store, child)
    assert data["revenue"].tolist() == [100, 80, 50]
    assert data["per_order"].tolist() == [50, 80, 50]
    assert data["source"].tolist() == ["آزمون"] * 3
    assert "orders" not in data.columns
    updated = execute(
        "edit_dataset",
        {"dataset_id": child["id"], "cells": [{"row_index": 1, "column": "revenue", "value": 81}]},
    )["data"]["dataset"]
    assert frame(store, updated)["revenue"].tolist() == [100, 81, 50]


def test_literal_filter_nulls_and_strings(execute, ingest_bytes, store):
    dataset = ingest_bytes("name,n\n  a.b  ,1\nxyz,2\n,3\n")
    child = execute(
        "transform_dataset",
        {
            "dataset_id": dataset["id"],
            "steps": [
                {"operation": "strip", "columns": ["name"]},
                {
                    "operation": "filter",
                    "conditions": [{"column": "name", "operator": "contains", "value": "."}],
                },
                {"operation": "replace", "mapping": {"name": {"a.b": "الف"}}},
            ],
        },
    )["data"]["dataset"]
    assert frame(store, child)["name"].tolist() == ["الف"]
    child = execute(
        "transform_dataset",
        {
            "dataset_id": dataset["id"],
            "steps": [
                {"operation": "filter", "conditions": [{"column": "name", "operator": "is_null"}]}
            ],
        },
    )["data"]["dataset"]
    assert frame(store, child)["n"].tolist() == [3]


@pytest.mark.parametrize(
    "step",
    [
        {"operation": "filter"},
        {"operation": "sort"},
        {
            "operation": "filter",
            "conditions": [{"column": "revenue", "operator": "in", "value": 2}],
        },
        {
            "operation": "calculate",
            "column": "x",
            "source_column": "revenue",
            "operator": "divide",
            "value": 0,
        },
        {"operation": "add_column", "column": "revenue", "value": 1},
        {"operation": "rename", "mapping": {"revenue": "region"}},
    ],
)
def test_invalid_transform_is_atomic(execute, sales, store, step):
    with pytest.raises(ServiceError):
        execute("transform_dataset", {"dataset_id": sales["id"], "steps": [step]})
    assert len(store.list("dataset", "local")) == 1


@pytest.mark.parametrize("fmt", ["csv", "json", "xlsx", "parquet"])
def test_export_full_dataset_and_persian(execute, store, ingest_bytes, fmt):
    dataset = ingest_bytes('name,n\nتهران,1\n"=1+1",2\n')
    result = execute("export_dataset", {"dataset_id": dataset["id"], "format": fmt})
    artifact = store.get("artifact", "local", result["artifacts"][0]["id"])
    content = store.path(artifact["path"]).read_bytes()
    assert result["data"]["rows"] == 2
    if fmt == "json":
        assert json.loads(content)[0]["name"] == "تهران"
    elif fmt == "csv":
        assert "'=1+1" in content.decode("utf-8-sig")
    elif fmt == "xlsx":
        exported = pd.read_excel(io.BytesIO(content))
        assert exported["name"].tolist() == ["تهران", "'=1+1"]
    else:
        assert pd.read_parquet(io.BytesIO(content))["name"].tolist() == ["تهران", "=1+1"]


def test_edit_and_export_scope(execute, sales):
    for name, arguments in [("edit_dataset", {"delete_rows": [0]}), ("export_dataset", {})]:
        with pytest.raises(ServiceError) as error:
            execute(name, {"dataset_id": sales["id"], **arguments}, allowed=[])
        assert error.value.code == "dataset_scope"
        with pytest.raises(ServiceError) as error:
            execute(name, {"dataset_id": sales["id"], **arguments}, tenant="other")
        assert error.value.status == 404


def test_browser_origin_and_auth(settings, sales):
    settings.browser_origins = ["http://localhost:8080"]
    settings.api_keys = {"test-token": "local"}
    with TestClient(create_app(settings)) as client:
        origin = {"Origin": "http://localhost:8080"}
        preflight = client.options(
            "/tools/edit_dataset",
            headers={
                **origin,
                "Access-Control-Request-Method": "POST",
                "Access-Control-Request-Headers": "authorization,content-type",
            },
        )
        assert preflight.status_code == 200
        assert preflight.headers["access-control-allow-origin"] == origin["Origin"]
        unauthorized = client.get("/datasets", headers=origin)
        assert unauthorized.status_code == 401
        assert unauthorized.headers["access-control-allow-origin"] == origin["Origin"]
        assert (
            client.get("/datasets", headers={"Origin": "https://evil.example"}).status_code == 403
        )
        headers = {**origin, "Authorization": "Bearer test-token"}
        edited = client.post(
            "/tools/edit_dataset",
            headers=headers,
            json={
                "arguments": {
                    "dataset_id": sales["id"],
                    "cells": [{"row_index": 1, "column": "revenue", "value": 88}],
                }
            },
        )
        assert edited.status_code == 200, edited.text
        assert edited.headers["access-control-allow-origin"] == origin["Origin"]
        assert edited.json()["data"]["dataset"]["parent_id"] == sales["id"]


def test_browser_disabled_by_default(settings):
    with TestClient(create_app(settings)) as client:
        assert client.get("/health", headers={"Origin": "http://localhost:8080"}).status_code == 403


def test_persian_html_report_direction(execute, sales, store):
    result = execute("profile_dataset", {"dataset_id": sales["id"]})
    report = execute(
        "build_report",
        {
            "title": "گزارش فروش",
            "question": "کیفیت داده را بررسی کن",
            "result_ids": [result["result_id"]],
            "format": "html",
        },
    )
    artifact = store.get("artifact", "local", report["artifacts"][0]["id"])
    content = store.path(artifact["path"]).read_text(encoding="utf-8")
    assert 'lang="fa" dir="rtl"' in content
    assert "یافته‌ها" in content and "شواهد و روش‌ها" in content


def test_agent_can_use_edited_version_in_same_run(store, settings, sales):
    class EditingProvider:
        def __init__(self):
            self.history = []
            self.count = 0

        def step(self, timeout):
            self.count += 1
            if self.count == 1:
                return Step(
                    [Call("c1", "edit_dataset", {"dataset_id": sales["id"], "delete_rows": [0]})],
                    "",
                    {},
                    "tool_use",
                )
            if self.count == 2:
                return Step(
                    [Call("c2", "profile_dataset", {"dataset_id": self.child})], "", {}, "tool_use"
                )
            return Step(
                [
                    Call(
                        "c3",
                        "submit_answer",
                        {"answer": "ویرایش انجام شد", "citations": [{"result_id": self.result}]},
                    )
                ],
                "",
                {},
                "tool_use",
            )

        def tool_results(self, outputs):
            value = outputs[0][1]
            assert value["status"] == "ok", value
            self.result = value["result_id"]
            if self.count == 1:
                self.child = value["data"]["dataset"]["id"]

        def close(self):
            pass

    agent = Agent(store, settings, DirectExecutor(store, settings), lambda *args: EditingProvider())
    conversation = store.put("conversation", "local", {"dataset_ids": [sales["id"]], "turns": []})
    answer = agent.run(
        "local",
        ChatInput(prompt="ردیف اول را حذف کن", dataset_ids=[sales["id"]], provider="openai"),
        "run_test",
        conversation["id"],
        threading.Event(),
        lambda *args: None,
    )
    assert len(answer["dataset_ids"]) == 2
    assert store.get("dataset", "local", answer["dataset_ids"][-1])["rows"] == 3
    assert {"edit_dataset", "export_dataset"} <= set(build_registry().tools)
