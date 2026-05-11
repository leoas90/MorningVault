"""
MorningVault Backend — Polygon.io market data proxy.
Keeps API keys server-side, adds caching and rate-limit handling.
"""

import os
import json
import time
import httpx
import asyncio
from datetime import datetime
from pathlib import Path
from typing import Optional

from fastapi import FastAPI, HTTPException, Query
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel

# ─── Config ────────────────────────────────────────────────────────────────────

POLYGON_API_KEY = os.getenv("POLYGON_API_KEY", "")
POLYGON_BASE_URL = "https://api.polygon.io"

# Cache directory — backed by Fly.io persistent volume at /app/.cache
CACHE_DIR = Path(os.getenv("CACHE_DIR", "/app/.cache"))
CACHE_TTL = 300  # 5 minutes

CACHE_DIR.mkdir(parents=True, exist_ok=True)

# ─── Pydantic models ────────────────────────────────────────────────────────────

class MarketResponse(BaseModel):
    symbol: str
    price: float
    change24h: float
    cached: bool
    error: Optional[str] = None

# ─── FastAPI app ────────────────────────────────────────────────────────────────

app = FastAPI(title="MorningVault Market API", version="1.0.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # Lock down to your app's bundle ID in production
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


# ─── File-based cache (persists across container restarts) ─────────────────────

def _cache_path(symbol: str) -> Path:
    return CACHE_DIR / f"{symbol.upper()}.json"


def _cache_read(symbol: str) -> Optional[dict]:
    """Read cached market data if fresh."""
    path = _cache_path(symbol)
    if not path.exists():
        return None
    try:
        raw = json.loads(path.read_text())
        age = time.time() - raw.get("_cached_at", 0)
        if age > CACHE_TTL:
            return None
        return raw
    except (json.JSONDecodeError, OSError):
        return None


def _cache_write(symbol: str, price: float, change24h: float) -> None:
    """Write market data to cache."""
    path = _cache_path(symbol)
    try:
        path.write_text(json.dumps({
            "symbol": symbol.upper(),
            "price": price,
            "change24h": change24h,
            "_cached_at": time.time(),
        }))
    except OSError:
        pass  # Volume write failed — non-fatal, serve without caching


# ─── Polygon helpers ────────────────────────────────────────────────────────────

def _polygon_symbol(symbol: str) -> str:
    """Map common symbols to Polygon format."""
    crypto = {"BTC", "ETH", "SOL", "BNB", "XRP", "ADA", "DOGE", "DOT", "AVAX", "LINK"}
    upper = symbol.upper()
    if upper in crypto:
        return f"X:{upper}USD"
    return upper


async def _fetch_from_polygon(symbol: str) -> tuple[float, float]:
    """Call Polygon.io prev endpoint. Raises on failure."""
    if not POLYGON_API_KEY:
        raise RuntimeError("POLYGON_API_KEY not configured on the server")

    ticker = _polygon_symbol(symbol)
    url = (
        f"{POLYGON_BASE_URL}/v2/aggs/ticker/{ticker}/prev"
        f"?adjusted=true&apiKey={POLYGON_API_KEY}"
    )

    async with httpx.AsyncClient(timeout=10.0) as client:
        resp = await client.get(url)
        if resp.status_code == 429:
            raise HTTPException(status_code=429, detail="Polygon rate limited — try again shortly")
        if resp.status_code != 200:
            raise HTTPException(status_code=502, detail=f"Polygon returned {resp.status_code}")

        data = resp.json()
        results = data.get("results", [])
        if not results:
            raise HTTPException(status_code=404, detail=f"No data for {symbol}")

        r = results[0]
        open_ = r["o"]
        close = r["c"]
        if open_ <= 0 or close <= 0:
            raise HTTPException(status_code=422, detail=f"Invalid price data for {symbol}")

        change = ((close - open_) / open_) * 100
        return close, change


# ─── Routes ───────────────────────────────────────────────────────────────────

@app.get("/market/{symbol}", response_model=MarketResponse)
async def get_market(symbol: str):
    """
    Returns price + 24h % change for any stock or crypto symbol.
    Results are cached for 5 minutes server-side (persists across restarts).

    Examples:
      GET /market/AAPL
      GET /market/BTC
    """
    symbol = symbol.upper()

    # 1. Serve from cache if fresh
    if cached := _cache_read(symbol):
        return MarketResponse(
            symbol=symbol,
            price=cached["price"],
            change24h=cached["change24h"],
            cached=True,
        )

    # 2. Fetch fresh from Polygon
    try:
        price, change = await _fetch_from_polygon(symbol)
    except httpx.HTTPStatusError as exc:
        raise HTTPException(status_code=exc.response.status_code, detail=str(exc))
    except Exception as exc:
        raise HTTPException(status_code=500, detail=str(exc))

    # 3. Update cache and return
    _cache_write(symbol, price, change)
    return MarketResponse(symbol=symbol, price=price, change24h=change, cached=False)


@app.get("/market/batch", response_model=list[MarketResponse])
async def get_market_batch(symbols: str = Query(..., description="Comma-separated symbols, e.g. AAPL,SPY,BTC")):
    """
    Batch endpoint — fetches multiple symbols concurrently.
    Returns whatever data is available, never fails partial.
    """
    symbol_list = [s.strip().upper() for s in symbols.split(",") if s.strip()]
    results: list[MarketResponse] = []

    async with httpx.AsyncClient(timeout=15.0) as client:
        for symbol in symbol_list:
            if cached := _cache_read(symbol):
                results.append(MarketResponse(
                    symbol=symbol, price=cached["price"],
                    change24h=cached["change24h"], cached=True,
                ))
                continue

            try:
                price, change = await _fetch_from_polygon(symbol)
                _cache_write(symbol, price, change)
                results.append(MarketResponse(symbol=symbol, price=price, change24h=change, cached=False))
            except Exception as exc:
                results.append(MarketResponse(
                    symbol=symbol, price=0, change24h=0, cached=False,
                    error=str(exc),
                ))

    return results


@app.get("/health")
async def health():
    return {
        "status": "ok",
        "polygon_key_configured": bool(POLYGON_API_KEY),
        "cache_dir": str(CACHE_DIR),
    }


# ─── Run locally ───────────────────────────────────────────────────────────────

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8080)
