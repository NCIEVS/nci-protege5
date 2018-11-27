#!/usr/bin/env bash

SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SOURCE" ]; do # resolve $SOURCE until the file is no longer a symlink
  DIR="$( cd -P "$( dirname "$SOURCE" )" && pwd )"
  SOURCE="$(readlink "$SOURCE")"
  [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE" # if $SOURCE was a relative symlink, we need to resolve it relative to the path where the symlink file was located
done
cd "$( cd -P "$( dirname "$SOURCE" )" && pwd )"

java -Xmx8000M -Xms2000M \
     -Xss16M \
     -Dlogback.configurationFile=conf/logback.xml \
     -DentityExpansionLimit=100000000 \
     -Dfile.encoding=UTF-8 \
     -Djava.util.prefs.PreferencesFactory=org.protege.editor.core.prefs.FileBackingStorePrefsFactory \
     -XX:CompileCommand=exclude,javax/swing/text/GlyphView,getBreakSpot \
     -classpath lib/*:bundles/*:bin/*:/plugins/* \
     $CMD_OPTIONS org.protege.editor.core.ProtegeApplication $1



