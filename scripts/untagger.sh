#!/bin/sh
NOW=`date +"%m_%d_%Y"`
TAG=$1
MSG=$2
TARGET=$3
echo $MSG
cd ../..
cd explanation-workbench
git tag -d $TAG
git push $TARGET :refs/tags/$TAG
cd ../binaryowl
git tag -d $TAG
git push $TARGET :refs/tags/$TAG
cd ../owlapi
git tag -d $TAG
git push $TARGET :refs/tags/$TAG
cd ../protege
git tag -d $TAG
git push $TARGET :refs/tags/$TAG
cd ../metaproject
git tag -d $TAG
git push $TARGET :refs/tags/$TAG
cd ../protege-server
git tag -d $TAG
git push $TARGET :refs/tags/$TAG
cd ../protege-client
git tag -d $TAG
git push $TARGET :refs/tags/$TAG
cd ../pellet
git tag -d $TAG
git push $TARGET :refs/tags/$TAG
cd ../nci-protege5
git tag -d $TAG
git push $TARGET :refs/tags/$TAG



