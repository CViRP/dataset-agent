import time

from fastapi.testclient import TestClient

from agent_dataset.api import create_app


def wait(client, job, headers=None):
    deadline = time.monotonic() + 150
    while time.monotonic() < deadline:
        response = client.get(f"/jobs/{job['id']}", headers=headers)
        assert response.status_code == 200, response.text
        result = response.json()
        if result["status"] in {"succeeded", "failed", "cancelled"}:
            return result
        time.sleep(0.1)
    raise AssertionError("Job did not finish")


def test_api_offline_end_to_end(settings):
    with TestClient(create_app(settings)) as client:
        assert client.get("/health").json()["status"] == "ok"
        assert client.get("/docs").status_code == 404
        assert client.get("/openapi.json").status_code == 200
        response = client.post(
            "/datasets",
            files={"file": ("sales.csv", b"region,revenue\nNorth,100\nSouth,80\nNorth,50\n")},
        )
        assert response.status_code == 202, response.text
        job = wait(client, response.json())
        assert job["status"] == "succeeded", job
        dataset_id = job["result"]["id"]
        assert "path" not in client.get(f"/datasets/{dataset_id}").json()
        assert client.get(f"/datasets/{dataset_id}/download").content[:4] == b"PAR1"
        assert client.get(f"/datasets/{dataset_id}/download?original=true").content.startswith(
            b"region,revenue"
        )
        response = client.post(
            "/chat",
            json={
                "prompt": "Summarize the dataset",
                "dataset_ids": [dataset_id],
                "provider": "offline",
            },
        )
        assert response.status_code == 202, response.text
        answer_job = wait(client, response.json())
        assert answer_job["status"] == "succeeded", answer_job
        answer = answer_job["result"]
        assert "3 rows" in answer["answer"]
        assert answer["citations"]
        events = client.get(f"/runs/{answer['run_id']}/events").text
        assert "event: completed" in events
        assert "event: tool_completed" in events
        response = client.post(
            "/reports",
            json={"prompt": "Sales report", "dataset_ids": [dataset_id], "format": "pdf"},
        )
        report_job = wait(client, response.json())
        assert report_job["status"] == "succeeded", report_job
        report = next(
            a for a in report_job["result"]["artifacts"] if a["mime_type"] == "application/pdf"
        )
        assert client.get(report["download_path"]).content.startswith(b"%PDF")
        followup = client.post(
            "/chat",
            json={
                "prompt": "Again",
                "dataset_ids": [dataset_id],
                "conversation_id": answer["conversation_id"],
            },
        )
        assert wait(client, followup.json())["status"] == "succeeded"


def test_auth_artifact_job_and_result_isolation(settings, sales, execute):
    settings.api_keys = {"alpha-token": "local", "beta-token": "other"}
    result = execute("query_table", {"tables": {"data": sales["id"]}, "sql": "SELECT * FROM data"})
    with TestClient(create_app(settings)) as client:
        assert client.get("/datasets").status_code == 401
        alpha = {"Authorization": "Bearer alpha-token"}
        beta = {"Authorization": "Bearer beta-token"}
        assert client.get(f"/datasets/{sales['id']}", headers=alpha).status_code == 200
        for path in [
            f"/datasets/{sales['id']}",
            f"/results/{result['result_id']}",
            result["artifacts"][0]["download_path"],
        ]:
            assert client.get(path, headers=beta).status_code == 404
        response = client.post(
            "/chat", headers=alpha, json={"prompt": "profile", "dataset_ids": [sales["id"]]}
        )
        assert response.status_code == 202
        assert client.get(f"/jobs/{response.json()['id']}", headers=beta).status_code == 404
        client.post(f"/jobs/{response.json()['id']}/cancel", headers=alpha)
        assert wait(client, response.json(), alpha)["status"] == "cancelled"


def test_no_key_and_validation(settings, sales):
    with TestClient(create_app(settings)) as client:
        response = client.post(
            "/chat",
            json={
                "prompt": "sum",
                "dataset_ids": [sales["id"]],
                "provider": "openai",
                "model": "configured-later",
            },
        )
        assert response.status_code == 503
        assert response.json()["error"]["code"] == "provider_not_configured"
        assert client.post("/datasets", files={"file": ("bad.exe", b"x")}).status_code == 415
        assert client.post("/tools/query_table", json={"arguments": {}}).status_code == 422
        assert (
            client.get("/datasets", headers={"Origin": "https://untrusted.example"}).status_code
            == 403
        )
        assert client.get("/datasets", headers={"Host": "untrusted.example"}).status_code == 400
