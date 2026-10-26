#!/bin/sh -e
# nci-curator and lucene-search-tab are client plugins AND server libraries: the server runs their
# ServiceLoader entry points (classifier, index builder), and the client now gets them packaged into
# its plugins/ dir (no longer via the plugin autoupdater). They build as modules of the protege
# reactor from the same $TAG as everything else, so the client and server always run identical plugin
# code at one version -- no separate GitHub release or Update-Url to keep in lockstep.
# A UI-only plugin change now requires rebuilding/repackaging the client (and, if it touches any
# wire/Lucene-index/inferred-graph contract, the server too).

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
# Server-side plugins nci-curator and lucene-search-tab now build as modules of the protege reactor
# above (same tag, same version), so there is no separate clone/build here. Their jars drive the
# server's ServiceLoader entry points (CuratorOntologyClassifier, SearchTabProjectIndexBuilder).
SRVLIB=protege/protege-editor-owl/target/server-distribution/server/lib
set -- protege/nci-curator/target/nci-curator-*.jar
[ $# -eq 1 ] && [ -f "$1" ] || { echo "ERROR: expected exactly one nci-curator jar in target/, found: $*"; exit 1; }
curator_jar="$1"
cp "$curator_jar" "$SRVLIB"/
set -- protege/lucene-search-tab/target/lucene-search-tab-*.jar
[ $# -eq 1 ] && [ -f "$1" ] || { echo "ERROR: expected exactly one lucene-search-tab jar in target/, found: $*"; exit 1; }
lucene_jar="$1"
cp "$lucene_jar" "$SRVLIB"/
# protege-editor-core is 'provided' scope in protege-editor-owl (the client OSGi platform supplies it),
# so the server assembly omits it -- but the lucene-search-tab index builder needs
# org.protege.editor.core.Disposable, so add it explicitly.
core_jar=`ls protege/protege-editor-core/target/protege-editor-core-*.jar | grep -Ev '(sources|tests|javadoc)\.jar$' | head -1`
[ -f "$core_jar" ] || { echo "ERROR: protege-editor-core jar not found"; exit 1; }
cp "$core_jar" "$SRVLIB"/
# The flat server classpath needs the plugins' third-party deps that the assembly does not already
# ship (jgrapht for the classifier; lucene-analyzers-phonetic and imgscalr for the index builder).
# Resolve them from Maven straight into server/lib -- no unzipping embedded bundle jars.
DEPCOPY="org.apache.maven.plugins:maven-dependency-plugin:3.1.1:copy"
mvn -q -f protege/protege-editor-owl/pom.xml $DEPCOPY -Dartifact=org.jgrapht:jgrapht-jdk1.5:0.7.3 -DoutputDirectory="$SRVLIB"
mvn -q -f protege/protege-editor-owl/pom.xml $DEPCOPY -Dartifact=org.apache.lucene:lucene-analyzers-phonetic:7.1.0 -DoutputDirectory="$SRVLIB"
mvn -q -f protege/protege-editor-owl/pom.xml $DEPCOPY -Dartifact=org.imgscalr:imgscalr-lib:4.2 -DoutputDirectory="$SRVLIB"
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
# Package the two NCI plugins into the client as well (no longer delivered by the plugin autoupdater),
# so the client and server always run the identical plugin build from this tag.
cp nci-curator/target/nci-curator-*.jar protege-desktop/target/protege-5.1.2-SNAPSHOT-platform-independent/Protege-5.1.2-SNAPSHOT/plugins/
cp lucene-search-tab/target/lucene-search-tab-*.jar protege-desktop/target/protege-5.1.2-SNAPSHOT-platform-independent/Protege-5.1.2-SNAPSHOT/plugins/
cd ../
cp ../run-protege.sh .
cp ../run-server.sh .
zip -r nci-protege5-$NOW.zip protege run-server.sh run-protege.sh
tar -cvzf nci-protege5-$NOW.tar.gz protege run-server.sh run-protege.sh
## rm -r $HOME/.m2/repository/org/apache/struts

