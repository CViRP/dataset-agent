import threading
import time
from collections.abc import Callable

from pydantic import ValidationError

from .config import ServiceError, Settings
from .execution import Executor
from .models import Answer, BuildReportInput, ChatInput, Citation, Finding, ReportInput
from .providers import make_provider, validate_provider
from .store import Store, dumps
from .tools import build_registry


class Agent:
    def __init__(
        self,
        store: Store,
        settings: Settings,
        executor: Executor,
        provider_factory: Callable = make_provider,
    ):
        self.store, self.settings, self.executor = store, settings, executor
        self.provider_factory = provider_factory
        self.registry = build_registry(settings.enabled_plugins)

    def validate(self, tenant: str, request: ChatInput):
        for dataset_id in request.dataset_ids:
            self.store.get("dataset", tenant, dataset_id)
        provider = request.provider or self.settings.provider
        model = request.model or self.settings.model
        validate_provider(self.settings, provider, model)
        if request.conversation_id:
            conversation = self.store.get("conversation", tenant, request.conversation_id)
            if set(request.dataset_ids) != set(conversation["dataset_ids"]):
                raise ServiceError(
                    "conversation_scope",
                    "Continue with the conversation's dataset_ids or start a new conversation.",
                    409,
                )

    def run(
        self,
        tenant: str,
        request: ChatInput,
        run_id: str,
        conversation_id: str,
        cancel: threading.Event,
        event: Callable,
    ) -> dict:
        started = time.monotonic()
        allowed = list(request.dataset_ids)
        results: dict[str, dict] = {}
        usage = []
        provider_name = request.provider or self.settings.provider
        model = request.model or self.settings.model

        def remaining():
            if cancel.is_set():
                raise ServiceError("cancelled", "Analysis cancelled", 409)
            left = self.settings.agent_timeout_seconds - (time.monotonic() - started)
            if left <= 0:
                raise ServiceError("agent_timeout", "Analysis time budget exhausted", 408)
            return left

        def call_tool(name, arguments):
            event("tool_started", {"tool": name})
            value = self.executor.run(
                tenant,
                "tool",
                {
                    "name": name,
                    "arguments": arguments,
                    "context": {"run_id": run_id, "allowed_dataset_ids": allowed},
                },
                cancel,
                min(self.settings.tool_timeout_seconds, remaining()),
            )
            results[value["result_id"]] = value
            if name in {"transform_dataset", "edit_dataset"}:
                allowed.append(value["data"]["dataset"]["id"])
            event(
                "tool_completed",
                {
                    "tool": name,
                    "result_id": value["result_id"],
                    "artifact_ids": [artifact["id"] for artifact in value["artifacts"]],
                },
            )
            return value

        if provider_name == "offline":
            answer = self._offline(tenant, request, call_tool)
        else:
            conversation = self.store.get("conversation", tenant, conversation_id)
            messages = []
            for turn in conversation.get("turns", [])[-5:]:
                messages += [
                    {"role": "user", "content": turn["prompt"][:4000]},
                    {"role": "assistant", "content": turn["answer"]["answer"][:4000]},
                ]
            messages.append(
                {
                    "role": "user",
                    "content": dumps(
                        {
                            "question": request.prompt,
                            "dataset_ids": allowed,
                            "report_requested": isinstance(request, ReportInput),
                        }
                    ),
                }
            )
            provider = self.provider_factory(
                self.settings, provider_name, model, self.registry.definitions(), messages
            )
            answer = None
            unstructured_responses = 0
            try:
                for _ in range(self.settings.max_agent_steps):
                    remaining()
                    if len(dumps(provider.history)) > self.settings.max_context_chars:
                        raise ServiceError(
                            "context_limit",
                            "Analysis context budget reached; narrow the question.",
                            422,
                        )
                    event("model_started", {"provider": provider_name, "model": model})
                    step = provider.step(timeout=min(60, remaining()))
                    usage.append(step.usage)
                    remaining()
                    if step.stop_reason in {"max_tokens", "incomplete", "failed"}:
                        raise ServiceError(
                            "model_incomplete",
                            "Model response was incomplete; narrow the question or retry.",
                            502,
                        )
                    if not step.calls:
                        unstructured_responses += 1
                        if unstructured_responses <= 2:
                            provider.history.append(
                                {
                                    "role": "user",
                                    "content": (
                                        "Your previous response contained no function call. "
                                        "Call a registered tool to gather evidence, or call "
                                        "submit_answer alone with the structured answer. "
                                        "Analytical answers must cite successful results from "
                                        "this run. Do not return plain text or invent evidence."
                                    ),
                                }
                            )
                            event("model_retry", {"reason": "missing_tool_call"})
                            continue
                        raise ServiceError(
                            "invalid_model_response",
                            "Model repeatedly returned no function call. Select a model "
                            "that follows required tool calling, or retry the request.",
                            502,
                        )
                    if len(step.calls) > 8:
                        raise ServiceError(
                            "tool_call_limit",
                            "Model requested too many simultaneous operations.",
                            422,
                        )
                    outputs = []
                    for call in step.calls:
                        try:
                            if not isinstance(call.arguments, dict):
                                raise ServiceError(
                                    "invalid_arguments", "Tool arguments must be a JSON object"
                                )
                            if call.name == "submit_answer":
                                if len(step.calls) != 1:
                                    raise ServiceError(
                                        "invalid_final_call",
                                        "Call submit_answer alone after receiving tool results",
                                    )
                                candidate = Answer.model_validate(call.arguments)
                                self._validate_answer(tenant, candidate, results)
                                answer = candidate
                                break
                            value = call_tool(call.name, call.arguments)
                            # Keep metadata and references while bounding model context.
                            if len(dumps(value)) > 16000:
                                value = {
                                    **value,
                                    "data": {
                                        "preview": dumps(value["data"])[:10000],
                                        "truncated_for_context": True,
                                    },
                                }
                            outputs.append((call, value))
                        except (ServiceError, ValidationError) as exc:
                            if isinstance(exc, ServiceError) and exc.code in {
                                "cancelled",
                                "agent_timeout",
                            }:
                                raise
                            code = exc.code if isinstance(exc, ServiceError) else "validation_error"
                            message = (
                                exc.message if isinstance(exc, ServiceError) else str(exc)[:1000]
                            )
                            event("tool_error", {"tool": call.name, "code": code})
                            outputs.append(
                                (
                                    call,
                                    {
                                        "status": "error",
                                        "error": {"code": code, "message": message},
                                    },
                                )
                            )
                    if answer is not None:
                        break
                    provider.tool_results(outputs)
                if answer is None:
                    raise ServiceError(
                        "step_limit",
                        "Agent reached its step budget; intermediate results are saved in this run.",
                        422,
                    )
            except ServiceError:
                raise
            except Exception as exc:
                raise ServiceError(
                    "provider_error",
                    f"Model request failed ({type(exc).__name__}); check credentials, model, and connectivity.",
                    502,
                ) from exc
            finally:
                provider.close()
        self._validate_answer(tenant, answer, results)
        if isinstance(request, ReportInput):
            evidence = [
                result_id
                for result_id, result in results.items()
                if result["provenance"]["tool"] not in {"build_report", "create_chart"}
            ]
            if not evidence:
                raise ServiceError(
                    "no_report_evidence", "No computed evidence was produced for the report", 422
                )
            chart_ids = [
                artifact["id"]
                for result in results.values()
                for artifact in result["artifacts"]
                if artifact["mime_type"] == "image/png"
            ]
            report = call_tool(
                "build_report",
                BuildReportInput(
                    title=request.title,
                    question=request.prompt,
                    limitations=answer.limitations,
                    result_ids=evidence[-30:],
                    artifact_ids=chart_ids[:20],
                    findings=[
                        Finding(
                            text=answer.answer[:4000],
                            result_ids=list(
                                dict.fromkeys(
                                    citation.result_id
                                    for citation in answer.citations
                                    if citation.result_id in evidence[-30:]
                                )
                            ),
                        )
                    ]
                    if any(c.result_id in evidence[-30:] for c in answer.citations)
                    else [],
                    format=request.format,
                ).model_dump(),
            )
            answer.artifact_ids.extend(artifact["id"] for artifact in report["artifacts"])
        remaining()
        artifacts = [
            self.store.public_artifact(self.store.get("artifact", tenant, artifact_id))
            for artifact_id in dict.fromkeys(answer.artifact_ids)
        ]
        output = {
            **answer.model_dump(),
            "artifacts": artifacts,
            "provider": provider_name,
            "model": model if provider_name != "offline" else None,
            "run_id": run_id,
            "conversation_id": conversation_id,
            "dataset_ids": allowed,
            "result_ids": list(results),
            "usage": usage,
            "elapsed_seconds": round(time.monotonic() - started, 3),
        }
        conversation = self.store.get("conversation", tenant, conversation_id)
        turns = conversation.get("turns", []) + [
            {"prompt": request.prompt, "answer": answer.model_dump(), "run_id": run_id}
        ]
        self.store.update(
            "conversation", tenant, conversation_id, turns=turns[-50:], dataset_ids=allowed
        )
        return output

    def _validate_answer(self, tenant, answer, results):
        if answer.kind == "answer" and not answer.citations:
            raise ServiceError(
                "missing_evidence",
                "An analytical answer needs result citations. Use kind='clarification' or 'insufficient_evidence' when appropriate.",
            )
        available_artifacts = {
            artifact["id"] for result in results.values() for artifact in result["artifacts"]
        }
        for citation in answer.citations:
            if citation.result_id not in results:
                raise ServiceError(
                    "invalid_citation", "Citations must reference successful results from this run"
                )
            if citation.chunk_id:
                data = self.store.get("result", tenant, citation.result_id)["data"]
                chunks = data.get("hits", []) + data.get("chunks", [])
                chunks += [
                    {"chunk_id": chunk_id}
                    for record in data.get("records", [])
                    for chunk_id in record.get("source", {}).get("chunk_ids", [])
                ]
                if citation.chunk_id not in {chunk["chunk_id"] for chunk in chunks}:
                    raise ServiceError(
                        "invalid_citation", "Chunk citation is not present in the cited evidence"
                    )
        if not set(answer.artifact_ids).issubset(available_artifacts):
            raise ServiceError(
                "invalid_artifact", "Answer references an artifact not produced by this run"
            )

    def _offline(self, tenant, request, call_tool):
        lines = ["Offline evidence summary (no LLM was called)."]
        citations, artifacts = [], []
        documents = []
        for dataset_id in request.dataset_ids:
            inspected = call_tool("inspect_dataset", {"dataset_id": dataset_id})
            dataset = inspected["data"]["dataset"]
            citations.append(Citation(result_id=inspected["result_id"]))
            if dataset["kind"] == "table":
                profiled = call_tool("profile_dataset", {"dataset_id": dataset_id})
                data = profiled["data"]
                citations.append(Citation(result_id=profiled["result_id"]))
                lines.append(
                    f"{dataset['name']}: {data['row_count']} rows, {data['column_count']} columns, "
                    f"{data['duplicate_rows']} duplicate rows."
                )
                for column, description in list(data["columns"].items())[:20]:
                    lines.append(
                        f"- {column}: {description['missing']} missing; {description['unique']} unique values."
                    )
                if isinstance(request, ReportInput):
                    numeric = next(
                        (
                            column
                            for column, description in data["columns"].items()
                            if "mean" in description and description["non_null"]
                        ),
                        None,
                    )
                    if numeric:
                        quoted = '"' + numeric.replace('"', '""') + '"'
                        rows = call_tool(
                            "query_table",
                            {
                                "tables": {"data": dataset_id},
                                "sql": f"SELECT {quoted} FROM data WHERE {quoted} IS NOT NULL",
                                "limit": 5000,
                            },
                        )
                        chart = call_tool(
                            "create_chart",
                            {
                                "result_id": rows["result_id"],
                                "chart_type": "histogram",
                                "x": numeric,
                                "title": f"Distribution of {numeric}",
                            },
                        )
                        artifacts.extend(artifact["id"] for artifact in chart["artifacts"])
            else:
                documents.append(dataset_id)
                lines.append(
                    f"{dataset['name']}: {dataset['chunk_count']} text chunks, {dataset['characters']} characters."
                )
        if documents:
            searched = call_tool(
                "search_documents", {"dataset_ids": documents, "query": request.prompt}
            )
            for hit in searched["data"]["hits"]:
                citations.append(
                    Citation(result_id=searched["result_id"], chunk_id=hit["chunk_id"])
                )
                lines.append(f"Relevant source ({hit['location']}): {hit['text'][:500]}")
        return Answer(
            answer="\n".join(lines),
            citations=citations,
            artifact_ids=artifacts,
            limitations=[
                "Offline mode provides profiling and keyword retrieval, not an answer to arbitrary natural-language questions. Configure GPT or Claude for reasoning."
            ],
        )
