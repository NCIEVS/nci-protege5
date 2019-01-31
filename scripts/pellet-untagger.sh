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
cd ../
cd pellet
git tag -d $TAG
git push $TARGET :refs/tags/$TAG

