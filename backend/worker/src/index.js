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
  // 1d/15m gives the intraday shape for a sparkline (~26 points); meta carries the quote.
  const url = `https://query1.finance.yahoo.com/v8/finance/chart/${encodeURIComponent(symbol)}?range=1d&interval=15m`;
  const r = await fetch(url, { headers: { "user-agent": "Mozilla/5.0 MorningVault" } });
  if (!r.ok) throw new Error(`stock source ${r.status}`);
  const result = (await r.json())?.chart?.result?.[0];
  const meta = result?.meta;
  const price = meta?.regularMarketPrice;
  const prev = meta?.chartPreviousClose ?? meta?.previousClose;
  if (!(price > 0) || !(prev > 0)) throw new Error(`no data for ${symbol}`);
  const closes = (result?.indicators?.quote?.[0]?.close || []).filter((v) => typeof v === "number" && v > 0);
  return { price, change24h: ((price - prev) / prev) * 100, prevClose: prev, series: closes.slice(-40) };
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
  // Last 24h of 30-minute candles for the sparkline ([time, low, high, open, close, vol], newest first).
  let series = [];
  try {
    const c = await fetch(`https://api.exchange.coinbase.com/products/${symbol}-USD/candles?granularity=900`, {
      headers: { "user-agent": "MorningVault" },
    });
    if (c.ok) series = (await c.json()).slice(0, 96).reverse().map((k) => k[4]).filter((v) => v > 0);
  } catch {}
  return { price, change24h: ((price - open) / open) * 100, prevClose: open, series };
}

async function quote(symbol, ctx) {
  const cache = caches.default;
  const key = new Request(`https://cache.morningvault.internal/q/${symbol}`);
  const hit = await cache.match(key);
  if (hit) return { ...(await hit.json()), cached: true };
  try {
    const q = CRYPTO.has(symbol) ? await fetchCrypto(symbol) : await fetchStock(symbol);
    const row = {
      symbol, price: q.price, change24h: Math.round(q.change24h * 100) / 100,
      prevClose: q.prevClose, series: q.series || [], cached: false, error: null,
    };
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
