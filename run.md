# Audio Processing Pipeline — Full Batch Benchmark

**Date:** 2026-09-07
**Source log:** `run-full.log`
**Command:** `.venv\Scripts\python.exe scripts\local_test.py --workers 8 --force`

## What was tested

The full pipeline — call recording → speech-to-text → LLM classification → structured JSON output — running over the complete sample set of 50 call recordings (~4 hours 15 minutes of audio) against live Azure AI Foundry endpoints. Execution was parallelised across 8 concurrent worker threads.

| Component | Service |
|---|---|
| Transcription | Azure AI Foundry — Fast Transcription (`2025-10-15`) |
| Classification | Azure OpenAI (`gpt-5.4`), structured outputs |
| Authentication | Microsoft Entra ID via `DefaultAzureCredential` — no keys in config |

## Headline results

| Metric | Result |
|---|---|
| Recordings processed | 50 of 50 (100% success, 0 failures) |
| Total audio processed | 255.3 minutes (4h 15m) |
| **End-to-end wall clock** | **167.6 seconds (2m 48s)** |
| Throughput | ~18 recordings per minute |
| Real-time factor | **91.4×** — one hour of audio processed in ~39 seconds |
| Compute time (summed across threads) | 1,264.9s (21.1 minutes) |
| Speed-up vs. sequential | **7.5×** on 8 workers (94% parallel efficiency) |
| Average per recording | 3.4s wall clock / 25.3s service time |

The same workload run sequentially would take approximately **21 minutes**. Parallel execution brought that down to **under 3 minutes**.

## Where the time goes

| Phase | Share of processing time |
|---|---|
| Speech-to-text | **86%** |
| Classification | **14%** |

Per-recording ranges: transcription 10.8s–42.8s, classification 2.3s–6.0s.

Transcription is the dominant cost, so it is the right target for any further optimisation.

## Classification output

| Category | Count |
|---|---|
| Service request | 16 |
| Cancellation | 9 |
| Complaint | 9 |
| Fraud | 8 |
| Sales | 8 |

- **9 of 50 calls (18%)** were auto-flagged for human review where model confidence fell below the 0.75 threshold.
- Confidence across the batch ranged 0.64–0.98; the majority scored 0.95 or above.

## Observations and next steps

1. **Concurrency tuning.** An earlier run at 12 concurrent workers triggered service-side throttling (HTTP 429) and lost 28% of the batch (36/50 completed). At 5–8 workers the pipeline runs clean with zero failures. Recommend **8 as the working concurrency ceiling** for this subscription tier, and requesting a quota increase if higher throughput is needed.
2. **Category refinement.** Eight recordings intended as `other` were classified as `service_request` (confidence 0.78–0.92) — which is why `other` shows 0 and `service_request` shows 16. The category definitions in the classification prompt are worth a review to sharpen that boundary.
3. **Scale projection.** At the measured rate, a 1,000-call day (~85 hours of audio) would complete in roughly **50 minutes** at current concurrency — comfortably within an overnight or intra-day batch window.
4. **Resilience.** Per-recording error isolation and automatic retry with exponential backoff (6 attempts, capped at 30s, honouring `retry-after`) are in place; a single failed recording does not affect the batch.

## Raw report block

```
--------------------------------------------------------------------
processed         50 ok, 0 failed, 8 worker(s)
wall clock        167.6s
audio processed   255.3 min
service time      1264.9s summed across threads
speedup           7.5x versus serial
per recording     3.4s wall, 25.3s service
realtime factor   91.4x audio per second
split             transcribe 86%, classify 14%
categories        cancellation 9, complaint 9, fraud 8, sales 8, service_request 16
human review      9
```

## Reproducing

```powershell
.venv\Scripts\python.exe scripts\local_test.py --workers 8 --force 2>&1 | Tee-Object -FilePath run-full.log
```

Results are written to `samples/results/{stem}.json`. Omit `--force` to skip recordings that already have results.

### Known environment issue

VS Code's venv auto-activation sets `PYTHONHOME` / `PYTHONPATH` / `VIRTUAL_ENV`, which breaks the Azure CLI's bundled Python when `AzureCliCredential` shells out to `az`. This surfaces as a `ClientAuthenticationError` with the actionable line (`AzureCliCredential: Failed to invoke the Azure CLI`) buried in the aggregate credential-chain error. Clearing those three variables in the shell resolves it.
