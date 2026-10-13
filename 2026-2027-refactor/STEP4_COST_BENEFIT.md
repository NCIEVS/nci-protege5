# Step 4 — Cost/Benefit Decision

Status: decision aid, 2026-10-13. Companion to `MIGRATION_PLAN.md` (Step 4) and `V2_SCOPING.md`.
Purpose: make an explicit, informed call on **whether and how far to pursue Step 4** now that
Step 3 is not just code-complete but validated on the real remote deployment.

---

## Decision (2026-10-13): Option C+, with a two-mode UX

**Chosen: C+** — the two read-path hotspots of Option C **plus** a small, explicit "C-plus" set that
makes the stock tabs *trustworthy* under lazy without building the v2 model:
- A hard **mode-aware guard**: generic stock-tab editing is disabled for server/lazy projects.
- **Virtuoso-backed (server-side `COUNT`) metrics** for the **Active Ontology** tab.

**Option B is deferred, not cancelled** — revisit once everything else is tight and running smoothly
over the VPN. The scale argument no longer justifies B, and (see §2b) **B does not, by itself, make
the stock tabs work.**

The governing UX is a **two-mode model** (see §2c): classic in-RAM mode for `File → Open` of a local
`.owl`, and lazy/server mode for `Open from Server`. The one data-integrity risk the audit found
(generic delete computing references over a *sparse* ontology → orphaned references in Virtuoso) is
eliminated outright in server mode by disabling generic editing there — not by porting the stock
delete onto Virtuoso.

---

## 1. The decision in one sentence

Step 4 as written = **delete the OWL-API-as-runtime-model usage and the dead `owlapi` modules**,
which requires building `owl-rdf-io` **v2** (a new internal runtime model + adapter behind the same
load/save seam). The question is **not** "are we ready" — the scoping and the first slice are done —
but **"is the remaining payoff worth the build, or do we bank the wins and stop short?"**

Keep in mind the permanent scope boundary (from the plan): the OWL API **I/O parsers stay by
design** (they are the keep-set behind `owl-rdf-io`). "Delete owlapi" only ever meant delete the
**runtime model** usage, not the file I/O.

---

## 2. Why the payoff has shifted (what's already banked)

The original motivation for Step 4 was **scale**: get the whole NCI Thesaurus out of RAM. That is
**already achieved by Step 3's lazy model** — the active ontology is now a sparse, per-entity lazy
cache (`LazyClassLoader.materialise()` writes only fetched molecules), not a whole-ontology-in-RAM
object. Concretely, already banked **without** Step 4:

- Lazy read: hierarchy, rendering, labels, entity finder — all Virtuoso/index-backed and abstracted.
- Lazy write: edits → commit → Virtuoso as source of truth; server-side classify, index, squash.
- Deployment-validated this month on the remote server (STRSTARTS cost fix, plugin packaging,
  classify Virtuoso-crash fix, search/index discovery, batched graph delete).
- **Slice 1 of Step 4 already done + committed**: reference retargeting over Virtuoso (the merge/
  retire correctness fix). This is the one piece of Step 4 that was a *correctness* need, not hygiene.

So the **remaining** value of Step 4 is largely **dependency hygiene and coupling reduction**:
deleting dead `owlapi` modules, severing the runtime-model dependency, and collapsing the
edit/commit path onto a model-neutral change representation. Real, but no longer a scale unlock.

---

## 2b. Tab completeness is orthogonal to owlapi removal

A natural question: *"wouldn't Option B make all the stock tabs work?"* **No — not by itself.** Two
independent axes are at play:

- **Axis 1 — runtime model type:** owlapi value objects vs. a new v2 model. ← what B changes.
- **Axis 2 — read completeness:** sparse on-demand cache vs. a complete, queryable store behind the
  read API. ← what actually makes the tabs functional.

The stock tabs break because they call whole-ontology methods (`getClassesInSignature`,
`getAxiomCount`, `getReferencingAxioms`) and expect a *complete* store — that is Axis 2. **B as scoped
does not move Axis 2**: `V2_SCOPING.md`'s disposition for `getActiveOntology()` under B is explicitly
"keep as lazy read cache for now." So a straight B would leave metrics / usage / property-list tabs
just as incomplete, only expressed in a different model type — and would in fact *expand* B's scope,
since a faithful new `OWLOntology` would then have to implement those whole-ontology queries too.

What *does* make a given tab trustworthy is a Virtuoso-backed implementation of the specific read
operation — and most of that is cheap and needs no model rewrite:
- **Metrics = counts** → a SPARQL `COUNT` per metric: exact, fast, no enumeration. (Easier to make
  correct than it ever was classically.)
