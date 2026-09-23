#!/usr/bin/env python3
"""Transform a new-style OWL API RDF/XML file (reified owl:Axiom blocks inline)
into the old-style layout expected by InferredFileGenerator: all owl:Axiom
reified-annotation blocks moved to the end under a "// Annotations" banner.
"""
import sys

SRC = "/Users/dionnero/protege/nci-protege5/data/Thesaurus-test-small-foo.owl"
DST = "/Users/dionnero/protege/nci-protege5/data/Thesaurus-test-small-annotated.owl"

with open(SRC, encoding="utf-8") as f:
    lines = f.readlines()

# Reuse the exact slash-rule line from an existing banner so formatting matches.
slash_line = None
for ln in lines:
    if ln.strip().startswith("//////"):
        slash_line = ln
        break
if slash_line is None:
    sys.exit("Could not find an existing banner slash line to copy.")

out = []
axioms = []
i, n = 0, len(lines)
while i < n:
    if lines[i].strip() == "<owl:Axiom>":
        block = [lines[i]]
        i += 1
        while i < n and lines[i].strip() != "</owl:Axiom>":
            block.append(lines[i])
            i += 1
        if i < n:  # append closing </owl:Axiom>
            block.append(lines[i])
            i += 1
        axioms.extend(block)
    else:
        out.append(lines[i])
        i += 1

banner = [
    "    <!-- \n",
    slash_line,
    "    //\n",
    "    // Annotations\n",
    "    //\n",
    slash_line,
    "     -->\n",
    "\n",
    "\n",
    "    \n",
]

rdf_idx = max(idx for idx, l in enumerate(out) if l.strip() == "</rdf:RDF>")
new = out[:rdf_idx] + banner + axioms + out[rdf_idx:]

with open(DST, "w", encoding="utf-8") as f:
    f.writelines(new)

print(f"axiom blocks moved: {sum(1 for l in axioms if l.strip() == '<owl:Axiom>')}")
print(f"input lines:  {len(lines)}")
print(f"output lines: {len(new)}")
print(f"wrote: {DST}")
