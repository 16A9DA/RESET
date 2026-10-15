"""Translate the neutral request into the Anthropic Messages API and back. Mirrors AnthropicProvider in ResetCore."""
from typing import Any

from .schemas import AIRequest, AIResponse, ToolCall


def to_anthropic(req: AIRequest, model: str) -> dict[str, Any]:
    messages = []
    for m in req.messages:
        content: list[dict[str, Any]] = []
        for p in m.parts:
            if p.type == "text":
                content.append({"type": "text", "text": p.text})
            elif p.type == "image":
                content.append({"type": "image", "source": {"type": "base64", "media_type": p.mime, "data": p.base64}})
            elif p.type == "tool_use":
                content.append({"type": "tool_use", "id": p.id, "name": p.name, "input": p.input})
            else:
                content.append({"type": "tool_result", "tool_use_id": p.id, "content": p.text, "is_error": p.is_error})
        messages.append({"role": m.role, "content": content})
    body: dict[str, Any] = {"model": model, "max_tokens": req.maxTokens, "system": req.system, "messages": messages}
    if req.tools:
        body["tools"] = [{"name": t.name, "description": t.description, "input_schema": t.schema_} for t in req.tools]
    return body


def from_anthropic(data: dict[str, Any]) -> AIResponse:
    text, calls = "", []
    for block in data.get("content", []):
        if block.get("type") == "text":
            text += block.get("text", "")
        elif block.get("type") == "tool_use":
            calls.append(ToolCall(id=block["id"], name=block["name"], input=block.get("input", {})))
    return AIResponse(text=text, toolCalls=calls)
