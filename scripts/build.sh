#!/bin/sh
NOW=`date +"%m_%d_%Y"`
TAG=$1
rm -Rf nci-protege5
mkdir nci-protege5
cd nci-protege5
git clone https://github.com/bdionne/protege.git
cd protege
git checkout -b search-api origin/search-api
mvn clean install -DskipTests=true
mkdir protege-desktop/target/protege-5.0.1-SNAPSHOT-platform-independent/Protege-5.0.1-SNAPSHOT/plugins
cp ../../run-editor.sh protege-desktop/target/protege-5.0.1-SNAPSHOT-platform-independent/Protege-5.0.1-SNAPSHOT/run.sh
cd ..
git clone https://github.com/protegeproject/metaproject.git
cd metaproject
git checkout $TAG
mvn clean install -DskipTests=true
cp target/metaproject-1.0.0-SNAPSHOT.jar ../protege/protege-desktop/target/protege-5.0.1-SNAPSHOT-platform-independent/Protege-5.0.1-SNAPSHOT/plugins
cd ..
git clone https://github.com/protegeproject/csv-export-plugin.git
cd csv-export-plugin
mvn clean install
cp target/csv-export-plugin-1.0.0-SNAPSHOT.jar ../protege/protege-desktop/target/protege-5.0.1-SNAPSHOT-platform-independent/Protege-5.0.1-SNAPSHOT/plugins
cd ..
git clone https://github.com/protegeproject/lucene-search-plugin.git
cd lucene-search-plugin
git checkout -b nci-lucene-search origin/nci-lucene-search
mvn clean install -DskipTests=true
cp target/lucene-search-plugin-1.0.0-SNAPSHOT.jar ../protege/protege-desktop/target/protege-5.0.1-SNAPSHOT-platform-independent/Protege-5.0.1-SNAPSHOT/plugins
cd ..
git clone https://github.com/protegeproject/lucene-search-tab.git
cd lucene-search-tab
mvn clean install
cp target/lucene-search-tab-1.0.0-SNAPSHOT.jar ../protege/protege-desktop/target/protege-5.0.1-SNAPSHOT-platform-independent/Protege-5.0.1-SNAPSHOT/plugins
cd ..
git clone https://github.com/protegeproject/protege-server.git
cd protege-server
git checkout $TAG
mvn clean install -DskipTests=true
cp target/protege-server*.jar ../protege/protege-desktop/target/protege-5.0.1-SNAPSHOT-platform-independent/Protege-5.0.1-SNAPSHOT/plugins
cp -R root target/server-distribution/server
cd ..
git clone https://github.com/protegeproject/protege-client.git
cd protege-client
git checkout $TAG
mvn clean install -DskipTests=true
cp target/protege-client*.jar ../protege/protege-desktop/target/protege-5.0.1-SNAPSHOT-platform-independent/Protege-5.0.1-SNAPSHOT/plugins
cd ..
git clone https://github.com/bdionne/nci-edit-tab.git
cd nci-edit-tab
mvn clean install -DskipTests=true
cp target/nci-edit-tab*.jar ../protege/protege-desktop/target/protege-5.0.1-SNAPSHOT-platform-independent/Protege-5.0.1-SNAPSHOT/plugins
cd ../
cp ../run-protege.sh .
cp ../run-server.sh .
zip -r nci-protege5-$NOW.zip protege protege-server run-server.sh run-protege.sh
tar -cvzf nci-protege5-$NOW.tar.gz protege protege-server run-server.sh run-protege.sh

