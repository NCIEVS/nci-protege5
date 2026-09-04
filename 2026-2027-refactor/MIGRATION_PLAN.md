# Migration Sequencing & Game Plan

Companion to [`ARCHITECTURE_REVIEW.md`](./ARCHITECTURE_REVIEW.md). That document says *what* the target architecture is and *why* the OWL→RDF write path, the OWL-API runtime model, and the revision-based concurrency model are the hard problems. This document says *in what order* to do the work, and where the earlier dependency-cleanup findings fit.

## The core decision: refactor first, let most of the cleanup fall out

An earlier review found many redundant/inconsistent dependencies across the repos. The instinct to clean those up first is natural but wrong here, because **most of those redundancies live in the code the refactor deletes** — the OWL API runtime model and the bulk of the `owlapi` modules.

Rule of thumb: **deletion is the ultimate dependency cleanup.** Cleaning dependencies in doomed code is paid twice and destabilizes the one asset you currently have — a working, tagged build.

Split cleanup work by the *fate* of the code:

| Fate | Repos / areas | Cleanup policy |
|---|---|---|
| **Survives** | `metaproject`, `binaryowl`, `xmlcatalog`, the OWL-RDF parsers/storers being kept, plugins' non-OWL parts, build scripts | Worth doing; some is prerequisite |
| **Dies** | `owlapi/api`, `owlapi/impl`, OWL-API-as-runtime-model usage in the protégé model layer | Skip entirely — delete later |

The redundant-dependency work scoped earlier **mostly evaporates at step 5** below, so doing it up front would be paying twice.

## Strategy: a strangler-fig around `owlapi`

Sequence the work by *what survives*, not by *what is messy*. Wrap the doomed OWL-API layer, stand up its replacement behind a stable seam, then delete.

### Step 0 — Fix branch footguns and freeze a baseline

The whole build is tag-driven (`scripts/build.sh` checks out `$TAG` for each repo; `scripts/tagger.sh` tags them together), so reproducibility depends on clean branch state.

Current branch state (observed 2026-09-04):

| Repo | Branch | Note |
|---|---|---|
| `owlapi` | `5.1.6` | non-`master` release branch |
| `binaryowl` | **detached HEAD** | fix before tagging — reproducibility footgun |
| `sparql-query-plugin` | `virtuoso` | migration beachhead already exists |
| `xmlcatalog`, `metaproject`, `protege`, `nci-edit-tab`, `lucene-search-tab`, `evs-history`, `revision-history` | `master` | — |

Actions:
- Get `binaryowl` (and `owlapi` if desired) onto clean named branches.
- Tag the current working state with `tagger.sh` and confirm `build.sh` reproduces it. This is the rollback point for the entire migration.

### Step 1 — Carve out the OWL-RDF I/O layer as a new standalone project

This is the single part of `owlapi` that is kept, and it already sits behind a clean I/O boundary. Making it standalone is the **seam** the rest of the strangler hangs on. See the dedicated section below.

### Step 2 — Build the Virtuoso-backed model + commit-coordination service

Against the seam from step 1, following the decisions in `ARCHITECTURE_REVIEW.md` (slim commit-coordination service, workflow state as graph data, entity-scoped optimistic concurrency, materialized logical projection for `nci-curator`). Can proceed in parallel with the `sparql-query-plugin/virtuoso` work.

### Step 3 — Migrate the hard consumers

Port hierarchy providers and `lucene-search-tab` onto the new model. These encode the "whole ontology in RAM" assumption most deeply and will fight a lazy model hardest, so they gate the schedule.

### Step 4 — Delete the OWL API runtime model and unused `owlapi` modules

Removing the OWL-API-as-runtime-model usage and the dead `owlapi` modules **resolves the bulk of the redundant-dependency findings for free.**

### Step 5 — Final dependency-hygiene pass

Only now, on the much smaller surviving surface: dedupe versions, consolidate transitive deps, modernize where safe.

## The standalone OWL-RDF project (milestone 1)

**Decision: yes.** Extract the OWL-RDF read/write layer into its own project. It is both the strangler seam and the place the hardest problem — the non-lossy OWL 2 ↔ RDF mapping — gets solved in isolation.

### Why

- **It is exactly the keep-set**, already behind a clean boundary: `OntologyLoader` / `OntologySaver` plus the vendored `owlapi/parsers`, `owlapi/rio`, `owlapi/oboformat`, and `binaryowl`.
- **It localizes the dependency mess** — pin/modernize deps in one small module you own instead of untangling the `owlapi` monorepo.
- **It is independently testable, and the fixture now exists** (see below). First milestone = a round-trip test that directly validates the #1 blocker from the architecture review.
- **It is independent of the Virtuoso work**, so it proceeds in parallel.

### Scoping cautions

