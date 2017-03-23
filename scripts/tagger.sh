#!/bin/sh
NOW=`date +"%m_%d_%Y"`
TAG=$1
MSG=$2
echo $MSG
cd protege
git tag -a $TAG -m "$MSG"
git push bobd $TAG
cd ../metaproject
git tag -a $TAG -m "$MSG"
git push bobd $TAG
cd ../csv-export-plugin
git tag -a $TAG -m "$MSG"
git push bobd $TAG
cd ../lucene-search-plugin
git tag -a $TAG -m "$MSG"
git push bobd $TAG
cd ../lucene-search-tab
git tag -a $TAG -m "$MSG"
git push bobd $TAG
cd ../protege-server
git tag -a $TAG -m "$MSG"
git push bobd $TAG
cd ../protege-client
git tag -a $TAG -m "$MSG"
git push bobd $TAG
cd ../pellet
git tag -a $TAG -m "$MSG"
git push bobd $TAG
cd ../nci-protege5
git tag -a $TAG -m "$MSG"
git push bobd $TAG


