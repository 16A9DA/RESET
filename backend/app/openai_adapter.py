"""Translate the neutral request into OpenAI Chat Completions and back. Mirrors OpenAICompatibleProvider in ResetCore.
OpenAI deprecated max_tokens; newer models need max_completion_tokens, which also counts hidden reasoning tokens."""
import json
from typing import Any

from .schemas import AIRequest, AIResponse, ToolCall

MIN_COMPLETION_TOKENS = 4000


def to_openai(req: AIRequest, model: str) -> dict[str, Any]:
    messages: list[dict[str, Any]] = [{"role": "system", "content": req.system}]
    for m in req.messages:
        content: list[dict[str, Any]] = []
        calls: list[dict[str, Any]] = []
        for p in m.parts:
            if p.type == "text":
                content.append({"type": "text", "text": p.text})
            elif p.type == "image":
                content.append({"type": "image_url", "image_url": {"url": f"data:{p.mime};base64,{p.base64}"}})
            elif p.type == "tool_use":
                calls.append({"id": p.id, "type": "function", "function": {"name": p.name, "arguments": json.dumps(p.input)}})
            else:
                messages.append({"role": "tool", "tool_call_id": p.id, "content": p.text})
        if content or calls:
            msg: dict[str, Any] = {"role": m.role, "content": content or None}
            if calls:
                msg["tool_calls"] = calls
            messages.append(msg)
    body: dict[str, Any] = {"model": model, "messages": messages, "max_completion_tokens": max(req.maxTokens, MIN_COMPLETION_TOKENS)}
    if req.tools:
        body["tools"] = [{"type": "function", "function": {"name": t.name, "description": t.description, "parameters": t.schema_}} for t in req.tools]
    return body


def from_openai(data: dict[str, Any]) -> AIResponse:
    msg = data["choices"][0]["message"]
    calls = []
    for c in msg.get("tool_calls") or []:
        try:
            args = json.loads(c["function"].get("arguments") or "{}")
        except json.JSONDecodeError:
            args = {}
        calls.append(ToolCall(id=c["id"], name=c["function"]["name"], input=args if isinstance(args, dict) else {}))
    return AIResponse(text=msg.get("content") or "", toolCalls=calls)
