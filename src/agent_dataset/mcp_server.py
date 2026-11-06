"""Hermes-compatible stdio MCP bridge. All operations use the authenticated REST API."""

import asyncio
import base64
import os

import httpx
from dotenv import load_dotenv
from mcp import types
from mcp.server import Server
from mcp.server.stdio import stdio_server

from .store import dumps


def create_server(client: httpx.AsyncClient) -> Server:
    server = Server("agent-dataset")

    async def request(method, path, **kwargs):
        response = await client.request(method, path, **kwargs)
        response.raise_for_status()
        return response.json()

    @server.list_tools()
    async def list_tools():
        catalog = await request("GET", "/tools")
        tools = [
            types.Tool(
                name=tool["name"], description=tool["description"], inputSchema=tool["input_schema"]
            )
            for tool in catalog["tools"]
        ]
        tools += [
            types.Tool(
                name="list_datasets",
                description="List uploaded dataset versions in your project.",
                inputSchema={"type": "object", "properties": {}, "additionalProperties": False},
            ),
            types.Tool(
                name="get_result",
                description="Read saved evidence with paginated rows.",
                inputSchema={
                    "type": "object",
                    "properties": {
                        "result_id": {"type": "string"},
                        "offset": {"type": "integer", "minimum": 0},
                        "limit": {"type": "integer", "minimum": 1, "maximum": 1000},
                    },
                    "required": ["result_id"],
                    "additionalProperties": False,
                },
            ),
            types.Tool(
                name="get_chart_image",
                description="Read a saved PNG as an MCP image for visual inspection.",
                inputSchema={
                    "type": "object",
                    "properties": {"artifact_id": {"type": "string"}},
                    "required": ["artifact_id"],
                    "additionalProperties": False,
                },
            ),
        ]
        return tools

    @server.call_tool()
    async def call_tool(name: str, arguments: dict):
        try:
            if name == "list_datasets":
                value = await request("GET", "/datasets")
            elif name == "get_result":
                value = await request(
                    "GET",
                    f"/results/{arguments['result_id']}",
                    params={k: v for k, v in arguments.items() if k != "result_id"},
                )
            elif name == "get_chart_image":
                response = await client.get(f"/artifacts/{arguments['artifact_id']}")
                response.raise_for_status()
                if response.headers.get("content-type", "").split(";")[0] != "image/png":
                    return types.CallToolResult(
                        isError=True,
                        content=[
                            types.TextContent(type="text", text="Artifact is not a PNG chart")
                        ],
                    )
                return types.CallToolResult(
                    content=[
                        types.ImageContent(
                            type="image",
                            mimeType="image/png",
                            data=base64.b64encode(response.content).decode("ascii"),
                        )
                    ]
                )
            else:
                value = await request("POST", f"/tools/{name}", json={"arguments": arguments})
            return types.CallToolResult(
                content=[types.TextContent(type="text", text=dumps(value))], structuredContent=value
            )
        except httpx.HTTPStatusError as exc:
            return types.CallToolResult(
                isError=True,
                content=[
                    types.TextContent(
                        type="text",
                        text=f"API error {exc.response.status_code}: {exc.response.text[:2000]}",
                    )
                ],
            )
        except httpx.RequestError:
            return types.CallToolResult(
                isError=True,
                content=[
                    types.TextContent(
                        type="text", text="Dataset API is unavailable; start agent-dataset first."
                    )
                ],
            )

    return server


async def serve():
    load_dotenv()
    url = os.getenv("DATA_AGENT_API_URL", "http://127.0.0.1:8000")
    key = os.getenv("DATA_AGENT_MCP_API_KEY", "")
    headers = {"Authorization": f"Bearer {key}"} if key else {}
    async with httpx.AsyncClient(
        base_url=url, headers=headers, timeout=330, trust_env=False
    ) as client:
        server = create_server(client)
        async with stdio_server() as (reader, writer):
            await server.run(reader, writer, server.create_initialization_options())


def main():
    asyncio.run(serve())


if __name__ == "__main__":
    main()