- **Usage / "used by"** → the bounded "who references E" query already built in Slice 1.
- **Generic-delete correctness** → right the moment `getReferencingAxioms` is Virtuoso-backed.
- **Full flat lists** (all classes/individuals in one widget) are the awkward ones — 232k classes
  exceed Virtuoso's 100k row cap and aren't a sane flat view anyway; paginate or leave as a known
  limitation.

Conclusion: if the goal is working stock tabs, the lever is **targeted Virtuoso-backed reads (≈ C+)**,
**not** the owlapi rewrite. B's real payoff stays dependency hygiene + one clean edit model.

---

## 2c. The two-mode design (the governing UX decision)

Protégé runs in one of two modes, detected from how the project was opened
(`TripleStoreContext.isActive()` / presence of a server+Virtuoso project):

**Mode 1 — Local file (`File → Open` of a `.owl`).** Classic Protégé: the whole ontology is in RAM,
so **all stock tabs work fully** (Entities, Classes, Object/Data Properties, Individuals, metrics,
usage, generic create/edit/delete). Nothing lazy, nothing disabled — unchanged from stock behavior;
the only requirement is that the lazy wiring stays dormant when no server project is open.

**Mode 2 — Open from Server (protege-server + Virtuoso).** Lazy navigation; the EditTab + NCI custom
plugins are the editing surface. The stock tabs are **browse-only**: their *editing* is disabled, so
the sparse-reference hazards (generic delete orphaning refs; generic create skipping the NCI workflow
+ uniqueness check) cannot fire. Incomplete read-only displays (sparse property lists, partial usage)
are acceptable as browse aids, or hidden, per taste.

**The one exception that must be fully correct in Mode 2 is the `Active Ontology` tab** — that is
where NCI modelers edit the ontology-header **revision date**, and they rely on its **metrics being
accurate**. So in Mode 2 that tab stays editable *and* its metrics are served from Virtuoso
(server-side `COUNT`), not from the sparse active ontology.

This cleanly resolves the audit's findings:

| Audit finding | Mode 1 (local file) | Mode 2 (server/lazy) |
|---|---|---|
| Metrics / stats | correct (in-RAM) | **correct via server-side COUNT** (Active Ontology) |
| Obj/Data-prop & Individuals tabs | full | browse-only (sparse display acceptable / hidden) |
| Usage / "used by" views | full | browse-only (incomplete, non-destructive) |
| Generic **delete** (orphan risk) | full & correct | **disabled** (risk eliminated) |
| Generic **create** (no uniqueness check) | full & correct | **disabled** (create via EditTab) |
| Stock description frames | full | works for the selected (materialized) entity |

---

## 3. The three options

### Option A — Bank the wins, stop short (hygiene-only)
Do **not** build `owl-rdf-io` v2. Keep OWL API value types *and* the sparse lazy `OWLOntology` as the
runtime cache. Do a **targeted dependency-hygiene pass** (Step 5 work pulled forward): trim unused
`owlapi` modules that are genuinely unreferenced, pin/modernize deps, delete dead snapshot/legacy code.

- **Cost:** low (days). No model rewrite, no edit/commit churn, no re-test of the whole edit surface.
- **Benefit:** smaller build, fewer redundant deps, less confusion — but `owlapi-api`/`impl` stay on
  the classpath because protégé still speaks `OWLOntology`/`OWLAxiom` at runtime.
- **Risk:** low. Nothing structural changes.
- **Leaves on the table:** the runtime-model coupling and the ~20 change-listener / `OWLOntologyChange`
  edit path stay owlapi-native forever. Fine if that coupling never hurts.

### Option B — Full Step 4 (build `owl-rdf-io` v2)
Build the new internal runtime model + adapter behind the load/save seam; migrate the edit/commit
path to a model-neutral `ChangeRecord` (Slice 2), then the change listeners, then the binaryowl
commit codec; finally delete `owlapi-as-runtime-model` and the dead modules.

- **Cost:** high (weeks). The edit/commit path, `SessionRecorder` undo/redo, ~20 listeners, and the
  commit serialization all touch it. This is the deepest, most test-sensitive surface in the app.
- **Benefit:** true removal of the owlapi runtime dependency; one clean model end-to-end; the
  `ChangesetRdf.transform` seam becomes the sole boundary. Long-term maintainability win.
- **Risk:** high. Edit correctness (merge/split/retire/undo/commit) is the crown jewels; a model swap
  risks subtle regressions. Also **no new user-visible benefit** — scale is already solved.
