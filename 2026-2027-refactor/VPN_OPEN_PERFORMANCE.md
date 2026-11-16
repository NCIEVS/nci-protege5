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
| 2026-11-16 | Step 1: parallelize schema-seed `directTriples` batches | ~no change (schema load 128,358 ms) | — | **Disproved the target.** The schema has only **308 seed entities** → just **2** batches, so parallelizing them does nothing. The real cost is elsewhere (see Findings). |
| 2026-11-16 | Instrumented full schema breakdown | schema load 124,530 ms | — | `seeds=935ms fetchClosure=38,618ms materialise=84,456ms rest=520ms`; `skolemClosure=36,557ms (127 round-trips)`. Two real targets: `materialise` (68%) and `skolemClosure` (31%). |
| 2026-11-16 | **Fix A: batch-prime labels before `addAxioms`** (materialise) | *pending measurement* | — | `materialise` was ~308 per-entity label round-trips (308 × ~274 ms). Prefetch all schema-entity labels in one query so the renderer/index lookups during the bulk add are cache hits. |
| 2026-11-16 | Fix A **confirmed** | schema load **40,513 ms** (from 124,530) | — | `materialise` **84,456 → 3,075 ms**. Schema load 3× faster. Remaining cost is `skolemClosure` (36 s, 89%). |
| 2026-11-16 | **Fix B: chunked rdf:rest walk** (skolemClosure) | *pending measurement* | — | `owl:oneOf` list walk was 127 serial round-trips. Virtuoso rejects `rdf:rest*` (transitive) and nested OPTIONALs degrade past ~8 hops (K=8: 0.4 s, K=12: 12 s), so walk 8 hops/query with a boundary-only frontier → ~16 round-trips. Verify triple count stays **1371** (completeness). |
| 2026-11-16 | Fix B **confirmed** | skolemClosure 34,111 → **30,008 ms**; schema load 40,513 → **38,009 ms** | — | Round-trips **127 → 16**, triples **1371** (complete, no truncation). But time barely moved: round-trips were *not* the bottleneck — baseline was 127 × ~268 ms (VPN latency), Fix B is 16 × ~1,875 ms (each 8-hop nested-OPTIONAL is expensive for Virtuoso to execute). The cost is the list walk itself, not the trips. **Next lever: defer the enumeration closure out of the open path (load on-demand) → removes ~30 s from every open.** |
| 2026-11-16 | **Plan A: defer datatype enumerations to a background thread** | *pending measurement* | — | Dropped `rdfs:Datatype` from the synchronous seed query and the `datatypeClosure()` call from `fetchClosure`; added `loadDatatypeEnumerationsAsync` (daemon thread, active-ontology guard) that loads datatype declarations + their oneOf closure *after* open. The ~30 s list walk stays, but off the blocking path. Expect `fetchClosure` ~33 → ~3 s, schema load ~38 → ~6 s. Enumerations populate ~30 s after open. |
| 2026-11-16 | Plan A **confirmed** | schema load 38,009 → **5,553 ms** | — | `fetchClosure` 32,947 → **1,873 ms**. 263 entities sync + 45 datatypes deferred (= 308 ✓); enumerations loaded in the background on `[datatype-enum-loader]` in 33,772 ms (**57 axioms from 45 datatypes**, non-blocking). **Schema load arc: 124.5 → 40.5 (Fix A) → 38 (Fix B) → 5.5 s (Plan A), ~22× overall.** The remaining 34 s is entirely off the open path. |
| 2026-11-16 | Instrumented the **open critical path** (beyond schema) | open ~30 s | — | Added `[perf] open step …` probes. `buildVersionedOntology`=2.7 s, `seedSearchIndex`=8 ms, **`setActiveProject`=24 s** (schema load is only 5.2 s of it). The long-mysterious "~22 s gap" *is* `setActiveProject`; `seedSearchIndex` (base index already seeded) and the project-list fetch are off the critical path. |
| 2026-11-16 | Split `setActiveProject` → `setActiveOntology` | — | — | `setActiveProject` = `setActiveOntology` **18.5 s** + `recheckPlugins` 24 ms + `fireChangeEvent` 5.5 s. Inside `setActiveOntology`: **`rebuildEntityIndices` = 19.6 s**, everything else ~0 ms (ontology still empty here; schema loads later in `fireChangeEvent`). |
| 2026-11-16 | **Root cause: entity-render label storm** | — | — | `OWLEntityRenderingCache.rebuild()` renders ~50 standard entities (owl built-ins, BUILT_IN annotation props, Dublin Core, every known OWL datatype) and calls `getRendering()` on each → **one Virtuoso label lookup per entity, serially** over the VPN (~50 × ~250 ms ≈ 19.6 s). Same per-entity-label pattern as Fix A. Also the likely cause of the intermittent first-open hang. |
| 2026-11-16 | **Fix: batch-prime render labels** (`rebuild()`) | **open ~30 → ~10–12 s** | — | Collect the ~50 render IRIs and `LazyLabelCache.prefetch()` them in one query before the loop (no-op when the triple store isn't configured, so standard Protégé is unaffected). `rebuildEntityIndices` **19,628 → 672 ms (~29×)**; `setActiveOntology` 18,542 → 674 ms; **`setActiveProject` 24,075 → 7,239 ms**. Opened first try. |
| 2026-11-16 | **UX: empty project list after fresh login** | list now instant | — | `fetchProjects` measured at **2 ms (11 projects)** — the list was never slow. The panel was blank because `showLoginWhenNecessary` only populated on a *second* `focusGained`; a fresh non-admin login now calls `loadProjectList()` directly. (An interim off-EDT rewrite was reverted — a 2 ms fetch needs no worker thread.) |

## Outcome — 2026-11-16

Project open over the VPN went from **~2 min 49 s → ~10–12 s**. The two dominant costs were both **per-entity label round-trips**, fixed by the same one-query batch-prefetch pattern:

1. **Schema `materialise`** (Fix A): 84.5 s → 3.1 s.
2. **Entity-render cache `rebuild()`**: 19.6 s → 0.67 s.

Supporting changes: datatype `owl:oneOf` enumerations deferred to a background thread (schema load 124.5 s → 5.5 s), the `skolemClosure` walk chunked (127 → 16 round-trips, list integrity preserved at 1371 triples), and the project-list populated immediately on login. The remaining open cost is schema load (~5.9 s) + `buildVersionedOntology` (~2.8 s) + hierarchy warm-up — candidates for a later pass.

## Findings — 2026-11-16 (after step 1)

The new schema-load timing shows `Lazily loaded schema: 2394 axioms from 308
entities in 128358ms`, and the open window shows a **~120 s silent gap** (no new
query-client log lines) running on the *shared* store. That signature points at
`datatypeClosure() → skolemClosure()`, which walks the datatype `owl:oneOf`
skolem/list chains **one Virtuoso round-trip per BFS level**. Deep lists ⇒ many
sequential round-trips ⇒ ~120 s over the VPN. `skolemClosure` is now instrumented
(`[perf] skolemClosure: … levels (round-trips) … in …ms`) to confirm the level
count before rewriting it to fetch the closure in 1–2 queries instead of N levels.

### Confirmed 2026-11-16 (instrumented)

`[perf] skolemClosure: 21 seeds, 127 levels (round-trips), 1371 triples in 37503ms`
— the datatype skolem walk is **127 serial Virtuoso round-trips = 37.5 s**. But the
schema load is **125.8 s**, so there is a **second, larger cost (~85 s) after the
closure**, in `materialise(...)` (which `addAxioms` ~2,394 axioms, firing change
listeners) + `ensureOntologyAnnotationsLoaded(...)`. Full sub-step timing added
(`[perf] schema breakdown: seeds=… fetchClosure=… materialise=… rest=…`) to split
that 85 s before fixing. Two targets, then:
1. `skolemClosure` — collapse the 127 per-level round-trips into 1–2 queries.
2. the ~85 s post-closure step — pending the `materialise` vs `rest` split.
