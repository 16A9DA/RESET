import json
import logging
from pathlib import Path

import httpx
from fastapi.testclient import TestClient

from app import env
from app.main import Settings, create_app
from app.openai_adapter import from_openai, to_openai
from app.schemas import AIRequest

TOKEN = "t-123"
AUTH = {"Authorization": f"Bearer {TOKEN}"}
BODY = {"system": "s", "messages": [{"role": "user", "parts": [{"type": "text", "text": "hi"}]}], "tools": [], "maxTokens": 100}


def test_parse_env_handles_quotes_comments_export():
    d = env.parse('# c\nA=1\nexport B="two words"\nC=\'x\'\nD=val # trailing\n\nbad line\nE=\n')
    assert d == {"A": "1", "B": "two words", "C": "x", "D": "val", "E": ""}


def test_load_does_not_override_existing_and_skips_empty(tmp_path, monkeypatch):
    f = tmp_path / ".env"
    f.write_text("RESET_T_A=fromfile\nRESET_T_B=fromfile\nRESET_T_C=\n")
    monkeypatch.setenv("RESET_T_A", "already")
    monkeypatch.delenv("RESET_T_B", raising=False)
    monkeypatch.delenv("RESET_T_C", raising=False)
    names = env.load([f, tmp_path / "missing.env"])
    import os
    assert os.environ["RESET_T_A"] == "already" and os.environ["RESET_T_B"] == "fromfile"
    assert "RESET_T_C" not in os.environ and names == ["RESET_T_B"]
    monkeypatch.delenv("RESET_T_B", raising=False)


def _clear(monkeypatch):
    for k in ["ANTHROPIC_API_KEY", "ANTROPIC_API_KEY", "OPENAI_API_KEY", "AI_PROVIDER", "ANTHROPIC_MODEL", "OPENAI_MODEL", "PROXY_TOKENS"]:
        monkeypatch.delenv(k, raising=False)


def test_misspelled_anthropic_key_is_accepted_with_a_warning_that_hides_the_value(monkeypatch, caplog):
    _clear(monkeypatch)
    monkeypatch.setenv("ANTROPIC_API_KEY", "sk-secret-typo")
    monkeypatch.setenv("ANTHROPIC_MODEL", "claude-sonnet-5")
    with caplog.at_level(logging.WARNING, logger="reset.proxy"):
        s = Settings()
    assert s.provider == "anthropic" and s.api_key == "sk-secret-typo" and s.model == "claude-sonnet-5"
    assert "ANTHROPIC_API_KEY" in caplog.text and "sk-secret-typo" not in caplog.text


def test_provider_selection(monkeypatch):
    _clear(monkeypatch)
    monkeypatch.setenv("OPENAI_API_KEY", "sk-o")
    monkeypatch.setenv("OPENAI_MODEL", "m-vision")
    s = Settings()
    assert (s.provider, s.api_key, s.model) == ("openai", "sk-o", "m-vision")
    monkeypatch.setenv("ANTHROPIC_API_KEY", "sk-a")
    assert Settings().provider == "anthropic"
    monkeypatch.setenv("AI_PROVIDER", "openai")
    assert Settings().provider == "openai"
    monkeypatch.setenv("AI_PROVIDER", "bogus")
    assert Settings().provider == "anthropic"


def test_openai_model_has_no_default(monkeypatch):
    _clear(monkeypatch)
    monkeypatch.setenv("OPENAI_API_KEY", "sk-o")
    assert Settings().model == ""


def test_to_openai_shape():
    req = AIRequest.model_validate({
        "system": "sys",
        "messages": [
            {"role": "user", "parts": [{"type": "image", "mime": "image/jpeg", "base64": "AAA"}, {"type": "text", "text": "x"}]},
            {"role": "assistant", "parts": [{"type": "tool_use", "id": "c1", "name": "log_water", "input": {"ml": 250}}]},
            {"role": "user", "parts": [{"type": "tool_result", "id": "c1", "text": "ok"}]},
        ],
        "tools": [{"name": "log_water", "description": "d", "schema": {"type": "object"}}],
        "maxTokens": 1500,
    })
    b = to_openai(req, "m")
    assert b["max_completion_tokens"] == 4000 and "max_tokens" not in b
    assert b["messages"][0] == {"role": "system", "content": "sys"}
    assert b["messages"][1]["content"][0] == {"type": "image_url", "image_url": {"url": "data:image/jpeg;base64,AAA"}}
    assert b["messages"][2]["tool_calls"][0]["function"] == {"name": "log_water", "arguments": json.dumps({"ml": 250})}
    assert b["messages"][2]["content"] is None
    assert b["messages"][3] == {"role": "tool", "tool_call_id": "c1", "content": "ok"}
    assert b["tools"][0]["function"]["parameters"] == {"type": "object"}


def test_from_openai_parses_tool_calls_and_bad_arguments():
    r = from_openai({"choices": [{"message": {"content": "hi", "tool_calls": [
        {"id": "a", "function": {"name": "f", "arguments": "{\"k\": 1}"}},
        {"id": "b", "function": {"name": "g", "arguments": "not json"}}]}}]})
    assert r.text == "hi" and r.toolCalls[0].input == {"k": 1} and r.toolCalls[1].input == {}
    assert from_openai({"choices": [{"message": {"content": None}}]}).text == ""


def _client(handler, **kw):
    s = Settings()
    s.provider, s.api_key, s.model, s.tokens, s.rate = "openai", kw.get("key", "sk-o"), kw.get("model", "m-vision"), [TOKEN], 30
    return TestClient(create_app(s, httpx.AsyncClient(transport=httpx.MockTransport(handler))))


def test_openai_end_to_end_and_headers():
    seen = {}

    def handler(request: httpx.Request) -> httpx.Response:
        seen["url"], seen["auth"], seen["body"] = str(request.url), request.headers.get("authorization"), json.loads(request.content)
        return httpx.Response(200, json={"choices": [{"message": {"content": "hello"}}]})

    r = _client(handler).post("/v1/ai/complete", json=BODY, headers=AUTH)
    assert r.status_code == 200 and r.json() == {"text": "hello", "toolCalls": []}
    assert seen["url"] == "https://api.openai.com/v1/chat/completions" and seen["auth"] == "Bearer sk-o"
    assert seen["body"]["model"] == "m-vision"


def test_openai_without_model_is_a_clear_503():
    r = _client(lambda _: httpx.Response(200, json={}), model="").post("/v1/ai/complete", json=BODY, headers=AUTH)
    assert r.status_code == 503 and "OPENAI_MODEL" in r.json()["detail"]


def test_openai_upstream_error_does_not_leak_key():
    r = _client(lambda _: httpx.Response(401, json={"error": {"message": "bad key sk-o"}})).post("/v1/ai/complete", json=BODY, headers=AUTH)
    assert r.status_code == 502 and "sk-o" not in r.text
    r2 = _client(lambda _: httpx.Response(200, json={"unexpected": True})).post("/v1/ai/complete", json=BODY, headers=AUTH)
    assert r2.status_code == 502