- **Note:** `V2_SCOPING.md` already judged **Slice 2 (the `ChangeRecord` seam) LOW-VALUE until the v2
  internal model exists** — it's scaffolding with no consumer until B is actually underway. So B is
  effectively all-or-nothing; there is no cheap first slice.

### Option C / C+ — read-path hotspots + mode-aware trustworthy stock tabs (CHOSEN)
Do **not** build v2. Keep the owlapi model. Scope:

**C (core):** close the two remaining read-side owlapi hotspots:
1. `OWLCellRenderer` per-paint reference/axiom check (`getActiveOntology().getReferencingAxioms(e)`
   at `OWLCellRenderer.java:594`, and the icon `getAxioms(e)` check) → cached, index/Virtuoso-derived
   `hasAxioms(e)`.
2. `OWLEntityRenderingCacheImpl.rebuild()` full-signature scan → prime from the index / lazy-populate.

**C+ (stock-tab trust, from the two-mode design in §2c):**
3. **Mode-aware edit guard** — disable generic stock-tab editing (create/delete/edit on
   Classes/Properties/Individuals/Entities) when `TripleStoreContext.isActive()` (server/lazy
   project). Eliminates the generic-delete orphan risk without porting stock delete onto Virtuoso.
4. **Active Ontology metrics over Virtuoso** — back that tab's metrics with server-side `COUNT`
   queries so the revision-date workflow sees accurate numbers in Mode 2.

- **Cost:** low–moderate (days), contained, independently testable.
- **Benefit:** removes the last per-paint / full-signature owlapi scans; makes the stock tabs *safe
  and trustworthy* under lazy without the v2 rewrite; keeps full stock functionality in Mode 1.
- **Risk:** low. Read-only hotspots + a disable-guard + count queries; no edit-model churn.
- **Leaves on the table:** same as A for the edit/commit path (fine — B deferred).

---

## 4. Cross-cutting prerequisite (regardless of option): stock-tab compatibility review

The NCI `nci-edit-tab` edit flow has lazy priming wired in. **Stock Protégé tabs do not**, and power
users use them occasionally:

- **Ontology page** — global stats (axiom/class/property counts) = whole-ontology aggregates over the
  **sparse** lazy active ontology → will report **wrong/partial counts**.
- **Entities tab / Classes / Object&Data Property editors** — generic OWL entity create/edit/delete
  that build `OWLOntologyChange`s directly, **bypassing** `nci-edit-tab`'s `primeReferencingClasses`
  and lazy fallbacks → likely incomplete reference handling, missing-signature lookups, and
  edits that don't round-trip to Virtuoso the way the NCI flow does.

**Status: audit DONE (2026-10-13), see `STOCK_TAB_AUDIT.md`.** Result: read-only stock views mostly
*mislead* (wrong counts, sparse lists, incomplete usage) but don't corrupt data; the only
data-integrity risk is **generic delete** (sparse reference computation → orphans in Virtuoso), with a
secondary duplicate-name risk on generic create. The two-mode design (§2c) addresses all of it:
Mode 1 keeps everything correct in-RAM; Mode 2 disables generic editing and serves Active-Ontology
metrics from Virtuoso.

---

## 5. Recommendation — DECIDED: C+ (see the Decision block up top)

1. Audit done (§4 / `STOCK_TAB_AUDIT.md`).
2. **Proceed with C+**: the two read-path hotspots now, plus the §2c two-mode guard (disable generic
   stock editing in server/lazy mode) and Virtuoso-backed Active-Ontology metrics.
3. **Option B deferred**, not cancelled — revisit once everything else is tight and running smoothly
   over the VPN. Per §2b, B is not the lever for working stock tabs anyway.

---

## 6. Decision checklist

- [x] Stock-tab audit done; classified (see `STOCK_TAB_AUDIT.md`).
- [x] Stock-tab policy decided: **two-mode** (§2c) — Mode 1 full stock; Mode 2 browse-only with
      generic editing disabled; Active Ontology editable with Virtuoso-backed metrics.
- [x] Step 4 path chosen: **C+** (read-path hotspots + mode-aware stock-tab trust). B deferred.
- [ ] Implement C hotspots: `OWLCellRenderer` per-paint check; `OWLEntityRenderingCacheImpl.rebuild`.
- [ ] Implement C+: mode-aware generic-edit disable guard; Active-Ontology server-side COUNT metrics.
- [ ] Set B revisit trigger (after VPN stabilization / a concrete owlapi-coupling pain).
- [ ] Separately: resolve the remote reverse-proxy gateway timeout for long POSTs (infra, not Step 4).