- **v1 still uses OWL API model types** (`OWLOntology`) because the parsers produce them. v1 = "parsers/storers repackaged, dependency-cleaned, round-trip-tested." Do **not** sever from `owlapi-api` on day one — v2 introduces the new internal model plus an adapter behind the same boundary.
- **Public contract is deliberately tiny:** `load(bytes) → model` and `save(model) → bytes`. Everything else in `owlapi` stays on the delete list.

### First milestone acceptance test

Round-trip on the small fixture:

```
parse(Thesaurus-test-small.owl) → model → serialize → reparse → diff == ∅
```

A clean round-trip is the concrete proof that the OWL 2 ↔ RDF mapping is non-lossy — the prerequisite the architecture review calls out as blocking everything downstream.

## Test fixture: `Thesaurus-test-small.owl`

Generated by [`make_test_ontology.py`](./make_test_ontology.py) from the full 760 MB `Thesaurus-251229-25.12e.owl`. Streaming two-pass, low memory — never loads the graph into an object model.

Contents: ontology header + **all** annotation/object/datatype property declarations, **all `rdfs:Datatype` enumerations** (the `owl:oneOf` value sets the editor enforces on complex-property qualifiers), top-level root classes, and one level of named subclasses beneath each root. The output is **referentially self-contained** — no dangling references, so the top level holds only real roots.

| Metric | Full ontology | Test fixture |
|---|---|---|
| Size | 760 MB | 2.8 MB |
| Classes | 208,530 | 754 (19 roots + 735 one-level children) |
| Object properties | 97 | 97 (all) |
| Annotation properties | 166 | 166 (all) |
| Datatype enumerations (`rdfs:Datatype`) | 24 | 24 (all) |
| Dangling class references | — | 0 |

The 19 roots are the canonical NCI Thesaurus upper-level kinds (Activity; Anatomic Structure, System, or Substance; Biological Process; Disease, Disorder or Finding; Gene; Gene Product; Organism; Retired Concept; …).

**Editor-enforced qualifier values.** When a class is created, EditTab requires its FULL_SYN (`P90`) to carry `term_type` (`P383`) = `PT` and `term_source` (`P384`) = `NCI`. Those allowed values (and the create/edit defaults) are defined in the ontology as `rdfs:Datatype` enumerations — e.g. `term-source-enum` (`owl:oneOf` = ACC, ANSI, … NCI, …; `default_on_create_class` = NCI) and `term-group-enum` (… PT, SY, …; default = PT). These are referenced as the `rdfs:range` of the qualifier properties and drive the columns/validation in the complex-property tables (`P90`, `P97`, `P211`, `P325`, `P375`). They must be kept for the fixture to be editable under the `byCode` project, so the extractor keeps all `rdfs:Datatype` blocks unconditionally.

Parameters: `--levels N` (go deeper than one level), `--max-children-per-root M` (cap breadth per root).

Selection rules:
- A **named superclass** = `<rdfs:subClassOf rdf:resource="IRI"/>` **or** the genus of a defined class (a `<rdf:Description rdf:about="IRI"/>` member of an `owl:equivalentClass` / `intersectionOf`), where `IRI != owl:Thing`.
- **root** = declared class with no named superclass that is itself used as a named superclass by ≥1 other class. Capturing the equivalentClass genus is what keeps fully-defined classes (e.g. `BCOR Gene`) from being mistaken for roots.
- **level-K children** = classes whose named superclass is in level K−1.
- **kept classes** = roots ∪ level-1 (at default `--levels 1`).

Referential integrity:
- Every reference from a kept block that points **outside** the kept slice is pruned (secondary parents, role fillers in `equivalentClass`/restrictions, object-valued associations, object-property `domain`/`range`). This is what removes the bare code-named orphan classes.
- Because pruning removes `equivalentClass` genus edges, an explicit `rdfs:subClassOf` to each kept named super is **injected**, so defined classes stay parented instead of orphaning to the top level.

Trade-off: pruning drops the logical **role definitions** on level-1 defined classes (their fillers live deeper in the hierarchy, outside the slice). For a small smoke-test fixture this is acceptable; if definitions must be preserved, a future `--closure` option could instead pull in referenced fillers and their parent chains (at the cost of size). The real acceptance test remains loading the fixture in Protégé / the OWL API.

Known remaining gap: the `byCode` workflow roots `premerged_root` (`NHC50000`) and `preretired_root` (`NHC50001`) exist in the full ontology but fall outside the roots-∪-level-1 slice, so they are not yet in the fixture. They are needed only for the merge/retire approval workflows (not for basic class creation). If those workflows are to be exercised, the extractor should force-include the config-referenced special classes (`NHC50000`, `NHC50001`, retired roots `C28428`/`C83485`) regardless of the slice.

## Open items carried from the architecture review

Unchanged and still pending (see `ARCHITECTURE_REVIEW.md` → "Open decisions carried forward"):

1. Transaction ↔ RDF atomicity against Virtuoso (highest risk).
2. Versioning unit: concept subgraph vs. named-graph-per-concept vs. global.
3. Provenance model replacing `ChangeHistory`.
4. EVS-history trigger point moving to the service accept-commit callback.
