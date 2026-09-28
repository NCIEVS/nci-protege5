# v2 Scoping — Replacing the OWL-API In-Memory Runtime Model (Step 4)

Status: scoping only, no code changes. Companion to `MIGRATION_PLAN.md` (Step 4) and
`ARCHITECTURE_REVIEW.md`. Date: 2026-09-28.

**Scope reminder (from the plan):** keep OWL API *value types* (`OWLClass`, `OWLAxiom`) at the
UI boundary; only remove the assumption that a single in-RAM `OWLOntology` is *the* queryable
store. `owl-rdf-io` v1 (RDF↔OWL for file I/O) is kept; "v2" is the new internal runtime model +
adapter behind that same load/save seam. v2 has not been started.

---

## 1. Inventory — where the code still speaks the OWL-API runtime model after Step 3

A single `OWLOntology` behind `OWLModelManager.getActiveOntology()` is still the lingua franca,
but it now serves **two separable roles**. Splitting them is the key structural insight for v2.

### 1a. Read / render / browse

**Already abstracted in Step 3 (no v2 work needed):**
- Hierarchy providers (`OWLObjectHierarchyProvider` + `VirtuosoClassHierarchyProvider` /
  `InferredVirtuosoClassHierarchyProvider`).
- Rendering: `VirtuosoEntityRenderer` + `LazyLabelCache` (labels come from Virtuoso, not the ontology).
- `OWLEntityFinder` (interface-abstracted, cache-backed).

**Still OWL-API-native and deep:**
- **~50 frame sections** — each `refill(OWLOntology ont)` calls `ont.getXxxAxioms(entity)`
  (`getSubClassAxiomsForSubClass`, `getAnnotationAssertionAxioms`, `getEquivalentClassesAxioms`, …).
  This is the bulk of read-path axiom consumption.
- **`OWLCellRenderer` icon check** — `getActiveOntology().getAxioms(entity).isEmpty()` **per paint**.
- **`OWLEntityRenderingCacheImpl.rebuild()`** — iterates the ontology signature.

**Why the read side is largely already handled:** frames work today only because
`LazyClassLoader.materialise()` writes the fetched RDF-molecule axioms **into the (sparse) active
ontology** on selection. The active ontology is therefore already a *lazy per-entity cache*, not a
whole-ontology-in-RAM. The read side needs little new-model work — mainly redirect the two
per-paint / full-signature hotspots to an index-backed, cached source.

### 1b. Edit / commit / change-event — uniformly OWL-API-native and deep

- Edit ops (`NCIEditTab` merge/split/retire, `RoleReplacer`, `ParentRemover`) build
  `List<OWLOntologyChange>` (`AddAxiom` / `RemoveAxiom`) → `applyChanges()`.
- `SessionRecorder` undo/redo = `Stack<List<OWLOntologyChange>>`.
- Commit bundle serializes `List<OWLOntologyChange>` via binaryowl **end-to-end** to the server.
- ~20 change listeners consume `List<OWLOntologyChange>` and inspect `isAddAxiom` / `getAxiom` to
  invalidate caches / hierarchy / index.
- **Clean seam already present:** `ChangesetRdf.transform(List<OWLOntologyChange>) → RDF triples` at
  the server boundary — the natural model-swap isolation point (Virtuoso downstream is unaffected).

### Coupling summary

| Surface | Coupling | v2 disposition |
|---|---|---|
| Hierarchy providers, entity renderer, entity finder | shallow (done) | none |
| Frame sections `refill(OWLOntology)` | deep | works via lazy materialise; leave, fix hotspots |
| `OWLCellRenderer` icon `getAxioms` per paint | deep (per-paint) | cache `hasAxioms(entity)` from index |
| `OWLEntityRenderingCacheImpl.rebuild` | medium | prime from index / lazy-populate |
| `getActiveOntology()` as lingua franca | pervasive | keep as lazy read cache for now |
| Edit ops → `List<OWLOntologyChange>` → `applyChanges` | deep | `ChangeRecord` seam (Slice 2) |
| `SessionRecorder` undo/redo stacks | deep | `ChangeRecord` (reversible) |
| Commit serialization (binaryowl) | deep | `ChangeRecord` codec (later) |
| `ChangesetRdf.transform` | **shallow — swap point** | generalize input to `ChangeRecord` |
| Reference retargeting (merge/retire) | **deep + correctness bug** | **Slice 1: Virtuoso query** |

---

## 2. Deep-dive: merge / retire semantics, blast radius, and the lazy correctness bug

This is the highest-priority finding: the reference-retargeting logic is **already incorrect under
the lazy model**, and it drives the server concurrency blast radius.

### What merge / retire actually touch

Both operations restructure not just the source class but **every class that references it**:

- **Reference discovery (two paths, both over the in-RAM ontology):**
  - `ont.getReferencingAxioms(entity)` — subclass / equivalent-class axioms where the entity is a
    named parent **or a role filler** inside an anonymous `R some X` / `R only X` expression.
  - a full `ont.getAxioms(AxiomType.ANNOTATION_ASSERTION)` scan — to catch **object-valued
    associations** whose value IRI equals the entity (NCI associations like role/associations
    pointing *at* the concept).
- **Actions per referencing class:**
  - *Merge* (`ReferenceReplace.retargetRefs`, `NCIEditTab.finalizeMerge`): remove the old axiom, add
    a retargeted one (parent → target; role filler → target; association value → target).
  - *Retire* (`ReferenceFinder.computeAnnotations`, `NCIEditTab.completeRetire`): record provenance
    on the retired class — the `DEP_CHILD` / `DEP_IN_ROLE` / `DEP_IN_ASSOC` / `DEP_ASSOC`
    annotations (the "OLD_SOURCE"-style records, e.g. `R|some|Filler`) — then remove the logical link
    and re-parent the retired class under the retire root with deprecation + status annotations.

