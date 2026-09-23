#!/usr/bin/env python3
"""
Produce a small test ontology from full NCI Thesaurus RDF/XML.

Keeps: ontology header + all annotation/object/datatype property declarations,
all rdfs:Datatype enumerations (owl:oneOf value sets that the editor enforces for
complex-property qualifiers, e.g. term-source-enum=NCI, term-group-enum=PT),
top-level root classes, and one level of named subclasses beneath each root.
Streaming, two-pass, low memory — never loads the whole graph into an object model.

Usage:
  make_test_ontology.py INPUT.owl OUTPUT.owl [--levels N] [--max-children-per-root M]

Selection rules:
  * A named superclass = <rdfs:subClassOf rdf:resource="IRI"/> OR the genus of a
    defined class (a <rdf:Description rdf:about="IRI"/> member of an intersectionOf,
    used by owl:equivalentClass), where IRI != owl:Thing.
  * root  = declared class with NO named superclass that is itself used as a named
            superclass by >=1 other class (filters stray parentless leaf classes and
            fully-defined classes whose genus lives in owl:equivalentClass).
  * levelK children = classes whose named superclass is in level K-1.
  * kept classes = roots U level1 (default --levels 1).

Referential integrity (so the top level holds only real roots, no orphan code-named
classes appear from dangling references):
  * Prune from every kept block any child element that references a class outside the
    kept slice (secondary parents, role fillers in equivalentClass/restrictions,
    object-valued associations, object-property domain/range). This drops logical role
    definitions whose fillers are outside the slice.
  * Because pruning removes equivalentClass genus edges, inject an explicit
    <rdfs:subClassOf rdf:resource="parent"/> for each kept named super, so defined
    classes stay parented instead of orphaning to the top level.
"""
import re
import sys
import argparse

OWL_THING = "http://www.w3.org/2002/07/owl#Thing"
ABOUT_RE = re.compile(r'rdf:about="([^"]+)"')
SUPER_RE = re.compile(r'<rdfs:subClassOf rdf:resource="([^"]+)"\s*/>')
SRC_RE = re.compile(r'<owl:annotatedSource rdf:resource="([^"]+)"\s*/>')
# named class member of an intersectionOf (the genus of a defined class)
DESC_RE = re.compile(r'<rdf:Description rdf:about="([^"]+)"')
# any object reference to a named Thesaurus class (Cxxxx)
RES_C_RE = re.compile(r'rdf:resource="([^"]*#C\d+)"')
ELEM_RE = re.compile(r'<\s*([A-Za-z][\w:.\-]*)')
SUBCLASS_RES_RE = re.compile(r'<rdfs:subClassOf rdf:resource="([^"]+)"\s*/>')

CLASS_START = "<owl:Class rdf:about="
CLASS_END = "</owl:Class>"
AXIOM_START = "<owl:Axiom>"
AXIOM_END = "</owl:Axiom>"
DATATYPE_START = "<rdfs:Datatype rdf:about="
DATATYPE_TAG = "<rdfs:Datatype"
DATATYPE_END = "</rdfs:Datatype>"
PROP_STARTS = (
    "<owl:AnnotationProperty rdf:about=",
    "<owl:ObjectProperty rdf:about=",
    "<owl:DatatypeProperty rdf:about=",
)
PROP_ENDS = (
    "</owl:AnnotationProperty>",
    "</owl:ObjectProperty>",
    "</owl:DatatypeProperty>",
)


def pass1_structure(path, levels):
    """Return (kept_classes:set, property_iris:set)."""
    supers = {}          # class IRI -> set(named super IRIs)
    used_as_super = set()  # IRIs that appear as a named super of something
    property_iris = set()

    cur_iri = None
    cur_supers = None
    cur_depth = 0
    in_prop = False

    with open(path, "r", encoding="utf-8") as f:
        for line in f:
            s = line.strip()
            if in_prop:
                if s.startswith(PROP_ENDS):
                    in_prop = False
                continue
            if s.startswith(PROP_STARTS):
                m = ABOUT_RE.search(s)
                if m:
                    property_iris.add(m.group(1))
                if not s.endswith("/>"):
                    in_prop = True
                continue
            if cur_iri is None:
                if s.startswith(CLASS_START):
                    m = ABOUT_RE.search(s)
                    cur_iri = m.group(1) if m else None
                    cur_supers = set()
                    cur_depth = 1
                    if s.endswith("/>"):  # empty declaration
                        if cur_iri is not None:
                            supers[cur_iri] = cur_supers
                        cur_iri = None
                continue
            # inside a class block (only the outermost subClassOf is a named super)
            if cur_depth == 1:
                sm = SUPER_RE.search(s)
                if sm and sm.group(1) != OWL_THING:
                    cur_supers.add(sm.group(1))
                    used_as_super.add(sm.group(1))
            # genus of a defined class (equivalentClass / anonymous intersectionOf)
            dm = DESC_RE.search(s)
            if dm and dm.group(1) != OWL_THING:
                cur_supers.add(dm.group(1))
                used_as_super.add(dm.group(1))
            cur_depth += s.count("<owl:Class") - s.count("</owl:Class>")
            if cur_depth == 0:
                supers[cur_iri] = cur_supers
                cur_iri = None

    roots = {c for c, sup in supers.items() if not sup and c in used_as_super}
    kept = set(roots)
    frontier = roots
    for _ in range(levels):
        nxt = {c for c, sup in supers.items() if sup & frontier}
        nxt -= kept
        kept |= nxt
        frontier = nxt
    return kept, property_iris, roots, supers


