import json

import httpx
import pytest
from fastapi.testclient import TestClient

from app.main import Settings, create_app

TOKEN = "test-token-123"


def make(handler, rate=30, key="sk-server-key", tokens=TOKEN):
    s = Settings()
    s.api_key, s.tokens, s.rate, s.model = key, [t for t in tokens.split(",") if t], rate, "claude-sonnet-5-5"
    upstream = httpx.AsyncClient(transport=httpx.MockTransport(handler))
    return TestClient(create_app(s, upstream))


def ok_handler(request: httpx.Request) -> httpx.Response:
    return httpx.Response(200, json={"content": [{"type": "text", "text": "hello"}], "stop_reason": "end_turn"})


BODY = {"system": "s", "messages": [{"role": "user", "parts": [{"type": "text", "text": "hi"}]}], "tools": [], "maxTokens": 100}
AUTH = {"Authorization": f"Bearer {TOKEN}"}


def test_requires_token():
    c = make(ok_handler)
    assert c.post("/v1/ai/complete", json=BODY).status_code == 401
    assert c.post("/v1/ai/complete", json=BODY, headers={"Authorization": "Bearer wrong"}).status_code == 401


def test_refuses_to_run_without_configured_tokens():
    assert make(ok_handler, tokens="").post("/v1/ai/complete", json=BODY, headers=AUTH).status_code == 503


def test_happy_path_and_provider_request_shape():
    seen = {}

    def handler(request: httpx.Request) -> httpx.Response:
        seen["headers"] = request.headers
        seen["body"] = json.loads(request.content)
        return httpx.Response(200, json={"content": [
            {"type": "text", "text": "ok"}, {"type": "tool_use", "id": "t1", "name": "log_water", "input": {"ml": 250}}]})

    body = {**BODY, "tools": [{"name": "log_water", "description": "d", "schema": {"type": "object"}}],
            "messages": [{"role": "user", "parts": [{"type": "image", "mime": "image/jpeg", "base64": "AAA"}, {"type": "text", "text": "x"}]}]}
    r = make(handler).post("/v1/ai/complete", json=body, headers=AUTH)
    assert r.status_code == 200
    assert r.json() == {"text": "ok", "toolCalls": [{"id": "t1", "name": "log_water", "input": {"ml": 250}}]}
    assert seen["headers"]["x-api-key"] == "sk-server-key"
    assert seen["headers"]["anthropic-version"] == "2023-06-01"
    assert seen["body"]["max_tokens"] == 100 and seen["body"]["model"] == "claude-sonnet-5-5"
    assert seen["body"]["tools"][0]["input_schema"] == {"type": "object"}
    assert seen["body"]["messages"][0]["content"][0]["source"] == {"type": "base64", "media_type": "image/jpeg", "data": "AAA"}


def test_tool_result_round_trip_translation():
    seen = {}

    def handler(request: httpx.Request) -> httpx.Response:
        seen["body"] = json.loads(request.content)
        return httpx.Response(200, json={"content": [{"type": "text", "text": "done"}]})

    body = {**BODY, "messages": [{"role": "user", "parts": [{"type": "tool_result", "id": "t1", "text": "ok", "is_error": True}]}]}
    assert make(handler).post("/v1/ai/complete", json=body, headers=AUTH).status_code == 200
    assert seen["body"]["messages"][0]["content"][0] == {"type": "tool_result", "tool_use_id": "t1", "content": "ok", "is_error": True}


@pytest.mark.parametrize("patch", [
    {"maxTokens": 99999},
    {"messages": [{"role": "system", "parts": [{"type": "text", "text": "x"}]}]},
    {"messages": [{"role": "user", "parts": [{"type": "image", "mime": "image/svg+xml", "base64": "A"}]}]},
    {"messages": [{"role": "user", "parts": [{"type": "text", "text": "x"}]}] * 41},
    {"unexpected": True},
    {"tools": [{"name": "bad name!", "description": "d", "schema": {}}]},
])
def test_rejects_invalid_input(patch):
    r = make(ok_handler).post("/v1/ai/complete", json={**BODY, **patch}, headers=AUTH)
    assert r.status_code == 422


def test_oversized_image_rejected():
    big = {"type": "image", "mime": "image/jpeg", "base64": "A" * 6_000_001}
    r = make(ok_handler).post("/v1/ai/complete", json={**BODY, "messages": [{"role": "user", "parts": [big]}]}, headers=AUTH)
    assert r.status_code == 422


def test_rate_limit_per_token():
    c = make(ok_handler, rate=2)
    codes = [c.post("/v1/ai/complete", json=BODY, headers=AUTH).status_code for _ in range(3)]
    assert codes == [200, 200, 429]


def test_upstream_errors_are_mapped_without_leaking_details():
    def unauthorized(_): return httpx.Response(401, json={"error": {"message": "invalid x-api-key sk-server-key"}})
    r = make(unauthorized).post("/v1/ai/complete", json=BODY, headers=AUTH)
    assert r.status_code == 502 and "sk-server-key" not in r.text

    def limited(_): return httpx.Response(429)
    assert make(limited).post("/v1/ai/complete", json=BODY, headers=AUTH).status_code == 429

    def boom(_): return httpx.Response(500)
    assert make(boom).post("/v1/ai/complete", json=BODY, headers=AUTH).status_code == 502

    def timeout(_): raise httpx.ReadTimeout("slow")
    assert make(timeout).post("/v1/ai/complete", json=BODY, headers=AUTH).status_code == 504

    def garbage(_): return httpx.Response(200, text="not json")
    assert make(garbage).post("/v1/ai/complete", json=BODY, headers=AUTH).status_code == 502


def test_missing_provider_key():
    assert make(ok_handler, key="").post("/v1/ai/complete", json=BODY, headers=AUTH).status_code == 503


def test_healthz_does_not_expose_secrets():
    r = make(ok_handler).get("/healthz")
    assert r.status_code == 200 and "sk-server-key" not in r.text and r.json()["provider_configured"] is True
