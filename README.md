# nci-protege5

````
git clone https://github.com/bdionne/protege.git

cd protege

git checkout nci-lucene-search

mvn clean install

````


````
git clone https://github.com/bdionne/protege-server.git

cd protege-server

mvn clean install

````

Now the server jar is needed by the protege client, so copy it to the
bundles:

````
cp target/protege-server-3.0.0-SNAPSHOT.jar
../protege/protege-desktop/target/protege-5.0.0-beta-21-SNAPSHOT-platform-independent/Protege-5.0.0-beta-21-SNAPSHOT/bundles

````


https://raw.githubusercontent.com/bdionne/autoupdate/master/plugins.repository
