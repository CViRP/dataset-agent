import asyncio
import base64
import os
import socket
import sys
import threading
import time

import uvicorn
from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client

from agent_dataset.api import create_app


def test_mcp_stdio_handshake_tools_and_png(settings, sales):
    listener = socket.socket()
    listener.bind(("127.0.0.1", 0))
    port = listener.getsockname()[1]
    server = uvicorn.Server(uvicorn.Config(create_app(settings), log_level="error"))
    thread = threading.Thread(target=server.run, kwargs={"sockets": [listener]}, daemon=True)
    thread.start()
    try:
        deadline = time.monotonic() + 10
        while not server.started and time.monotonic() < deadline:
            time.sleep(0.05)
        assert server.started

        async def exercise():
            parameters = StdioServerParameters(
                command=sys.executable,
                args=["-m", "agent_dataset.mcp_server"],
                env={
                    **os.environ,
                    "DATA_AGENT_API_URL": f"http://127.0.0.1:{port}",
                    "DATA_AGENT_MCP_API_KEY": "",
                },
            )
            async with (
                stdio_client(parameters) as (reader, writer),
                ClientSession(reader, writer) as session,
            ):
                await session.initialize()
                tools = await session.list_tools()
                assert "query_table" in {tool.name for tool in tools.tools}
                listed = await session.call_tool("list_datasets", {})
                assert not listed.isError
                assert listed.structuredContent["datasets"][0]["id"] == sales["id"]
                queried = await session.call_tool(
                    "query_table",
                    {
                        "tables": {"sales": sales["id"]},
                        "sql": "SELECT region, SUM(revenue) AS revenue FROM sales GROUP BY region",
                    },
                )
                assert not queried.isError, queried
                chart = await session.call_tool(
                    "create_chart",
                    {
                        "result_id": queried.structuredContent["result_id"],
                        "chart_type": "bar",
                        "x": "region",
                        "y": "revenue",
                    },
                )
                assert not chart.isError, chart
                image = await session.call_tool(
                    "get_chart_image",
                    {"artifact_id": chart.structuredContent["data"]["artifact_id"]},
                )
                assert not image.isError, image
                assert image.content[0].type == "image"
                assert base64.b64decode(image.content[0].data).startswith(b"\x89PNG")

        asyncio.run(exercise())
    finally:
        server.should_exit = True
        thread.join(timeout=15)
        listener.close()
        assert not thread.is_alive()
