#!/bin/sh
NOW=`date +"%m_%d_%Y"`
TAG=$1
MSG=$2
TARGET=$3
echo $MSG
cd ../..
cd evs-history
git tag -a $TAG -m "$MSG"
git push $TARGET $TAG
cd ../lucene-search-tab
git tag -a $TAG -m "$MSG"
git push $TARGET $TAG
cd ../metaproject-admin
git tag -a $TAG -m "$MSG"
git push $TARGET $TAG
cd ../nci-edit-tab
git tag -a $TAG -m "$MSG"
git push $TARGET $TAG
cd ../revision-history
git tag -a $TAG -m "$MSG"
git push $TARGET $TAG
cd ../sparql-query-plugin
git tag -a $TAG -m "$MSG"
git push $TARGET $TAG



