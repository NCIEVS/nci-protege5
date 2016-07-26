#!/bin/sh
NOW=`date +"%m_%d_%Y"`
rm -Rf nci-protege5
mkdir nci-protege5
cd nci-protege5
git clone https://github.com/bdionne/protege.git
cd protege
git checkout -b search-api origin/search-api
mvn clean install -DskipTests=true
cd ..
git clone https://github.com/protegeproject/metaproject.git
cd metaproject
mvn clean install -DskipTests=true
cp target/metaproject*.jar ../protege/protege-desktop/target/protege-5.0.1-SNAPSHOT-platform-independent/Protege-5.0.1-SNAPSHOT/bundles
cd ..
git clone https://github.com/protegeproject/lucene-search-plugin.git
cd lucene-search-plugin
git checkout -b nci-lucene-search origin/nci-lucene-search
mvn clean install -DskipTests=true
cp target/lucene*.jar ../protege/protege-desktop/target/protege-5.0.1-SNAPSHOT-platform-independent/Protege-5.0.1-SNAPSHOT/bundles
cd ..
git clone https://github.com/protegeproject/protege-server.git
cd protege-server
git checkout -b http-metaproject-integration origin/http-metaproject-integration
mvn clean install -DskipTests=true
cp target/protege-server*.jar ../protege/protege-desktop/target/protege-5.0.1-SNAPSHOT-platform-independent/Protege-5.0.1-SNAPSHOT/bundles
cd ..
git clone https://github.com/protegeproject/protege-client.git
cd protege-client
git checkout -b http-metaproject-integration origin/http-metaproject-integration
mvn clean install -DskipTests=true
cp target/protege-client*.jar ../protege/protege-desktop/target/protege-5.0.1-SNAPSHOT-platform-independent/Protege-5.0.1-SNAPSHOT/bundles

cd ..
git clone https://github.com/bdionne/nci-edit-tab.git
cd nci-edit-tab
mvn clean install -DskipTests=true
cp target/nci-edit-tab*.jar ../protege/protege-desktop/target/protege-5.0.1-SNAPSHOT-platform-independent/Protege-5.0.1-SNAPSHOT/bundles
cd ../
zip -r nci-protege5-$NOW.zip protege protege-server ../run-server.sh ../run-protege.sh

