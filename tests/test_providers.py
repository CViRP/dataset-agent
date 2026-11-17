import threading
from types import SimpleNamespace

import pytest

from agent_dataset.agent import Agent
from agent_dataset.config import ServiceError
from agent_dataset.models import Answer, ChatInput, Citation, ToolContext
from agent_dataset.providers import Call, ClaudeProvider, OpenAIProvider, Step
from agent_dataset.tools import Analysis, build_registry


class Payload(SimpleNamespace):
    def model_dump(self, **kwargs):
        return vars(self)


def test_openai_endpoint_from_dotenv(tmp_path, monkeypatch):
    import openai

    from agent_dataset.config import Settings

    monkeypatch.delenv("OPENAI_BASE_URL", raising=False)
    monkeypatch.delenv("DATA_AGENT_OPENAI_BASE_URL", raising=False)
    env_file = tmp_path / ".env"
    env_file.write_text("OPENAI_BASE_URL=https://openrouter.ai/api/v1\n", encoding="utf-8")
    configured = Settings(_env_file=env_file, openai_api_key="test-key")
    received = {}

    def client(**kwargs):
        received.update(kwargs)
        return SimpleNamespace(close=lambda: None)

    monkeypatch.setattr(openai, "OpenAI", client)
    provider = OpenAIProvider(configured, "test-model", [], [])
    assert received["base_url"] == "https://openrouter.ai/api/v1"
    provider.close()


def test_openai_wire_format(monkeypatch, settings):
    import openai

    received = []
    output = Payload(
        type="function_call",
        call_id="call_1",
        name="inspect_dataset",
        arguments='{"dataset_id":"dataset_1"}',
    )
    response = Payload(
        output=[output],
        output_text="",
        status="completed",
        usage=Payload(input_tokens=10, output_tokens=5),
    )
    client = SimpleNamespace(
        responses=SimpleNamespace(create=lambda **kw: received.append(kw) or response),
        close=lambda: None,
    )
    monkeypatch.setattr(openai, "OpenAI", lambda **kwargs: client)
    provider = OpenAIProvider(
        settings,
        "configured-model",
        build_registry().definitions(),
        [{"role": "user", "content": "inspect"}],
    )
    step = provider.step(timeout=10)
    assert step.calls[0].arguments == {"dataset_id": "dataset_1"}
    provider.tool_results([(step.calls[0], {"status": "ok", "result_id": "result_1"})])
    assert provider.history[-1]["type"] == "function_call_output"
    assert provider.history[-1]["call_id"] == "call_1"
    assert received[0]["store"] is False
    assert received[0]["tool_choice"] == "required"
    assert received[0]["tool_choice"] == "required"
    assert all(tool["type"] == "function" for tool in received[0]["tools"])


def test_claude_wire_format(monkeypatch, settings):
    import anthropic

    received = []
    block = Payload(
        type="tool_use", id="toolu_1", name="inspect_dataset", input={"dataset_id": "dataset_1"}
    )
    response = Payload(
        content=[block], stop_reason="tool_use", usage=Payload(input_tokens=10, output_tokens=5)
    )
    client = SimpleNamespace(
        messages=SimpleNamespace(create=lambda **kw: received.append(kw) or response),
        close=lambda: None,
    )
    monkeypatch.setattr(anthropic, "Anthropic", lambda **kwargs: client)
    provider = ClaudeProvider(
        settings,
        "configured-model",
        build_registry().definitions(),
        [{"role": "user", "content": "inspect"}],
    )
    step = provider.step(timeout=10)
    provider.tool_results([(step.calls[0], {"status": "error", "error": {"code": "test"}})])
    assert provider.history[-2]["role"] == "assistant"
    assert provider.history[-1]["role"] == "user"
    assert provider.history[-1]["content"][0]["tool_use_id"] == "toolu_1"
    assert provider.history[-1]["content"][0]["is_error"] is True
    assert "input_schema" in received[0]["tools"][0]
    assert received[0]["tool_choice"] == {"type": "any"}
    assert received[0]["tool_choice"] == {"type": "any"}


class DirectExecutor:
    """Use real analysis operations while replacing process startup in agent logic tests."""

    def __init__(self, store, settings):
        self.store, self.settings = store, settings

    def run(self, tenant, action, payload, *args):
        return Analysis(
            self.store, self.settings, ToolContext(tenant=tenant, **payload["context"])
        ).execute(build_registry(), payload["name"], payload["arguments"])


