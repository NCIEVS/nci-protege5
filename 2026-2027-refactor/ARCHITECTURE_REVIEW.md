# Architecture Review: Migrating Clients to a Direct Virtuoso RDF Store

## Goal being evaluated

Move away from the current client-server design (clients load a full serialized OWL snapshot into RAM and sync with the protege-server via revision-numbered changesets) toward one where:

- Clients interact **directly** with the RDF Virtuoso triple store, so the entire ontology no longer needs to be in RAM at once.
- The **OWL API layer is removed**, while **keeping the OWL format for input/output serialization**.
- `nci-curator` (a classifier that needs the whole ontology in memory) is addressed separately, later.

## Current architecture, in one picture

```mermaid
flowchart LR
    subgraph Client["Protégé Client (full ontology in RAM)"]
      MM[OWLModelManager<br/>wraps OWLOntologyManager]
      SNAP[(binaryowl<br/>history-snapshot)]
      MM --- SNAP
    end
    Client -->|"HTTP /nci_protege<br/>Java-serialized CommitBundle"| Server
    subgraph Server["protege-server (Undertow)"]
      FILTERS[AccessControl → ConflictDetection → ChangeManagement]
      HIST[(change-history file<br/>SOURCE OF TRUTH)]
      FILTERS --- HIST
    end
    Server -->|"ConvertToRdf (LOSSY)<br/>RDF4J SPARQLRepository"| VIRT[(Virtuoso)]
    PLUGIN[sparql-query-plugin<br/>RemoteSparqlReasoner] -->|read-only SPARQL| VIRT
```

The key thing to internalize: **Virtuoso is currently a lossy, one-way, read-only projection.** The authoritative store is the binaryowl snapshot + change-history file on the server. The proposed design inverts this — Virtuoso becomes the read/write source of truth — and that inversion is where almost all the friction lives.

## What sticks out

### 1. The OWL→RDF write path is lossy and one-way — this is the #1 blocker

`ConvertToRdf` in `protege/protege-editor-owl/src/main/java/org/protege/editor/owl/server/http/handlers/HTTPChangeService.java` (around lines 184–280) is an `OWLAxiomVisitor` that handles exactly **three** axiom shapes:

- `OWLDeclarationAxiom` → only `rdf:type owl:Class` (object/data/annotation properties, individuals, datatypes are dropped)
- `OWLAnnotationAssertionAxiom` → only literal values (IRI-valued annotations dropped)
- `OWLSubClassOfAxiom` → named superclass, or a single `ObjectSomeValuesFrom` with named property + named filler

Everything else — equivalent classes, disjointness, object/data property axioms, nested class expressions, imports, datatypes, language tags, individuals — is **silently discarded**. It also assumes a single `ncit:` namespace and derives predicates from `IRI.getShortForm()` (`buildCompQuery`), so it cannot represent a general OWL ontology.

This is fine for its actual job (feeding ad-hoc NCIt queries), but it means the RDF in Virtuoso **cannot round-trip back to OWL**. For the target design you need a complete, standards-based OWL-to-RDF mapping (the W3C OWL 2 RDF mapping) so that what a client writes is exactly what any client can read back. That is a full rewrite of this component, not an extension.

### 2. OWL API is the runtime data model, not an I/O layer — "remove the OWL API layer" is the largest item by far

Quantified: ~**2,900** `org.semanticweb.owlapi.model` imports across ~1,000 files. The entire contract of `protege/protege-editor-owl/src/main/java/org/protege/editor/owl/model/OWLModelManager.java` is OWL API types (`OWLOntology`, `OWLOntologyManager`, `OWLDataFactory`, `OWLAxiom`, `OWLReasoner`, `OWLOntologyChange`). Every UI panel, hierarchy provider, frame section, renderer, and plugin (`nci-edit-tab`, `lucene-search-tab`, `revision-history`) consumes those objects directly.

Only a thin sliver is genuinely I/O-only and cleanly separable — this is the part to *keep*:

- `protege/protege-editor-owl/src/main/java/org/protege/editor/owl/model/io/OntologySaver.java` / `OntologyLoader.java`
- the format implementations vendored in `owlapi/parsers`, `owlapi/rio`, `owlapi/oboformat`, plus `binaryowl`

So "keep OWL format for I/O, drop the OWL API layer" really means: **introduce a new abstraction to replace `OWLModelManager`/`OWLOntology` as the in-memory model**, backed by Virtuoso queries instead of an `OWLOntologyManager`, while still using the OWL API parsers/storers only at the import/export boundary. That new model interface is the central design artifact; everything downstream depends on it.

### 3. Nothing today does lazy/partial loading — the whole point of the migration has no foothold yet

`buildVersionedOntology` / `loadSnapShot` in `protege/protege-editor-owl/src/main/java/org/protege/editor/owl/client/LocalHttpClient.java` (around lines 571–700) deserialize the entire ontology into an `OWLOntologyImpl` up front, then fast-forward with changes. There is no notion of "fetch class X and its neighbors on demand." Every consumer assumes `getActiveOntology()` returns a fully-materialized ontology and iterates it freely (hierarchy providers, entity finders, Lucene indexing). A Virtuoso-backed lazy model must satisfy those same access patterns via SPARQL — the hierarchy providers and `lucene-search-tab`'s change-driven indexing are the places that will fight a lazy model hardest.

