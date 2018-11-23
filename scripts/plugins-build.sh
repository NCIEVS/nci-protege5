#!/bin/sh -e
NOW=`date +"%m_%d_%Y"`
TAG=$1
TARGET=$2
cd nci-protege5


for p in lucene-search-tab metaproject-admin nci-edit-tab revision-history sparql-query-plugin
do
    echo Building $p ...
    git clone https://github.com/$TARGET/$p.git
    cd $p
    git checkout $TAG
    mvn clean install -DskipTests=true
    cp target/$p*SNAPSHOT.jar ../protege/protege-desktop/target/protege-5.1.2-SNAPSHOT-platform-independent/Protege-5.1.2-SNAPSHOT/plugins
    cd ..
done






