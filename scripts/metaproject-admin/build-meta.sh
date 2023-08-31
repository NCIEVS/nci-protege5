#!/bin/sh -e
NOW=`date +"%m_%d_%Y"`
TAG=$1
TARGET=$2
rm -Rf meta-admin-app
mkdir meta-admin-app
cd meta-admin-app
git clone https://github.com/$TARGET/owlapi.git
cd owlapi
git checkout $TAG
mvn clean install -DskipTests=true
cd ..
git clone https://github.com/$TARGET/binaryowl.git
cd binaryowl
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
cp ../../run-meta-admin.sh protege-desktop/target/protege-5.1.2-SNAPSHOT-platform-independent/Protege-5.1.2-SNAPSHOT/run.sh
cd ../
git clone https://github.com/$TARGET/metaproject-admin.git
cd metaproject-admin
git checkout $TAG
mvn clean install -DskipTests=true
cd ../
cp metaproject/target/metaproject-1.0.3-SNAPSHOT.jar protege/protege-desktop/target/protege-5.1.2-SNAPSHOT-platform-independent/Protege-5.1.2-SNAPSHOT/plugins
cp metaproject-admin/target/metaproject-admin-*-SNAPSHOT.jar protege/protege-desktop/target/protege-5.1.2-SNAPSHOT-platform-independent/Protege-5.1.2-SNAPSHOT/plugins
cp ../meta-admin.sh .
cp ../run-meta-admin.sh .
zip -r meta-admin-app-$NOW.zip protege run-meta-admin.sh
tar -cvzf meta-admin-app-$NOW.tar.gz protege meta-admin.sh run-meta-admin.sh
rm -r $HOME/.m2/repository/org/apache/struts

