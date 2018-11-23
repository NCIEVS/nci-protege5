#!/bin/sh
NOW=`date +"%m_%d_%Y"`
TAG=$1
MSG=$2
TARGET=$3
echo $MSG
cd ../..
cd evs-history
git tag -d $TAG
git push $TARGET :refs/tags/$TAG
cd ../lucene-search-tab
git tag -d $TAG
git push $TARGET :refs/tags/$TAG
cd ../metaproject-admin
git tag -d $TAG
git push $TARGET :refs/tags/$TAG
cd ../nci-edit-tab
git tag -d $TAG
git push $TARGET :refs/tags/$TAG
cd ../revision-history
git tag -d $TAG
git push $TARGET :refs/tags/$TAG
cd ../sparql-query-plugin
git tag -d $TAG
git push $TARGET :refs/tags/$TAG


