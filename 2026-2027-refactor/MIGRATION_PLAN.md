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

### Step 0 — Establish the refactor branch from the stable base

The whole build is tag-driven: `scripts/build.sh $TAG $TARGET` clones each core repo from `github.com/$TARGET/…` and runs `git checkout $TAG`. A branch name is a valid ref for `git checkout` (identical to a tag for build purposes — it just materializes that commit's tree), so the build can run off a **branch** exactly as it runs off a tag.

Baseline: the latest tag **`4.4.1-dev3`** is stable and present in all five core repos — this is the rollback point (no re-tagging needed). Branch state of the *local working copies* (owlapi on `5.1.6`, binaryowl detached, others `master`) is irrelevant: the build uses the tag/branch ref, not the working-copy branch.

Strategy: one branch name, **`2026-2027-refactor`**, in every core repo, cut from `4.4.1-dev3`. Because `build.sh` applies a single ref to *all* core repos and is `#!/bin/sh -e` (aborts on first failed checkout), the branch must exist in **all five** — even the ones not yet changed. Empty branches that point at the tag commit cost nothing, and `build.sh 2026-2027-refactor NCIEVS` then resolves uniformly. Commits land only where the refactor actually touches code.

Plugins stay independent: `plugins-build.sh` has the same one-ref-for-all loop, so it keeps using the plugins' latest tags. Branch a plugin as `2026-2027-refactor` only when the refactor reaches it (`nci-edit-tab`, `lucene-search-tab` in step 3), and build/drop that one jar individually.

Done (2026-09-09): created `2026-2027-refactor` from `4.4.1-dev3` in all five core repos, each pointing at the exact tag commit:

| Repo | `2026-2027-refactor` → | tag commit |
|---|---|---|
| `owlapi` | `bfe7f2bd61` | = `4.4.1-dev3` |
| `binaryowl` | `b4ec67af46` | = `4.4.1-dev3` |
| `xmlcatalog` | `d579f2be90` | = `4.4.1-dev3` |
| `metaproject` | `92d4e0b991` | = `4.4.1-dev3` |
| `protege` | `a110f8df4f` | = `4.4.1-dev3` |

Pending: branches are **local only** — push each to `origin` (NCIEVS) before `build.sh 2026-2027-refactor NCIEVS` can consume them (`git push origin 2026-2027-refactor` per repo; load the SSH key via `ssh-add` first to avoid a per-repo passphrase prompt).

Pushed (2026-09-09): all five `2026-2027-refactor` branches pushed to `origin` (NCIEVS). `build.sh 2026-2027-refactor NCIEVS` now resolves uniformly and builds the `4.4.1-dev3` tree until commits land on the branches.

### Step 1 — Carve out the OWL-RDF I/O layer as a new standalone project

This is the single part of `owlapi` that is kept, and it already sits behind a clean I/O boundary. Making it standalone is the **seam** the rest of the strangler hangs on. See the dedicated section below.

Research finding (2026-09-09): the entire OWL⇄RDF/XML machinery lives in **one owlapi module, `owlapi-parsers`** (`org.semanticweb.owlapi.rdf.rdfxml.parser` / `.renderer`), on top of `owlapi-api` (model) and `owlapi-impl` (in-memory `OWLOntologyImpl`/`OWLDataFactoryImpl`). There are **no NCI/EVS fork customizations** in that code — it is clean upstream. `rio` (15 rdf4j artifacts), `oboformat`, `tools`, `compatibility`, `distribution` are **not needed** for RDF/XML load+save. protégé's `OntologyLoader` uses `OWLManager.createOWLOntologyManager()` + `loadOntologyFromOntologyDocument(...)`; `OntologySaver` uses `ontology.saveOntology(OWLDocumentFormat, ...)` — that is the boundary the new project satisfies.

Done (2026-09-09) — v1 scaffolded at `projs/owl-rdf-io` (`gov.nih.nci:owl-rdf-io:0.1.0-SNAPSHOT`, Java 8):
- `OwlRdfIO` facade — the whole public surface: `load(InputStream)→OWLOntology`, `save(OWLOntology, OutputStream)` / `saveToBytes(...)` in RDF/XML.
- Depends on `owlapi-apibinding:5.1.6-SNAPSHOT` (v1 choice: `OWLManager` wires parsers/storers reliably, exactly like `OntologyLoader`). To be trimmed in v1b.
- `RoundTripTest` (milestone-1 acceptance): parse fixture → render RDF/XML → reparse → assert axiom set preserved. **Passing** — axioms preserved exactly on `Thesaurus-test-small.owl` (2.9 MB, 754 classes + 263 properties + 24 datatype enums). First concrete proof the OWL 2 ⇄ RDF mapping is non-lossy on real NCIt content.
- Build: `JAVA_HOME=…/zulu-8.jdk … mvn -f projs/owl-rdf-io/pom.xml clean test` → BUILD SUCCESS.

Next in this step:
- **v1b (done, 2026-09-09):** dependency dropped from `owlapi-apibinding` to direct `owlapi-api` + `owlapi-impl` + `owlapi-parsers`; the `rio`/rdf4j, `oboformat`, `tools` footprint is gone. `OwlRdfIO` now bootstraps the `OWLOntologyManager` by hand (`OWLOntologyManagerImpl` + `OWLDataFactoryImpl` + `OWLOntologyFactoryImpl` + `RDFXMLParserFactory` + `RDFXMLStorerFactory`) — pattern taken from owlapi's own tests. Round-trip still passing.
- **Round-trip coverage widened (done):** `BinaryOwlRoundTripTest` (RDF/XML load → binaryowl write via `OWLOntologyWrapper` → read via `BinaryOWLOntologyBuildingHandler` → axioms preserved) passes; `binaryowl:2.0.3-SNAPSHOT` is a test-only dep with its `owlapi-distribution` uber jar excluded (api/impl/parsers supply the classes). `FullThesaurusRoundTripTest` added — gated on `-DfullThesaurus=<path>`, skipped by default, heap via surefire `argLine` (`-Dowlrdf.test.argLine`). Suite: 3 tests, 1 skipped, BUILD SUCCESS.
- **Repo + branch + build wiring (done):** `git init` at `projs/owl-rdf-io`, committed on `main`, branch `2026-2027-refactor` created (both at `9f10f9e`). `build.sh` now clones + `mvn install`s `owl-rdf-io` **after `binaryowl`** (it depends on owlapi, and test-compiles against binaryowl) and before `xmlcatalog`.

Pending to make `build.sh 2026-2027-refactor NCIEVS` consume it:
- Create the `NCIEVS/owl-rdf-io` GitHub repo and push `main` + `2026-2027-refactor` (needs a human — I don't create remote repos). Until then the new `build.sh` clone step will fail, exactly like any other core repo whose branch isn't pushed.

v1b tail (2026-09-09):
- **binaryowl decoupled from the owlapi uber jar (done).** On binaryowl's `2026-2027-refactor` branch (commit `956a5b1`): its pom drops `owlapi-distribution` for explicit `owlapi-api` + `owlapi-impl` + `owlapi-parsers` + `owlapi-rio`, with `apibinding` demoted to test scope. `owlapi-rio` is retained because `BinaryOWLOntologyDocumentParserFactory` imports a rio class (`BinaryRDFDocumentFormatFactory`) — the one real rio coupling; everything else binaryowl needs is in api/impl/parsers. The single `OWLManager.createOWLOntologyManager()` on binaryowl's read path was replaced with the same manual `OWLOntologyManagerImpl` bootstrap `owl-rdf-io` uses, so binaryowl's main code no longer needs `apibinding`. Verified: binaryowl compiles and installs; `owl-rdf-io`'s `BinaryOwlRoundTripTest` stays green against the decoupled jar. binaryowl's 4 long-standing test failures are **pre-existing** (identical on pristine `4.4.1-dev3` — hamcrest version clash + owlapi IRI-absolutization/lang-tag drift) and are skipped by `build.sh`, so not a regression.
- **Physical module move DEFERRED to step 4 (was premature).** Moving `owlapi` `api`+`impl`+`parsers` into `owl-rdf-io` now is not yet worthwhile: `protege-editor-owl` still depends on `owlapi-distribution`/`apibinding`, so `owlapi` cannot be dropped until protégé migrates (steps 3–4). Doing the move now would only create a fragile `owl-rdf-io ↔ owlapi` build-order coupling for no near-term benefit. Absorb the three modules (and repoint `binaryowl` at `owl-rdf-io`) as part of the owlapi deletion in **step 4**.

### Step 2 — Build the Virtuoso-backed model + commit-coordination service

Against the seam from step 1, following the decisions in `ARCHITECTURE_REVIEW.md` (slim commit-coordination service; workflow state as graph data; the append-only changeset log as the provenance spine with an OWL↔RDF transform driving Virtuoso; materialized logical projection for `nci-curator`). Can proceed in parallel with the `sparql-query-plugin/virtuoso` work.

**Sequencing decision — keep the coarse-but-proven concurrency controls in v1, revisit granularity later.** The current model already works and is what `revision-history` is built around, so v1 keeps it intact and only adds the Virtuoso write step:
- **Commit gate becomes per-class** (`ARCHITECTURE_REVIEW.md` Decision #2). Keep the commit path serialized (`ConflictDetectionFilter`'s `synchronized` section) and the client-side `SimpleConflictDetector` review, but change the accept/reject predicate: a commit carries `baseRevision` + its touched-class set, and the server rejects only if a touched class changed in `(baseRevision, head]` (via a per-class last-changed-revision index over the changeset log), returning the conflicting classes. This lets modelers editing disjoint areas commit concurrently instead of forcing a full re-sync, while the serialized section still applies each accepted changeset to Virtuoso in revision order.
- Keep **squash as a server-pause operation** (`HTTPServer.isPaused` + `HTTPChangeService.squashHistory`): pause, compact log → new snapshot baseline, fresh empty changeset, back up `evs_history`/`concept_history`. Only the "current state" source changes (Virtuoso instead of the in-RAM snapshot); the pause/compact/baseline mechanics stay.
- The **new** work in v1 is narrow: after a changeset is accepted and appended to the log, transform its OWL add/removes to RDF and apply them to Virtuoso; and feed the same changeset stream to clients for Lucene + editor refresh (replacing the in-RAM-ontology change events).

Revisit finer-grained concurrency (per-concept refresh feed, non-pausing squash) only after the coarse path is proven end-to-end.

Started (2026-09-10) — the OWL↔RDF changeset transform (the one net-new v1 component). New module `projs/owl-virtuoso` (`gov.nih.nci:owl-virtuoso:0.1.0-SNAPSHOT`, depends on `owl-rdf-io` so that module stays pure; rdf4j/Virtuoso wiring added here later):
- `ChangesetRdf.axiomToTriples` / `transform` renders OWL axioms to RDF triples via owlapi's `RDFTranslator`, producing `INSERT`/`DELETE` triple sets for a changeset.
- **Blank-node problem solved with per-axiom skolemization.** owlapi assigns blank-node ids from a counter, so the same anonymous structure (restriction, `owl:Axiom` reification, `intersectionOf` list) renders to a different `_:` id each pass — a `DELETE` would never match a prior `INSERT`. Fix: render each axiom in isolation with a fresh counter and rewrite each blank node to `urn:skolem:{sha256(axiom)}:{localId}`. The axiom hash scopes the skolem, so identical structures on different axioms don't collide and the same axiom's add/remove render identically.
- Tests (5, green) prove the invariant on the real bnode cases: a `someValuesFrom` restriction and a reified `owl:Axiom` synonym qualifier render deterministically; add-then-remove cancels; distinct subjects get distinct skolems; named `subClassOf` stays a single bnode-free triple.
- Repo `git init`ed, branch `2026-2027-refactor` (`f0d1015`). Not yet in `build.sh` (WIP, not yet consumed).

Done (2026-09-10) — the RDF4J SPARQL-Update write path (`owl-virtuoso.SparqlStore`). Applies an `RdfChangeSet` as one SPARQL Update (`DELETE DATA` then `INSERT DATA`) into the project named graph via RDF4J `SPARQLRepository` (the same client the server's `RemoteSparqlReasoner` uses). Endpoint + graph are server-sourced (`TRIPLESTORE` config + project `namespace/name`), never client preferences. Verified end-to-end: an in-memory RDF4J round-trip (CI-safe) and a gated `-Dvirtuoso.endpoint` integration test **green against the real localhost Virtuoso (11.4M triples)** — the skolemized `DELETE` matches the earlier `INSERT` and the graph empties. Security: the dev Virtuoso allows anonymous updates, so before go-live the client-facing endpoint must be read-only with updates behind an authenticated server-only endpoint (see `ARCHITECTURE_REVIEW.md` “Write-path security”).

Still to do for the v1 write path: hook `SparqlStore.apply` into the server's `synchronized` commit section (right after the changeset is appended to the log), add the last-applied-revision marker + replay-on-restart recovery (Decision #1), and fold in the EVS descriptor (Decision #4).

Done (2026-09-10, on the protege `2026-2027-refactor` branch):
- **Commit hook** (`96f0a786`): `HTTPChangeService.submitCommitBundle` now calls the new write path after `serverLayer.commit` returns (log already appended), passing the committed head revision. Adds the `gov.nih.nci:owl-virtuoso` dependency; `build.sh` builds `owl-virtuoso` after `owl-rdf-io`.
- **Last-applied-revision marker + replay** (`3c4ac961`): `SparqlStore.apply(changeset, revision)` writes a per-graph revision marker as the final op of the same SPARQL Update; `writeTripleStore` is now **self-healing** — it reads the marker and replays `marker+1..head` (via `changeService.getChanges`, exclusive of `from`) rather than only the current bundle, so a restart/outage catches up on the next commit. Triple-store failures are logged, never fail the commit (log is authoritative). Verified in `owl-virtuoso` (in-memory + real Virtuoso) and compiles in `protege-editor-owl`.
- **Dead-code removal** (`6ba49684`): deleted the lossy, injection-prone `ConvertToRdf` / `buildCompQuery` / `buildAnonParentQuery` and their fields/imports.

Remaining: **fold in the EVS descriptor (Decision #4)** — this is a cross-repo change (client `nci-edit-tab`/`LocalHttpClient` + the commit wire format + server), not a server-only edit: today the client records EVS via a separate `putEVSHistory` call after commit, so folding it into the commit requires the client to send the EVS descriptor with the bundle and the server to record it inside `submitCommitBundle`. Best done alongside the commit-transport rewrite (finding #5, dropping Java serialization).

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
