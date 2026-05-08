# Third-Party Services Disclosure

MorningVault uses the following third-party services. Each is used only for the stated purpose and transmits no personal identifiers.

## Weather

**wttr.in**
- Purpose: City-level weather data
- Data shared: City name (approximate, no GPS coordinates)
- Endpoint: `https://wttr.in/~{city}?format=j1`
- ToS: CC BY-SA 4.0 — acceptable for personal and commercial use with attribution
- Privacy: No cookies, no user tracking

## Market Data

**CoinGecko**
- Purpose: Cryptocurrency prices (BTC, ETH, SOL, etc.)
- Data shared: Symbol only, no PII
- Endpoint: `https://api.coingecko.com/api/v3/simple/price`
- ToS: Free tier acceptable for personal use. Paid plan recommended for App Store distribution per CoinGecko ToS restrictions on commercial API access.
- ⚠️ Open flag: Commercial distribution requires paid plan or explicit ToS sign-off

**Yahoo Finance**
- Purpose: Stock prices (SPY, QQQ, AAPL, etc.)
- Data shared: Symbol only, no PII
- Endpoint: `https://query1.finance.yahoo.com/v8/finance/chart/{symbol}`
- ToS: No authorized API for third-party display. yfinance library operates as a scraper.
- ⚠️ Open flag: Yahoo Finance ToS does not authorize third-party use. Using Yahoo Finance data in a distributed app carries legal risk. Alternative: use paid data provider (Alpha Vantage, IEX Cloud, or similar).

## RSS Feeds

FeedKit (Apple SPM) parses RSS/Atom feeds from hardcoded public news sources. No authentication required. No user-specific data is transmitted.

## Local Processing

**Apple HealthKit**: On-device only, no network transmission
**Apple EventKit**: On-device only, no network transmission
**Apple Foundation Models**: On-device AI processing, no network transmission

## Privacy Summary

No third-party service receives: device ID, email, precise location, health data, calendar content, or any user-identifying information.