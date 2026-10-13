# Stock-Tab Compatibility Audit — Protégé under the sparse lazy model

Date: 2026-10-13. Companion to `STEP4_COST_BENEFIT.md` (feeds its §4 and the §2c two-mode design).
Scope: the **stock (non-NCI) Protégé tabs/views/actions** that NCI power users occasionally use, and
how each behaves when the active `OWLOntology` is a **sparse on-demand lazy cache** (server/lazy mode).
Read-only audit — no fixes proposed here.

Classification key: **WORKS** (only touches the selected/materialized entity or eager schema) /
**DEGRADES-WRONG** (silently wrong: partial counts / incomplete usage / sparse list) / **NEEDS-ADAPTER**
(generic edit that computes over the sparse view / bypasses lazy priming).

---

## Headline finding

Lazy wiring is **class-hierarchy-only**. In `OWLHierarchyManagerImpl` (`.../model/hierarchy/
OWLHierarchyManagerImpl.java`), `-Dnci.lazyHierarchy` swaps in the Virtuoso provider for the **asserted
class** tree (L61–65) and the **inferred class** tree (L75–79) — and nothing else. The object-property
(L92), data-property (L101), and individuals-by-type (L122) providers are always the stock in-RAM
ones. So under lazy, everything outside the class tree that reads whole-ontology signature/axioms/counts,
or issues generic edits, is unaware of the sparse model. Three failure modes: **wrong numbers**,
**empty/sparse lists & trees**, **edits computed over a sparse view**.

---

## 1. Whole-ontology stats — DEGRADES-WRONG (all)

`AxiomMetricsViewComponent` (`.../ui/metrics/`) and the class/individual/property count metrics source
every number from `getActiveOntology().getAxiomCount()` / `getClassesInSignature()` /
`getXxxInSignature()` / `axioms(type)`. Over the sparse ontology these report only what's been
materialized (e.g. a few hundred classes vs 232k). Every metric in that view is wrong under lazy.
Read-only, no data risk, but misleading.

## 2. Object/Data-property & Individuals tabs — DEGRADES-WRONG (empty/sparse trees)

No lazy provider is wired for them:
- Object-property tree → `OWLObjectPropertyHierarchyProvider.java:44` `getObjectPropertiesInSignature()`
- Data-property tree → `OWLDataPropertyHierarchyProvider.java:44` `getDataPropertiesInSignature()`
- Individuals-by-type → `IndividualsByTypeHierarchyProvider.java:50/78` `getIndividualsInSignature()` /
  `getClassAssertionAxioms(cls)`
- Flat individual list → `OWLIndividualListViewComponent.java:117` `getIndividualsInSignature()`

They render only materialized entities. Partial self-mitigation for NCI: the schema
(properties/datatypes) is eagerly loaded, so property trees may be reasonably populated; individuals
are near-empty (NCI is class-centric). The *default* (non-lazy) class tree
`AssertedClassHierarchyProvider.java:258` also scans `getReferencingAxioms()` — only the
`-Dnci.lazyHierarchy` path is safe, which the NCI launch sets.

## 3. Usage / "used by" views — DEGRADES-WRONG (incomplete)

`UsageByEntityTreeModel.java:74` computes usage from `ont.getReferencingAxioms(entity)` over the sparse
ontology, as do the per-type referencing strategies in `.../model/selection/axioms/`. Same
incompleteness class that Slice 1 fixed inside nci-edit-tab with `primeReferencingClasses` — but the
stock Usage views don't call that primer, so they silently under-report. The lazy loader documents the
exact gap at `LazyClassLoader.java:199`. Views: `OWLClassUsageViewComponent`,
`OWL{ObjectProperty,DataProperty,AnnotationProperty,Individual}UsageViewComponent`.

## 4. Generic create / delete actions — NEEDS-ADAPTER

- **Delete** — `DeleteEntityAction.java:25`, and hierarchy deleters via `OWLEntityDeleter.java:48` →
  `ReferenceFinder.java:44` `getReferencingAxioms(entity)`. Delete decides *what to remove* from the
  sparse ontology → removes only in-RAM references and **leaves the rest dangling in Virtuoso**. This
  is the genuinely dangerous one (data-integrity).
- **Create** — `CreateSubClassHierarchyAction` / `OWLObjectHierarchyCreator.java:43` build `AddAxiom`s
  and call `applyChanges()`. **The writes DO round-trip** (commit → `ChangesetRdf.transform` →
  Virtuoso is UI-agnostic), so a raw create isn't lost — but it bypasses the NCI workflow (code/P-prop
  generation, pref-name uniqueness check against Virtuoso, EVS history). Acceptable *by design* for a
  power user, except the **missing Virtuoso-backed uniqueness check** can create duplicate-named
  entities.

## 5. Stock description frames — WORKS (mostly)

Class/individual/property **description** frames (`.../ui/frame/.../*FrameSection.java`, e.g.
`OWLSubClassAxiomFrameSection.java:42`) refill from the *selected* entity's axioms
(`getSubClassAxiomsForSubClass(sel)`); selecting an entity materializes its molecule, so these render
correctly. Exception: `OWLClassGeneralClassAxiomFrameSection` iterates all `generalClassAxioms()` →
incomplete (DEGRADES-WRONG), but GCIs are rare/absent in NCI.

Also relevant to Option C: `OWLCellRenderer.java:594`
`getActiveOntology().getReferencingAxioms(owlEntity).isEmpty()` runs per paint — under lazy the active
ontology is a cheap sparse HashMap so this is not a perf stall (confirmed), but it's semantically a
sparse (cosmetic) result; it's one of the two Option-C read-path hotspots.

---

## Summary

| Category | Classification | Count | Data risk |
|---|---|---|---|
| Ontology metrics / stats | DEGRADES-WRONG | ~14 metrics | None (cosmetic) |
| Obj/Data-prop & Individuals tabs/lists | DEGRADES-WRONG | ~5 views | None (incomplete display) |
| Usage / "used by" views | DEGRADES-WRONG | 5 views + 4 strategies | None (incomplete display) |
| Generic **delete** | NEEDS-ADAPTER | 4 actions | **Yes — dangling refs in Virtuoso** |
| Generic **create** | NEEDS-ADAPTER (partial) | 3 actions | Low — writes persist; no uniqueness check |
| Stock description frames | WORKS | ~dozens | None |

**Bottom line:** read-only stock views mostly *mislead* but don't corrupt anything. The only
data-integrity risk is **generic delete** (sparse reference computation → orphans), with a secondary
duplicate-name risk on generic create.

**Resolution (adopted — see `STEP4_COST_BENEFIT.md` §2c):** the **two-mode design**. Mode 1 (local
`File → Open`) keeps all stock tabs fully correct in-RAM. Mode 2 (Open from Server) makes stock tabs
**browse-only** (generic editing disabled → delete/create hazards cannot fire) and keeps only the
**Active Ontology** tab editable with **Virtuoso-backed (server-side `COUNT`) metrics** for the
revision-date workflow.