def _split_children(body):
    """Yield each top-level child element of a block body as a list of lines."""
    i = 0
    n = len(body)
    while i < n:
        line = body[i]
        st = line.strip()
        m = ELEM_RE.match(st)
        name = m.group(1) if m else None
        if st.endswith("/>") or (name and ("</" + name + ">") in line):
            yield [line]
            i += 1
            continue
        elem = [line]
        i += 1
        close = ("</" + name + ">") if name else None
        while i < n:
            elem.append(body[i])
            done = close is not None and close in body[i]
            i += 1
            if done:
                break
        yield elem


def _prune_block(buf, kept):
    """Drop child elements that reference any class outside the kept slice."""
    head, tail, body = buf[0], buf[-1], buf[1:-1]
    out = [head]
    for elem in _split_children(body):
        refs = RES_C_RE.findall("".join(elem))
        if all(r in kept for r in refs):
            out.extend(elem)
    out.append(tail)
    return out


def _inject_parents(pruned, iri, supers, kept):
    """Ensure the class asserts an explicit subClassOf to each kept named super.

    Needed because pruning removes equivalentClass genus edges whose sibling role
    fillers fall outside the slice; without this, defined classes would orphan to
    the top level.
    """
    parents = supers.get(iri, set()) & kept
    if not parents:
        return pruned
    present = set(SUBCLASS_RES_RE.findall("".join(pruned)))
    missing = sorted(parents - present)
    if not missing:
        return pruned
    inj = ['        <rdfs:subClassOf rdf:resource="%s"/>\n' % p for p in missing]
    return [pruned[0]] + inj + pruned[1:]


def pass2_emit(path, out, kept, property_iris, max_children_per_root, roots, supers):
    kept_entities = kept | property_iris
    child_count = {}  # not used unless capping

    def class_allowed(iri, block_supers):
        if max_children_per_root is None:
            return iri in kept
        if iri in roots:
            return True
        if iri not in kept:
            return False
        parent = next(iter(block_supers & roots), None)
        if parent is None:
            return True
        n = child_count.get(parent, 0)
        if n >= max_children_per_root:
            return False
        child_count[parent] = n + 1
        return True

    with open(path, "r", encoding="utf-8") as f, open(out, "w", encoding="utf-8") as w:
        # 1) header: copy verbatim through </owl:Ontology>
        for line in f:
            w.write(line)
            if "</owl:Ontology>" in line:
                break

        buf = []
        block = None       # None | 'class' | 'axiom' | 'prop'
        block_iri = None
        block_supers = set()
        depth = 0

        for line in f:
            s = line.strip()
            if block is None:
                if s.startswith(PROP_STARTS):
                    m = ABOUT_RE.search(s)
                    block_iri = m.group(1) if m else None
                    if s.endswith("/>"):
                        w.write(line)  # keep declaration
                        continue
                    block, buf = "prop", [line]
                elif s.startswith(CLASS_START):
                    m = ABOUT_RE.search(s)
                    block_iri = m.group(1) if m else None
                    block_supers = set()
                    if s.endswith("/>"):
                        if block_iri in kept:
                            w.write(line)
                        continue
                    block, buf, depth = "class", [line], 1
                elif s.startswith(DATATYPE_START):
                    # named datatype enum (owl:oneOf value set) -> always keep verbatim
                    if s.endswith("/>"):
                        w.write(line)
                        continue
                    block, buf, depth = "datatype", [line], 1
                elif s.startswith(AXIOM_START):
                    block, buf, block_iri = "axiom", [line], None
                # else: comment / blank in body -> drop
                continue

            buf.append(line)
            if block == "class":
                if depth == 1:
                    sm = SUPER_RE.search(s)
                    if sm and sm.group(1) != OWL_THING:
                        block_supers.add(sm.group(1))
                depth += s.count("<owl:Class") - s.count("</owl:Class>")
                if depth == 0:
                    if class_allowed(block_iri, block_supers):
                        pruned = _prune_block(buf, kept)
                        pruned = _inject_parents(pruned, block_iri, supers, kept)
                        w.writelines(pruned)
                    block, buf = None, []
            elif block == "prop":
                if s.startswith(PROP_ENDS):
                    w.writelines(_prune_block(buf, kept))
                    block, buf = None, []
            elif block == "datatype":
                depth += s.count(DATATYPE_TAG) - s.count(DATATYPE_END)
                if depth == 0:
                    w.writelines(buf)
                    block, buf = None, []
            elif block == "axiom":
                if block_iri is None:
                    sm = SRC_RE.search(s)
                    if sm:
                        block_iri = sm.group(1)
                if s.startswith(AXIOM_END):
                    refs = RES_C_RE.findall("".join(buf))
                    if block_iri in kept_entities and all(r in kept for r in refs):
                        w.writelines(buf)
                    block, buf = None, []

        w.write("</rdf:RDF>\n")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("input")
    ap.add_argument("output")
    ap.add_argument("--levels", type=int, default=1)
    ap.add_argument("--max-children-per-root", type=int, default=None)
    args = ap.parse_args()

    sys.stderr.write("pass 1: scanning class hierarchy...\n")
    kept, props, roots, supers = pass1_structure(args.input, args.levels)
    sys.stderr.write(
        f"  roots={len(roots)}  kept-classes={len(kept)}  properties={len(props)}\n"
    )
    sys.stderr.write("pass 2: writing test ontology...\n")
    pass2_emit(args.input, args.output, kept, props, args.max_children_per_root, roots, supers)
    sys.stderr.write("done\n")


if __name__ == "__main__":
    main()
