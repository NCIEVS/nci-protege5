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

## 5. Round-trip spike — RESOLVED (2026-09-28)

Original open question: *can we reconstruct an arbitrary referencing molecule back to the exact
`OWLAxiom` the in-RAM path manipulates?* **Answered: yes, and more cheaply than feared** — we don't
reconstruct reverse molecules from scratch. Instead:

**Strategy:** a *reverse-index* query returns the set of **named classes that reference E**; each is
then `ensureLoaded` via the already-proven `LazyClassLoader` forward path, after which the existing
`getReferencingAxioms(E)` / `retargetRefs` / `computeAnnotations` work unchanged. The only new code is
the reverse-index query; reconstruction reuses Step 3's proven forward path.

Verified read-only against the full graph (`thes-full-2`, E = C7057 / Gene). All three reference
shapes are cheap **when done right**:

| Shape | Query | Cost |
|---|---|---|
| Children (E is a named parent) | `?c rdfs:subClassOf E` | ~3 ms |
| Role filler (`R some E`) | **bounded reverse skolem BFS** from `?restr owl:someValuesFrom E`, VALUES-anchored `?s ?p ?x` steps up to the named owner | ~3–5 ms/step, ≤4 steps |
| Object-valued association | `VALUES ?p { A1 A2 … } ?c ?p E` (predicate set **bound** from schema) | ~4.7 ms / 43 rows |

The BFS correctly found **both** owner shapes: `C1000002` at depth 1 (plain `subClassOf (R some E)`)
and `C999999` at depth 4 (defined class `≡ … and (R some E)`, walked restriction → list → list →
intersection → named). This works because per-axiom skolemization gives every bnode of one axiom the
same `urn:skolem:<axiomHash>:` prefix (stable reverse walk).

**Pitfalls found (consistent with prior Virtuoso rules):**
- Inverse property paths with alternation + `*` (`^rdf:first/(^rdf:rest)*/… | ^rdfs:subClassOf`) →
  42000 cost-estimator rejection (est 38205 s). Use bounded VALUES-anchored BFS, not paths.
- A **variable predicate** on a bound object (`?c ?p E`) → **32 s**. Bind the association-property set
  via `VALUES` (the client already has it from the schema; `isAssociation` = range `anyURI`).

**Slice 1 shape (now low-risk):** reverse-index queries → `ensureLoaded` the owners → run the existing
`retargetRefs` / `computeAnnotations` unchanged, and fix the `ReferenceReplace` visitor bugs
(all/union/cardinality/hasValue) in the same pass.

## 6. Decisions (locked 2026-09-28)

1. **Parity on non-retargeted references — ignore them.** `getReferencingAxioms(E)` also returns
   `disjointWith` (17 for C7057), object-property `domain`/`range`, and reified `annotatedSource`
   axioms, which the current in-RAM `retargetRefs` ignores (falls through). Slice 1 **replicates that
   exactly** — the reverse-index query only needs to surface the shapes the retarget logic acts on
   (subclass-parent, role filler, object-valued association). No behaviour change.
2. **Keep the wide single commit.** A merge/retire stays one atomic bundle whose touched-set is the
   full reference closure; it correctly blocks concurrent edits to any class in that closure. Intended
   behaviour, not to be re-scoped.
3. **Preserve undo semantics.** Modelers can undo a *pre-merge* / *pre-retire* (their step) before the
   workflow manager finalizes it into a full merge/retire — the "never mind" for a mis-click. This is
   why Slice 1 keeps the edit representation as `OWLOntologyChange` end-to-end: it runs the existing
   `retargetRefs` / `completeRetire`, so the produced changes flow through `applyChanges` →
   `SessionRecorder` and stay reversible on the existing undo/redo stack. The `ensureLoaded` priming of
   owner classes is done with recording suppressed (as today), so materialization never pollutes the
   undo stack. Defer the model-neutral `ChangeRecord` codec (Slice 2) until it can guarantee the same
   reversibility + binaryowl serialization.