### 4. The whole concurrency model is revision-number optimistic locking — it disappears in the new design

Commit-blocking is enforced by comparing `commitBundle.getBaseRevision()` to the server head in `protege/protege-editor-owl/src/main/java/org/protege/editor/owl/server/conflict/ConflictDetectionFilter.java` (around lines 38–60), with client polling in `.../client/action/EnableAutoUpdateAction.java` and merge/rebase in `.../client/action/UpdateAction.java`.

If clients write straight to Virtuoso, you lose: the linear revision history, the "must be at latest to commit" guarantee, conflict detection, and the change-history audit trail. Virtuoso/SPARQL 1.1 Update gives no equivalent transactionality or per-edit provenance out of the box. **You need to decide what replaces revisions** — graph-level versioning, RDF-star provenance, an external transaction/lock service, or keeping a slimmer commit-coordination service in front of Virtuoso. This is a policy decision, not a code detail, and it affects `metaproject` (access control) too.

### 5. Transport uses Java native serialization — a rewrite opportunity and a security liability

Commits/changes cross the wire as `ObjectOutputStream`/`ObjectInputStream` of `CommitBundle`, `ChangeHistory`, `DocumentRevision` (`LocalHttpClient.commit`, `HTTPChangeService.handlingRequest`). Moving to a SPARQL-endpoint model deletes this protocol entirely — good, because untrusted Java deserialization is a well-known RCE vector (OWASP A08).

### 6. Security debt in the current write path that must not be carried forward

`buildAnonParentQuery` / `buildCompQuery` build SPARQL Update by string-concatenating IRIs and literal values (`HTTPChangeService.java`, around lines 82–188) — literal values are interpolated with raw `"` quoting and no escaping. That is a SPARQL-injection / broken-data hazard today, and in a client-writes-directly world every client becomes an injection surface. The new mapping layer must use parameterized/programmatic RDF (RDF4J `Statement`/`Update` builders, proper literal escaping, full IRIs not short forms) rather than string building.

### 7. `nci-curator` is correctly the one thing to defer

Confirmed: it is a bespoke in-memory structural classifier (a Pellet-derived graph-walker, not a DL tableaux reasoner) in `nci-curator/src/main/java/gov/nih/nci/curator/owlapi/KnowledgeBase.java` that stores the whole `OWLOntology` and walks it. It is genuinely separable from the rest and can keep loading a full snapshot (via the OWL parsers being kept) even after everyone else goes lazy. It is also the one component that *is* a legitimate consumer of the full OWL API model, so it will anchor whatever OWL-API-based path is retained.

## Suggested framing of the work

Roughly in dependency order:

1. **Define a complete, bidirectional OWL 2 ↔ RDF mapping** and make it the single write/read contract for Virtuoso (replacing `ConvertToRdf`). This is prerequisite to everything.
2. **Introduce a new model abstraction** to stand in for `OWLModelManager`/`OWLOntology`, backed by SPARQL, keeping the OWL API only behind `OntologyLoader`/`OntologySaver` for file import/export.
3. **Decide the concurrency/provenance replacement** for revision numbers + `ConflictDetectionFilter` before removing the server.
4. **Port the hardest consumers** — hierarchy providers and `lucene-search-tab` — to the lazy model; they encode the "whole ontology in RAM" assumption most deeply.
5. **Leave `nci-curator` on a full-load path** and detach it last.

## Key files referenced

| Concern | File |
|---|---|
| Lossy OWL→RDF write path | `protege/protege-editor-owl/src/main/java/org/protege/editor/owl/server/http/handlers/HTTPChangeService.java` |
| Core in-memory model contract | `protege/protege-editor-owl/src/main/java/org/protege/editor/owl/model/OWLModelManager.java` |
| Full-snapshot load / no lazy loading | `protege/protege-editor-owl/src/main/java/org/protege/editor/owl/client/LocalHttpClient.java` |
| Revision-based conflict detection | `protege/protege-editor-owl/src/main/java/org/protege/editor/owl/server/conflict/ConflictDetectionFilter.java` |
| Client polling of server revision | `protege/protege-editor-owl/src/main/java/org/protege/editor/owl/client/action/EnableAutoUpdateAction.java` |
| Update/sync merge | `protege/protege-editor-owl/src/main/java/org/protege/editor/owl/client/action/UpdateAction.java` |
| I/O boundary to keep | `protege/protege-editor-owl/src/main/java/org/protege/editor/owl/model/io/OntologySaver.java`, `OntologyLoader.java` |
| Vendored format parsers to keep | `owlapi/parsers`, `owlapi/rio`, `owlapi/oboformat`, `binaryowl` |
| Read-side Virtuoso query plugin | `sparql-query-plugin/src/main/java/org/protege/editor/owl/rdf/RemoteSparqlReasoner.java` |
| In-memory classifier (defer) | `nci-curator/src/main/java/gov/nih/nci/curator/owlapi/KnowledgeBase.java` |
