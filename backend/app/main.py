"""Optional RE:SET proxy. Holds the provider key, checks a shared token, validates input, rate limits, forwards.
Request bodies are never logged. Run behind HTTPS (a reverse proxy or a platform that terminates TLS)."""
import os
import secrets
import time
from collections import defaultdict, deque

import httpx
from fastapi import Depends, FastAPI, Header, HTTPException, Request

from .anthropic_adapter import from_anthropic, to_anthropic
from .schemas import AIRequest, AIResponse

ANTHROPIC_URL = "https://api.anthropic.com/v1/messages"
MAX_BODY = 12_000_000


class Settings:
    def __init__(self) -> None:
        self.api_key = os.environ.get("ANTHROPIC_API_KEY", "")
        self.model = os.environ.get("ANTHROPIC_MODEL", "claude-sonnet-5-5")
        self.tokens = [t.strip() for t in os.environ.get("PROXY_TOKENS", "").split(",") if t.strip()]
        self.rate = int(os.environ.get("RATE_LIMIT_PER_MIN", "30"))


class RateLimiter:
    def __init__(self, per_minute: int) -> None:
        self.per_minute = per_minute
        self.hits: dict[str, deque[float]] = defaultdict(deque)

    def check(self, key: str) -> bool:
        now = time.monotonic()
        q = self.hits[key]
        while q and now - q[0] > 60:
            q.popleft()
        if len(q) >= self.per_minute:
            return False
        q.append(now)
        return True


def create_app(settings: Settings | None = None, upstream: httpx.AsyncClient | None = None) -> FastAPI:
    cfg = settings or Settings()
    app = FastAPI(title="RE:SET AI proxy", docs_url=None, redoc_url=None)
    limiter = RateLimiter(cfg.rate)
    client = upstream or httpx.AsyncClient(timeout=httpx.Timeout(60.0))

    def authorize(authorization: str | None = Header(default=None)) -> str:
        if not cfg.tokens:
            raise HTTPException(503, "Proxy has no PROXY_TOKENS configured.")
        presented = (authorization or "").removeprefix("Bearer ").strip()
        # Compare against every token without early exit so timing does not reveal which matched.
        ok = False
        for t in cfg.tokens:
            ok |= secrets.compare_digest(presented.encode(), t.encode())
        if not ok:
            raise HTTPException(401, "Invalid token.")
        return presented

    @app.middleware("http")
    async def limit_body(request: Request, call_next):
        length = request.headers.get("content-length")
        if length and length.isdigit() and int(length) > MAX_BODY:
            from fastapi.responses import JSONResponse
            return JSONResponse({"detail": "Request too large."}, status_code=413)
        return await call_next(request)

    @app.get("/healthz")
    async def healthz() -> dict[str, bool]:
        return {"ok": True, "provider_configured": bool(cfg.api_key)}  # type: ignore[return-value]

    @app.post("/v1/ai/complete", response_model=AIResponse)
    async def complete(req: AIRequest, token: str = Depends(authorize)) -> AIResponse:
        if not cfg.api_key:
            raise HTTPException(503, "Provider key is not configured on the server.")
        if not limiter.check(token):
            raise HTTPException(429, "Too many requests. Try again in a minute.")
        try:
            r = await client.post(
                ANTHROPIC_URL,
                json=to_anthropic(req, cfg.model),
                headers={"x-api-key": cfg.api_key, "anthropic-version": "2023-06-01", "content-type": "application/json"},
            )
        except httpx.TimeoutException:
            raise HTTPException(504, "The AI provider timed out.")
        except httpx.HTTPError:
            raise HTTPException(502, "Could not reach the AI provider.")
        if r.status_code == 429:
            raise HTTPException(429, "The AI provider is rate limiting. Try again shortly.")
        if r.status_code in (401, 403):
            # The server's key is wrong. Do not pass the provider's message to the phone.
            raise HTTPException(502, "The server's AI credentials were rejected.")
        if r.status_code >= 400:
            raise HTTPException(502, f"The AI provider returned an error ({r.status_code}).")
        try:
            return from_anthropic(r.json())
        except (ValueError, KeyError):
            raise HTTPException(502, "Unreadable reply from the AI provider.")

    return app


app = create_app()
