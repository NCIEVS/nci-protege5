#!/bin/sh
NOW=`date +"%m_%d_%Y"`
TAG=$1
MSG=$2
TARGET=$3
echo $MSG
cd ../..
cd binaryowl
git tag -a $TAG -m "$MSG"
git push $TARGET $TAG
cd ../owlapi
git tag -a $TAG -m "$MSG"
git push $TARGET $TAG
cd ../protege
git tag -a $TAG -m "$MSG"
git push $TARGET $TAG
cd ../metaproject
git tag -a $TAG -m "$MSG"
git push $TARGET $TAG
cd ../protege-server
git tag -a $TAG -m "$MSG"
git push $TARGET $TAG
cd ../protege-client
git tag -a $TAG -m "$MSG"
git push $TARGET $TAG
cd ../pellet
git tag -a $TAG -m "$MSG"
git push $TARGET $TAG
cd ../nci-protege5
git tag -a $TAG -m "$MSG"
git push $TARGET $TAG


