# NCI Protege 5

## Build

# NCI Protege Metaproject GUI

## Build

These simple steps enable the building of Protege 5, the client and
server, and the metaproject GUI.

### Protege 5

Start with a top level directory to make clean up easier:

````
mkdir <my-top-level>

cd <my-top-level>

git clone https://github.com/protegeproject/protege.git

cd protege/

git checkout 5.0.0

mvn clean install

````

### Metaproject

````
cd ..

git clone https://github.com/bdionne/metaproject.git

cd metaproject

mvn clean install

````

### Protege Server

````
cd ../

git clone https://github.com/bdionne/protege-server.git

cd protege-server/

git checkout -b metaproject-integration origin/metaproject-integration

mvn clean install
````

### Protege Client

````
cd ..

git clone https://github.com/bdionne/protege-client.git

cd protege-client/

git checkout -b metaproject-integration-edittab origin/metaproject-integration-edittab

mvn clean install
````



Now the client/server jars are needed by the protege client, so copy them to the
bundles:

````
cp target/protege-client-3.0.0-SNAPSHOT.jar
../protege/protege-desktop/target/protege-5.0.0-beta-22-SNAPSHOT-platform-independent/Protege-5.0.0-beta-22-SNAPSHOT/bundles

cd ../protege-server

cp target/protege-server-3.0.0-SNAPSHOT.jar
../protege/protege-desktop/target/protege-5.0.0-beta-22-SNAPSHOT-platform-independent/Protege-5.0.0-beta-22-SNAPSHOT/bundles

````

### Running

First start the server:

````
cd <my-top-level>/protege-server/target/server-distribution/server

../run.sh
````

Now run protege:
````
cd
<my-top-level>/protege/protege-desktop/target/protege-5.0.0-beta-22-SNAPSHOT-platform-independent/Protege-5.0.0-beta-22-SNAPSHOT

./run.sh
````

When the app comes up, use `File/OpenFromServer...`, connect and the
metaproject gui panel will be usable
