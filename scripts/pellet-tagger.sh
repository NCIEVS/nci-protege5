#!/bin/sh
NOW=`date +"%m_%d_%Y"`
TAG=$1
MSG=$2
TARGET=$3
echo $MSG
cd ../..
cd pellet
git tag -a $TAG -m "$MSG"
git push $TARGET $TAG
cd ../
cd explanation-workbench
git tag -a $TAG -m "$MSG"
git push $TARGET $TAG



