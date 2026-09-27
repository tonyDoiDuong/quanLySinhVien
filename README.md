# NTA Daily Liquidity Story

MT5 (MQL5) indicator that follows the intraday liquidity story as one state machine:
**ASIA → LONDON → NEW YORK → displacement → MSS → FVG → retrace**.

- Indicator: `MQL5/Indicators/NTA/NTA_DailyLiquidityStory.mq5`
- Engine / stats / renderer: `MQL5/Include/NTA/DailyLiquidityStory/`
- CSV statistics aggregator: `tools/dls_stats.py`
- Full documentation (Vietnamese): [`docs/DailyLiquidityStory.md`](docs/DailyLiquidityStory.md)
