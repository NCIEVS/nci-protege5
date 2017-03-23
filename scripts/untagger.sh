#!/bin/sh
NOW=`date +"%m_%d_%Y"`
TAG=$1
MSG=$2
echo $MSG
cd protege
git tag -d $TAG
git push bobd :refs/tags/$TAG
cd ../metaproject
git tag -d $TAG
git push bobd :refs/tags/$TAG
cd ../csv-export-plugin
git tag -d $TAG
git push bobd :refs/tags/$TAG
cd ../lucene-search-plugin
git tag -d $TAG
git push bobd :refs/tags/$TAG
cd ../lucene-search-tab
git tag -d $TAG
git push bobd :refs/tags/$TAG
cd ../protege-server
git tag -d $TAG
git push bobd :refs/tags/$TAG
cd ../protege-client
git tag -d $TAG
git push bobd :refs/tags/$TAG
cd ../pellet
git tag -d $TAG
git push bobd :refs/tags/$TAG
cd ../nci-protege5
git tag -d $TAG
git push bobd :refs/tags/$TAG



