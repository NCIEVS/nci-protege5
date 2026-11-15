# NCI Protégé — Lazy Project-Open Performance Over the VPN

Tracking the slow project-open experienced when the desktop editor runs far from
the NCI dev-tier Virtuoso, connected over the VPN. This is a living document —
each optimization appends a row to the Progress table with a fresh measurement.

## Summary

Opening a server project is **~12× slower over the VPN than locally** (≈2 min 49 s
vs ≈14 s for the same workflow). The cause is **not** a code defect and **not**
data volume — it is **network/remote latency multiplied by the number of
sequential Virtuoso queries** the lazy model issues during open. The single
dominant cost is the schema load (~120 s of the ~169 s), which runs ~12 queries
one after another, each paying the per-query penalty of the remote link.

## Baseline measurements — 2026-11-16

Same open workflow, measured from the client log (`protege.log`).

| Step | Local (`localhost`) | VPN (NCI dev tier) | Slowdown |
|------|---------------------|--------------------|----------|
| `buildDefinedByGenus` (10,806 rows) | 1,473 ms | 4,328 ms | ~3× |
| `getChildren(owl:Thing)` (**21 rows**) | 729 ms | 5,250 ms | ~7× |
| Schema load span (import → schema loaded) | ~6–9 s | **~129 s** | ~17× |
| **Total project open** | **~14 s** | **~2 min 49 s** | **~12×** |

## Root cause

- **Per-query overhead, not data transfer.** `getChildren(owl:Thing)` returns
  only **21 rows** yet takes **5.3 s** over the VPN (0.7 s locally). A tiny query
  being *slower* than the 10,806-row one proves the cost is fixed per request —
  round-trip latency plus remote query execution, likely amplified by the reverse
  proxy in front of the dev-tier Virtuoso — not bandwidth.
- **The open is a sequence of ~15–20 Virtuoso queries run serially**, so that
  per-query penalty compounds:
  - Hierarchy warm-up: `buildDefinedByGenus` + `getChildren` (~10 s on VPN).
  - **Schema load dominates (~120 s):** the 2,394 schema seeds are fetched in
    `SCHEMA_SEED_BATCH = 200` chunks → ~12 sequential `directTriples` queries,
    each ~10 s over the VPN. (Already batched, and the connection is reused — so
    it is ~12 heavy *sequential* queries, not thousands of round-trips.)
  - Then per-restored-tab entity materialization.
- **The auto-updater firing ~5× during open is a symptom, not a cause** — its
  30 s timer simply keeps elapsing while open is slow; each poll is one more
  remote round-trip.

## Optimization plan (in order of expected impact)

1. **Parallelize the independent open-path queries.** The ~12 schema
   `directTriples` batches are independent of one another, as are several warm-up
   queries. Running them concurrently collapses ~120 s of serial waiting toward
   the cost of the slowest single query. Highest-impact change for a high-latency
   link; client-only.
2. **Fewer, heavier queries where safe** (e.g. a single closure query for the
   whole schema) — trades round-trip count against per-query result size; measure.
3. **Suppress the auto-updater while a project is opening** — removes the mid-open
   polls and the noise.
4. **Remote-side investigation** — the 5 s / 21-row `getChildren` warrants looking
   at the Virtuoso/proxy layer (cold cache, load, proxy latency). Comparing the
   same query in Conductor directly on the server vs. through the client isolates
   proxy overhead.

## Progress

| Date | Change | VPN open | Local open | Notes |
|------|--------|----------|------------|-------|
| 2026-11-16 | Baseline (no change) | ~2 min 49 s | ~14 s | Measurements above |
