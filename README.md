# NCI Protege 5

## Build

Building is pretty easy, first build Protege 5 then build the protege
server

### Protege 5

Start with a top level directory to make clean up easier:

````
mkdir <my-top-level>

cd <my-top-level>

git clone https://github.com/bdionne/protege.git

cd protege

git checkout nci-lucene-search

mvn clean install

````

### Protege Server

````
cd ../<my-top-level>

git clone https://github.com/bdionne/protege-server.git

cd protege-server

mvn clean install
````

Now the server jar is needed by the protege client, so copy it to the
bundles:

````
cp target/protege-server-3.0.0-SNAPSHOT.jar ../protege/protege-desktop/target/protege-5.0.0-beta-22-SNAPSHOT-platform-independent/Protege-5.0.0-beta-22-SNAPSHOT/bundles
````

### Running

First start the server:

````
cd target/server-distribution/server

../run.sh
````

Now run protege:
````
cd
<my-top-level>/protege/protege-desktop/target/protege-5.0.0-beta-22-SNAPSHOT-platform-independent/Protege-5.0.0-beta-22-SNAPSHOT

./run.sh
````

When the app comes up, go into `Launcher/preferences` and select the
plugins tab. Change the registry url to:

````
https://raw.githubusercontent.com/bdionne/autoupdate/master/plugins.repository
````
Now under `File` select `Check for Plugins` and in there check the
lucene search and protege client plugins. After these load a restart
is required.
