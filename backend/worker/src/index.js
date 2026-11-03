// MorningVault market proxy (Cloudflare Worker).
// Replaces the retired Fly/Polygon server. Same API the app already calls:
//   GET /market/batch?symbols=SPY,BTC  -> [{symbol, price, change24h, cached, error}]
//   GET /market/<SYMBOL>               -> {symbol, price, change24h, cached, error}
//   GET /health
// No API keys: stocks/ETFs from Yahoo's public chart endpoint, crypto from Coinbase's
// public exchange stats. Responses are cached at the edge for 5 minutes, so the phone
// never talks to a third party and upstreams see at most one call per symbol per 5 min.
// change24h is percent: stocks vs previous close, crypto vs 24h open.

const CRYPTO = new Set(["BTC", "ETH", "SOL", "BNB", "XRP", "ADA", "DOGE", "DOT", "AVAX", "LINK", "LTC"]);
const TTL = 300;
const MAX_SYMBOLS = 25;
const SYMBOL_RE = /^[A-Z0-9.\-^=]{1,12}$/;

const json = (body, status = 200, extra = {}) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json", "cache-control": `public, max-age=${TTL}`, ...extra },
  });

async function fetchStock(symbol) {
  const url = `https://query1.finance.yahoo.com/v8/finance/chart/${encodeURIComponent(symbol)}?range=5d&interval=1d`;
  const r = await fetch(url, { headers: { "user-agent": "Mozilla/5.0 MorningVault" } });
  if (!r.ok) throw new Error(`stock source ${r.status}`);
  const meta = (await r.json())?.chart?.result?.[0]?.meta;
  const price = meta?.regularMarketPrice;
  const prev = meta?.chartPreviousClose ?? meta?.previousClose;
  if (!(price > 0) || !(prev > 0)) throw new Error(`no data for ${symbol}`);
  return { price, change24h: ((price - prev) / prev) * 100 };
}

async function fetchCrypto(symbol) {
  const r = await fetch(`https://api.exchange.coinbase.com/products/${symbol}-USD/stats`, {
    headers: { "user-agent": "MorningVault" },
  });
  if (!r.ok) throw new Error(`crypto source ${r.status}`);
  const d = await r.json();
  const price = parseFloat(d.last);
  const open = parseFloat(d.open);
  if (!(price > 0) || !(open > 0)) throw new Error(`no data for ${symbol}`);
  return { price, change24h: ((price - open) / open) * 100 };
}

async function quote(symbol, ctx) {
  const cache = caches.default;
  const key = new Request(`https://cache.morningvault.internal/q/${symbol}`);
  const hit = await cache.match(key);
  if (hit) return { ...(await hit.json()), cached: true };
  try {
    const q = CRYPTO.has(symbol) ? await fetchCrypto(symbol) : await fetchStock(symbol);
    const row = { symbol, price: q.price, change24h: Math.round(q.change24h * 100) / 100, cached: false, error: null };
    ctx.waitUntil(cache.put(key, json(row)));
    return row;
  } catch (e) {
    return { symbol, price: 0, change24h: 0, cached: false, error: String(e.message || e) };
  }
}

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);
    if (request.method !== "GET") return json({ error: "method not allowed" }, 405);
    if (url.pathname === "/health") return json({ status: "ok", time: new Date().toISOString() }, 200, { "cache-control": "no-store" });

    if (url.pathname === "/market/batch") {
      const symbols = [...new Set((url.searchParams.get("symbols") || "")
        .split(",").map((s) => s.trim().toUpperCase()).filter((s) => SYMBOL_RE.test(s)))].slice(0, MAX_SYMBOLS);
      if (!symbols.length) return json({ error: "symbols required" }, 400);
      return json(await Promise.all(symbols.map((s) => quote(s, ctx))));
    }

    const m = url.pathname.match(/^\/market\/([^/]+)$/);
    if (m) {
      const s = decodeURIComponent(m[1]).toUpperCase();
      if (!SYMBOL_RE.test(s)) return json({ error: "bad symbol" }, 400);
      const row = await quote(s, ctx);
      return json(row, row.error ? 502 : 200);
    }
    return json({ error: "not found" }, 404);
  },
};
