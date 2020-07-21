#!/bin/sh
NOW=`date +"%m_%d_%Y"`
TAG=$1
MSG=$2
TARGET=$3
echo $MSG
cd ../..
cd explanation-workbench
git tag -a $TAG -m "$MSG"
git push $TARGET $TAG
cd ../binaryowl
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

