#!/bin/sh -e
NOW=`date +"%m_%d_%Y"`
TAG=$1
TARGET=$2
rm -Rf nci-protege5
mkdir nci-protege5
cd nci-protege5
git clone https://github.com/$TARGET/owlapi.git
cd owlapi
git checkout $TAG
mvn clean install -DskipTests=true
cd ..
git clone https://github.com/$TARGET/protege.git
cd protege
git checkout $TAG
mvn clean install -DskipTests=true
mkdir protege-desktop/target/protege-5.1.1-SNAPSHOT-platform-independent/Protege-5.1.1-SNAPSHOT/plugins
cp ../../run-editor.sh protege-desktop/target/protege-5.1.1-SNAPSHOT-platform-independent/Protege-5.1.1-SNAPSHOT/run.sh
cd ..
git clone https://github.com/$TARGET/metaproject.git
cd metaproject
git checkout $TAG
mvn clean install -DskipTests=true
cp target/metaproject-1.0.0-SNAPSHOT.jar ../protege/protege-desktop/target/protege-5.1.1-SNAPSHOT-platform-independent/Protege-5.1.1-SNAPSHOT/plugins
cd ..
git clone https://github.com/$TARGET/protege-server.git
cd protege-server
git checkout $TAG
mvn clean install -DskipTests=true
cp target/protege-server*.jar ../protege/protege-desktop/target/protege-5.1.1-SNAPSHOT-platform-independent/Protege-5.1.1-SNAPSHOT/plugins
cd ..
git clone https://github.com/$TARGET/protege-client.git
cd protege-client
git checkout $TAG
mvn clean install -DskipTests=true
cp target/protege-client*.jar ../protege/protege-desktop/target/protege-5.1.1-SNAPSHOT-platform-independent/Protege-5.1.1-SNAPSHOT/plugins
cd ../
git clone https://github.com/$TARGET/pellet.git
cd pellet
mvn clean install -DskipTests=true
cp protege/target/pellet-protege-2.4.0-SNAPSHOT.jar ../protege/protege-desktop/target/protege-5.1.1-SNAPSHOT-platform-independent/Protege-5.1.1-SNAPSHOT/plugins
cd ../
cp ../run-protege.sh .
cp ../run-server.sh .
zip -r nci-protege5-$NOW.zip protege protege-server run-server.sh run-protege.sh
tar -cvzf nci-protege5-$NOW.tar.gz protege protege-server run-server.sh run-protege.sh

