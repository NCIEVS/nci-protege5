#!/bin/sh -e
# nci-curator and lucene-search-tab are client plugins AND server libraries: the server runs their
# ServiceLoader entry points (classifier, index builder), the client gets them via autoupdate. They
# are built here from the same $TAG as everything else so the client and server run identical plugin
# code -- keep each plugin's GitHub release in lockstep with the tag it is built from.
# A UI-only plugin change can ship to the client alone (separate JVMs, no shared classes) PROVIDED it
# is built against this same core tag and changes no wire/Lucene-index/inferred-graph contract;
# when in doubt, rebuild the server too.

# Mirror what the client autoupdater does for an OSGi plugin on the flat server classpath: extract the
# bundle's embedded (Bundle-ClassPath) jars into server/lib, skipping any whose artifact (name minus
# version) the server assembly already provides, so no second, conflicting version is added.
extract_embedded_jars() {
  _bundle="$1"; _dest="$2"; _tmp=`mktemp -d`
  for _emb in `unzip -l "$_bundle" | awk '/\.jar$/{print $NF}'`; do
    _base=`basename "$_emb"`
    _prefix=`echo "$_base" | sed -E 's/-[0-9].*\.jar$//'`
    if ls "$_dest"/"$_prefix"-[0-9]*.jar >/dev/null 2>&1; then
      echo "  server lib: $_prefix already present, skip embedded $_base"
    else
      unzip -o -j "$_bundle" "$_emb" -d "$_tmp" >/dev/null
      cp "$_tmp/$_base" "$_dest"/
      echo "  server lib: added embedded $_base"
    fi
  done
  rm -rf "$_tmp"
}

NOW=`date +"%m_%d_%Y"`
TAG=$1
TARGET=$2
rm -Rf nci-protege5
mkdir nci-protege5
cd nci-protege5
mkdir protege-server
mkdir protege-server/target
mkdir protege-server/target/server-distribution
git clone git@github.com:$TARGET/owlapi.git
cd owlapi
git checkout $TAG
mvn clean install -DskipTests=true
cd ..
git clone git@github.com:$TARGET/binaryowl.git
cd binaryowl
git checkout $TAG
mvn clean install -DskipTests=true
cd ..
git clone git@github.com:$TARGET/xmlcatalog.git
cd xmlcatalog
git checkout $TAG
mvn clean install -DskipTests=true
cd ..
git clone git@github.com:$TARGET/owl-rdf-io.git
cd owl-rdf-io
git checkout $TAG
mvn clean install -DskipTests=true
cd ..
git clone git@github.com:$TARGET/owl-virtuoso.git
cd owl-virtuoso
git checkout $TAG
mvn clean install -DskipTests=true
cd ..
git clone git@github.com:$TARGET/metaproject.git
cd metaproject
git checkout $TAG
mvn clean install -DskipTests=true
cd ..
git clone git@github.com:$TARGET/protege.git
cd protege
git checkout $TAG
mvn clean install -DskipTests=true
cd ..
# Server-side plugins: the whole plugin jar on the server classpath drives its ServiceLoader entry
# points (CuratorOntologyClassifier, SearchTabProjectIndexBuilder). Built from the same tag so the
# client (via autoupdate) and the server run identical plugin code.
git clone git@github.com:$TARGET/nci-curator.git
cd nci-curator
git checkout $TAG
mvn clean install -DskipTests=true
cd ..
git clone git@github.com:$TARGET/lucene-search-tab.git
cd lucene-search-tab
git checkout $TAG
mvn clean install -DskipTests=true
cd ..
SRVLIB=protege/protege-editor-owl/target/server-distribution/server/lib
set -- nci-curator/target/nci-curator-*.jar
[ $# -eq 1 ] && [ -f "$1" ] || { echo "ERROR: expected exactly one nci-curator jar in target/, found: $*"; exit 1; }
curator_jar="$1"
cp "$curator_jar" "$SRVLIB"/
set -- lucene-search-tab/target/lucene-search-tab-*.jar
[ $# -eq 1 ] && [ -f "$1" ] || { echo "ERROR: expected exactly one lucene-search-tab jar in target/, found: $*"; exit 1; }
lucene_jar="$1"
cp "$lucene_jar" "$SRVLIB"/
# protege-editor-core is 'provided' scope in protege-editor-owl (the client OSGi platform supplies it),
# so the server assembly omits it -- but the lucene-search-tab index builder needs
# org.protege.editor.core.Disposable, so add it explicitly.
core_jar=`ls protege/protege-editor-core/target/protege-editor-core-*.jar | grep -Ev '(sources|tests|javadoc)\.jar$' | head -1`
[ -f "$core_jar" ] || { echo "ERROR: protege-editor-core jar not found"; exit 1; }
cp "$core_jar" "$SRVLIB"/
# Extract the plugins' embedded deps the flat server classpath needs (jgrapht for the classifier;
# lucene-analyzers-phonetic/imgscalr for the index builder); dedup keeps the binaryowl, commons-codec
# and lucene core the assembly already ships.
extract_embedded_jars "$curator_jar" "$SRVLIB"
extract_embedded_jars "$lucene_jar" "$SRVLIB"
cd protege
zip -q -d protege-desktop/target/protege-5.1.2-SNAPSHOT-platform-independent/Protege-5.1.2-SNAPSHOT/lib/log4j-core-2.26.1.jar org/apache/logging/log4j/core/lookup/JndiLookup.class
zip -q -d protege-desktop/target/protege-5.1.2-SNAPSHOT-platform-independent/Protege-5.1.2-SNAPSHOT/lib/log4j-core-2.26.1.jar org/apache/logging/log4j/core/appender/db/jdbc/JdbcAppender.class
mkdir protege-desktop/target/protege-5.1.2-SNAPSHOT-platform-independent/Protege-5.1.2-SNAPSHOT/plugins
cp ../../run-editor.sh protege-desktop/target/protege-5.1.2-SNAPSHOT-platform-independent/Protege-5.1.2-SNAPSHOT/run.sh
cd protege-editor-owl/target/server-distribution
zip -q -d server/lib/log4j-core-2.26.1.jar org/apache/logging/log4j/core/lookup/JndiLookup.class
zip -q -d server/lib/log4j-core-2.26.1.jar org/apache/logging/log4j/core/appender/db/jdbc/JdbcAppender.class
cp -R server ../../../../protege-server/target/server-distribution
cd ../../..
cp ../metaproject/target/metaproject-1.0.3-SNAPSHOT.jar ../protege/protege-desktop/target/protege-5.1.2-SNAPSHOT-platform-independent/Protege-5.1.2-SNAPSHOT/plugins
cd ../
cp ../run-protege.sh .
cp ../run-server.sh .
zip -r nci-protege5-$NOW.zip protege run-server.sh run-protege.sh
tar -cvzf nci-protege5-$NOW.tar.gz protege run-server.sh run-protege.sh
## rm -r $HOME/.m2/repository/org/apache/struts