So the **blast radius = the full reference closure of the source**: its children, defined classes
whose genus/role filler is the source, primitive classes with `subClassOf (R some source)`, and any
class with an object-valued association pointing at the source. Every one of those gets an axiom
modified and/or a provenance annotation added.

### The lazy correctness bug (confirmed)

Both `getReferencingAxioms` and the annotation-assertion scan run over the **active ontology**, which
under the lazy model is **sparse** (only browsed/materialised classes are present). On the full
Thesaurus (~200K classes), a merge/retire will **silently miss every referencing class that was not
browsed**, producing:
- **dangling references** — role fillers and associations still pointing at the merged-away / retired
  concept after commit (a broken Virtuoso graph);
- **incomplete provenance** — missing `DEP_IN_ROLE` / `DEP_IN_ASSOC` records for the missed refs.

This is a correctness regression, not merely a perf/refactor concern.

### Concurrency connection (server per-class commit gate)

The per-class commit gate (Decision #2) derives a commit's **touched-entity set** from the subjects
of its add/remove axioms. Because retarget/provenance edits land on the *referencing* classes, a
correct merge/retire's touched-set is the **whole reference closure** — a legitimately wide commit
that should block concurrent edits to any class being restructured. But under the sparse scan the
**missed classes are also absent from the touched-set**, so the gate cannot protect what was never
found. The same bug breaks correctness *and* concurrency safety. Fixing the reference query at the
source fixes all three: retarget completeness, provenance completeness, and gate completeness.

### Pre-existing (non-lazy) bugs to fix while we are here

In `ReferenceReplace` the class-expression visitor is partly wrong for object-property fillers:
- `OWLObjectAllValuesFrom` is rebuilt as `someValuesFrom` (semantic change) and lacks an `else`, so a
  non-matching filler leaves stale shared `newExpression` state.
- `OWLObjectUnionOf` is rebuilt as `intersectionOf` (semantic change).
- `hasValue`, cardinalities, `oneOf`, `complementOf`, and all data-range visitors are empty stubs, so
  a source appearing inside those shapes is mis-retargeted.

NCI is `someValuesFrom`-dominant, so these rarely fire in practice, but they are landmines that the
Virtuoso-backed rewrite should resolve (reconstruct the true expression from triples, retarget by
structure).

---

## 3. v2 model shape + adapter boundary

Decouple the two roles the single `OWLOntology` serves:

- **Read model:** leave the `LazyClassLoader` → active-ontology bridge (it already provides lazy
  reads). Only fix the two hotspots — make the icon `hasAxioms(entity)` check and the
  rendering-cache priming come from a cached, index/Virtuoso-backed source instead of a per-paint /
  full-signature ontology scan. No new read-model type needed yet.
- **Change model:** introduce a model-neutral, **reversible + serializable `ChangeRecord`** as the
  lingua franca for edit ops → `SessionRecorder` → commit serialization → listener dispatch →
  `ChangesetRdf`. Ship it with a **`ChangeRecord ↔ OWLOntologyChange` adapter** so both
  representations coexist and migration is incremental (listeners keep an `OWLOntologyChange` view via
  the adapter until each is ported).
- **Core reusable primitive:** "query Virtuoso for the axioms **about / referencing** entity E →
  reconstruct `OWLAxiom`s via owl-rdf-io (RDF→OWL, already exists)." Both the change side (reference
  retargeting) and the eventual read-model replacement build on this.

---

## 4. First vertical slice — recommendation

**Slice 1: move merge/retire reference discovery off the in-RAM scan onto a Virtuoso
"who references E" query, reconstructing the affected axioms via owl-rdf-io.**

Rationale:
- Fixes the deepest correctness coupling on the edit path **and a confirmed latent bug** under the
  lazy model (sparse scan → missed refs) — immediate user-facing value, plus it repairs the commit
  gate's touched-set completeness.
- Contained: `ReferenceReplace` / `ReferenceFinder` + `finalizeMerge` / `completeRetire`, driven by
  one query. Independently testable end-to-end (merge/retire a class with role fillers and object
  associations from *unbrowsed* classes; assert every reference retargeted / recorded).
- Builds the **query-Virtuoso → reconstruct-OWLAxioms** primitive that all later v2 work reuses.
- Also the right place to fix the `ReferenceReplace` visitor bugs (all/union/cardinality/hasValue).

Follow-on slices:
- **Slice 2:** the `ChangeRecord` seam at `ChangesetRdf` (+ `ChangeRecord ↔ OWLOntologyChange`
  adapter) — model-neutral change lingua franca, no wire/UI churn.
- **Slice 3:** read-model hotspot caching (`OWLCellRenderer` icon `hasAxioms`, rendering-cache
  priming) from an index.

---

## 5. Open questions for the team

1. Reference retargeting needs the *reconstructed axioms* to edit, not just IRIs — confirm owl-rdf-io
   can round-trip an arbitrary referencing molecule (role restrictions, reified associations) back to
   the exact `OWLAxiom` the current in-RAM path manipulates.
2. Should the wide merge/retire commit stay a single atomic bundle (large touched-set, blocks
   concurrent edits to the closure) or be re-scoped? Current behaviour is correct-but-wide; document
   it as intended.
3. Undo/redo of a Virtuoso-sourced retarget: the reconstructed reverse changes must be reversible and
   serializable through binaryowl until the `ChangeRecord` codec lands.
