#!/bin/sh -e
NOW=`date +"%m_%d_%Y"`
TAG=$1
TARGET=$2
rm -Rf nci-protege5
mkdir nci-protege5
cd nci-protege5
mkdir protege-server
mkdir protege-server/target
mkdir protege-server/target/server-distribution
git clone https://github.com/$TARGET/binaryowl.git
cd binaryowl
git checkout $TAG
mvn clean install -DskipTests=true
cd ..
git clone https://github.com/$TARGET/owlapi.git
cd owlapi
git checkout $TAG
mvn clean install -DskipTests=true
cd ..
git clone https://github.com/$TARGET/metaproject.git
cd metaproject
git checkout $TAG
mvn clean install -DskipTests=true
cd ..
git clone https://github.com/$TARGET/protege.git
cd protege
git checkout $TAG
mvn clean install -DskipTests=true
mkdir protege-desktop/target/protege-5.1.2-SNAPSHOT-platform-independent/Protege-5.1.2-SNAPSHOT/plugins
cp ../../run-editor.sh protege-desktop/target/protege-5.1.2-SNAPSHOT-platform-independent/Protege-5.1.2-SNAPSHOT/run.sh
cd protege-editor-owl/target/server-distribution
cp -R server ../../../../protege-server/target/server-distribution
cd ../../..
cp ../metaproject/target/metaproject-1.0.1-SNAPSHOT.jar ../protege/protege-desktop/target/protege-5.1.2-SNAPSHOT-platform-independent/Protege-5.1.2-SNAPSHOT/plugins
cd ../
git clone https://github.com/$TARGET/explanation-workbench.git
cd explanation-workbench
git checkout $TAG
mvn clean install -DskipTests=true
cp target/explanation-workbench*SNAPSHOT.jar ../protege/protege-desktop/target/protege-5.1.2-SNAPSHOT-platform-independent/Protege-5.1.2-SNAPSHOT/lib
cd ../
cp ../run-protege.sh .
cp ../run-server.sh .
zip -r nci-protege5-$NOW.zip protege run-server.sh run-protege.sh
tar -cvzf nci-protege5-$NOW.tar.gz protege run-server.sh run-protege.sh
rm -r $HOME/.m2/repository/org/apache/struts
