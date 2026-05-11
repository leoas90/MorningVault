# MorningVault Market API — Backend

FastAPI proxy that calls Polygon.io server-side, keeping your API key out of the iOS app. Includes a file-based cache backed by a Fly.io persistent volume.

---

## Quick Start (local dev)

```bash
cd backend
pip install -r requirements.txt
POLYGON_API_KEY=your_key uvicorn server:app --reload --port 8080
```

Test it:
```bash
curl http://localhost:8080/health
curl http://localhost:8080/market/AAPL
curl "http://localhost:8080/market/batch?symbols=AAPL,BTC,ETH"
```

---

## Deploy to Fly.io (free)

### One-time setup

```bash
# Install flyctl
curl -L https://fly.io/install.sh | sh

# Authenticate
fly auth login

# Launch (creates fly.toml from Dockerfile automatically)
cd backend
fly launch
# App name: morningvault-market-api (or your choice)
# Region: choose closest to you
# Override? No

# Create persistent cache volume (survives restarts)
fly volumes create market_cache --size 1

# Set your Polygon.io API key (stored securely on Fly, not in code or env)
fly secrets set POLYGON_API_KEY=your_key_here

# Deploy
fly deploy
```

Your API will be live at `https://morningvault-market-api.fly.dev`.

### Redeploy after code changes

```bash
cd backend
fly deploy
```

### Useful commands

```bash
fly logs                 # Tail logs
fly secrets set POLYGON_API_KEY=new_key   # Rotate key
fly ssh console          # Shell into the container
fly scale count 1        # Ensure 1 machine running (free tier: 3 shared)
```

---

## API Reference

| Endpoint | Description |
|----------|-------------|
| `GET /health` | Returns `{ status, polygon_key_configured }` |
| `GET /market/{symbol}` | Single symbol, e.g. `/market/AAPL`, `/market/BTC` |
| `GET /market/batch?symbols=AAPL,BTC,ETH` | Up to ~20 symbols, comma-separated |

**Response shape:**
```json
{
  "symbol": "AAPL",
  "price": 189.45,
  "change24h": 1.23,
  "cached": false,
  "error": null
}
```

**Batch returns array** — individual entries may have `error` set if that symbol failed. The batch never fails partial.

---

## iOS App Setup

In Settings → Market Data, enter your backend URL:
```
https://morningvault-market-api.fly.dev
```

Leave blank to use local cache only (works offline, no live prices).

---

## Scaling to Paid

When you're ready for the Polygon.io paid tier ($200/mo Starter or $500/mo Growth):

1. Upgrade your Polygon.io plan at [polygon.io](https://polygon.io)
2. Update the secret on Fly: `fly secrets set POLYGON_API_KEY=new_key`
3. The iOS app requires **zero changes** — it already talks to this backend
4. Optionally scale up: `fly scale memory 512mb` or `fly scale count 2`

The free tier is fine for development and early users. The paid backend is a single env var swap away.