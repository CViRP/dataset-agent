"""Run with .venv/Scripts/python.exe examples/api_demo.py against a running server."""

import os
import time
from pathlib import Path

import httpx


def main():
    token = os.getenv("DATA_AGENT_MCP_API_KEY", "")
    headers = {"Authorization": f"Bearer {token}"} if token else {}
    with httpx.Client(
        base_url=os.getenv("DATA_AGENT_API_URL", "http://127.0.0.1:8000"),
        headers=headers,
        timeout=120,
        trust_env=False,
    ) as client:

        def wait(job):
            deadline = time.monotonic() + 300
            while time.monotonic() < deadline:
                response = client.get(f"/jobs/{job['id']}")
                response.raise_for_status()
                job = response.json()
                if job["status"] == "succeeded":
                    return job["result"]
                if job["status"] in {"failed", "cancelled"}:
                    raise RuntimeError(job)
                time.sleep(0.25)
            raise TimeoutError("Job did not finish")

        with Path(__file__).with_name("sales.csv").open("rb") as file:
            response = client.post("/datasets", files={"file": ("sales.csv", file, "text/csv")})
        response.raise_for_status()
        dataset = wait(response.json())
        response = client.post(
            "/tools/query_table",
            json={
                "arguments": {
                    "tables": {"sales": dataset["id"]},
                    "sql": "SELECT region, SUM(revenue) AS revenue FROM sales GROUP BY region ORDER BY region",
                }
            },
        )
        response.raise_for_status()
        query = response.json()
        print("Regional revenue:", query["data"]["rows"])
        response = client.post(
            "/tools/create_chart",
            json={
                "arguments": {
                    "result_id": query["result_id"],
                    "chart_type": "bar",
                    "x": "region",
                    "y": "revenue",
                    "title": "Revenue by region",
                }
            },
        )
        response.raise_for_status()
        print("Chart:", response.json()["artifacts"][0]["download_path"])
        response = client.post(
            "/reports",
            json={
                "dataset_ids": [dataset["id"]],
                "prompt": "Create an exploratory sales report",
                "provider": "offline",
                "format": "pdf",
            },
        )
        response.raise_for_status()
        report = wait(response.json())
        print(report["answer"])
        for artifact in report["artifacts"]:
            print(artifact["mime_type"], artifact["download_path"])


if __name__ == "__main__":
    main()
