def main() -> None:
    import argparse

    import uvicorn

    parser = argparse.ArgumentParser(description="Dataset analysis API")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8000)
    args = parser.parse_args()
    from .config import Settings

    settings = Settings()
    if args.host not in {"127.0.0.1", "localhost", "::1"} and not settings.api_keys:
        parser.error("Set DATA_AGENT_API_KEYS before binding beyond loopback.")
    uvicorn.run("agent_dataset.api:create_app", factory=True, host=args.host, port=args.port)
