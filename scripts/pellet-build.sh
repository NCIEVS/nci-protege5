#!/bin/sh -e
NOW=`date +"%m_%d_%Y"`
TAG=$1
TARGET=$2
rm -Rf nci-protege5-pellet
mkdir nci-protege5-pellet
cd nci-protege5-pellet
git clone https://github.com/$TARGET/explanation-workbench.git
cd explanation-workbench
git checkout $TAG
mvn clean install -DskipTests=true
cd ../
git clone https://github.com/$TARGET/pellet.git
cd pellet
git checkout $TAG
mvn clean install -DskipTests=true