def test_agent_recovers_invalid_citation_and_computes_answer(store, settings, sales):
    settings.openai_api_key = "not-a-real-key"

    class ScriptedProvider:
        def __init__(self, *args):
            self.history, self.outputs, self.count = [], [], 0

        def step(self, timeout):
            self.count += 1
            if self.count == 1:
                call = Call(
                    "1",
                    "query_table",
                    {
                        "tables": {"sales": sales["id"]},
                        "sql": "SELECT SUM(revenue) AS total FROM sales",
                    },
                )
            elif self.count == 2:
                call = Call(
                    "2",
                    "submit_answer",
                    {"answer": "Revenue is 250.", "citations": [{"result_id": "made_up"}]},
                )
            else:
                assert self.outputs[-1][0][1]["error"]["code"] == "invalid_citation"
                evidence = self.outputs[0][0][1]
                assert evidence["data"]["rows"] == [{"total": 250.0}]
                call = Call(
                    "3",
                    "submit_answer",
                    {
                        "answer": "Revenue is 250.",
                        "citations": [{"result_id": evidence["result_id"]}],
                    },
                )
            return Step([call], "", {"input_tokens": 5, "output_tokens": 5}, "completed")

        def tool_results(self, outputs):
            self.outputs.append(outputs)

        def close(self):
            pass

    conversation = store.put("conversation", "local", {"dataset_ids": [sales["id"]], "turns": []})
    agent = Agent(store, settings, DirectExecutor(store, settings), ScriptedProvider)
    output = agent.run(
        "local",
        ChatInput(
            prompt="Total revenue?", dataset_ids=[sales["id"]], provider="openai", model="test"
        ),
        "test-run",
        conversation["id"],
        threading.Event(),
        lambda *_: None,
    )
    assert output["answer"] == "Revenue is 250."
    assert len(output["usage"]) == 3
    assert store.get("conversation", "local", conversation["id"])["turns"]


def test_answer_rejects_missing_or_forged_evidence(store, settings):
    agent = Agent(store, settings, DirectExecutor(store, settings))
    with pytest.raises(ServiceError, match="needs result citations"):
        agent._validate_answer("local", Answer(answer="Invented answer"), {})
    with pytest.raises(ServiceError, match="successful results"):
        agent._validate_answer(
            "local", Answer(answer="Invented answer", citations=[Citation(result_id="fake")]), {}
        )
    agent._validate_answer(
        "local", Answer(kind="clarification", answer="Which currency is revenue in?"), {}
    )


def test_agent_step_budget(store, settings, sales):
    class LoopProvider:
        def __init__(self):
            self.history = []

        def step(self, timeout):
            return Step([Call("x", "nonexistent", {})], "", {}, "completed")

        def tool_results(self, outputs):
            assert outputs[0][1]["error"]["code"] == "unknown_tool"

        def close(self):
            pass

    settings.max_agent_steps = 2
    conversation = store.put("conversation", "local", {"dataset_ids": [sales["id"]], "turns": []})
    agent = Agent(store, settings, DirectExecutor(store, settings), lambda *_: LoopProvider())
    with pytest.raises(ServiceError) as exc:
        agent.run(
            "local",
            ChatInput(prompt="Analyze", dataset_ids=[sales["id"]], provider="openai", model="test"),
            "test-run",
            conversation["id"],
            threading.Event(),
            lambda *_: None,
        )
    assert exc.value.code == "step_limit"


@pytest.mark.parametrize("recover", [True, False])
def test_agent_recovers_unstructured_response(store, settings, sales, recover):
    class TextProvider:
        def __init__(self):
            self.history, self.count, self.closed = [], 0, False

        def step(self, timeout):
            self.count += 1
            if self.count == 1 or not recover:
                return Step([], "Unverified claim: revenue is 999.", {}, "completed")
            assert "no function call" in self.history[-1]["content"]
            return Step(
                [
                    Call(
                        "final",
                        "submit_answer",
                        {"kind": "clarification", "answer": "Which revenue measure should I use?"},
                    )
                ],
                "",
                {},
                "completed",
            )

        def close(self):
            self.closed = True

    provider = TextProvider()
    conversation = store.put("conversation", "local", {"dataset_ids": [sales["id"]], "turns": []})
    agent = Agent(store, settings, DirectExecutor(store, settings), lambda *_: provider)
    events = []

    def run():
        return agent.run(
            "local",
            ChatInput(prompt="Analyze", dataset_ids=[sales["id"]], provider="openai", model="test"),
            "test-run",
            conversation["id"],
            threading.Event(),
            lambda name, data: events.append(name),
        )

    if recover:
        output = run()
        assert output["kind"] == "clarification"
        assert "999" not in output["answer"]
        assert provider.count == 2
    else:
        with pytest.raises(ServiceError) as exc:
            run()
        assert exc.value.code == "invalid_model_response"
        assert provider.count == 3
        assert store.get("conversation", "local", conversation["id"])["turns"] == []
    assert provider.closed
    assert events.count("model_retry") == (1 if recover else 2)
