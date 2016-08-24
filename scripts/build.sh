#!/bin/sh
NOW=`date +"%m_%d_%Y"`
rm -Rf nci-protege5
mkdir nci-protege5
cd nci-protege5
git clone https://github.com/bdionne/protege.git
cd protege
git checkout d1.4
mvn clean install -DskipTests=true
cd ..
git clone https://github.com/protegeproject/metaproject.git
cd metaproject
git checkout d1.4
mvn clean install -DskipTests=true
cp target/metaproject*.jar ../protege/protege-desktop/target/protege-5.0.1-SNAPSHOT-platform-independent/Protege-5.0.1-SNAPSHOT/bundles
cd ..
git clone https://github.com/protegeproject/lucene-search-plugin.git
cd lucene-search-plugin
git checkout d1.4
mvn clean install -DskipTests=true
cp target/lucene*.jar ../protege/protege-desktop/target/protege-5.0.1-SNAPSHOT-platform-independent/Protege-5.0.1-SNAPSHOT/bundles
cd ..
git clone https://github.com/protegeproject/protege-server.git
cd protege-server
git checkout d1.4
mvn clean install -DskipTests=true
cp target/protege-server*.jar ../protege/protege-desktop/target/protege-5.0.1-SNAPSHOT-platform-independent/Protege-5.0.1-SNAPSHOT/bundles
cp -R root target/server-distribution/server
cd ..
git clone https://github.com/protegeproject/protege-client.git
cd protege-client
git checkout d1.4
mvn clean install -DskipTests=true
cp target/protege-client*.jar ../protege/protege-desktop/target/protege-5.0.1-SNAPSHOT-platform-independent/Protege-5.0.1-SNAPSHOT/bundles

cd ..
git clone https://github.com/bdionne/nci-edit-tab.git
cd nci-edit-tab
mvn clean install -DskipTests=true
cp target/nci-edit-tab*.jar ../protege/protege-desktop/target/protege-5.0.1-SNAPSHOT-platform-independent/Protege-5.0.1-SNAPSHOT/bundles
cd ../
cp ../run-protege.sh .
cp ../run-server.sh .
zip -r nci-protege5-$NOW.zip protege protege-server run-server.sh run-protege.sh
tar -cvzf nci-protege5-$NOW.tar.gz protege protege-server run-server.sh run-protege.sh

