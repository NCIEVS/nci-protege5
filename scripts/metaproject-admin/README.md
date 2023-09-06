# Standalone Metaproject Admin App

The set of scripts in this directory enable the building of the protege metaproject admin plugin as a standalone application. They work almost the same way as the main build scripts.

Here is how to build it:

Checkout the nci-project5 repo:

````
git clone https://github.com/NCIEVS/nci-protege5.git

cd nci-protege5/scripts/metaproject-admin
````
Now execute the buid script specifying the tag to use and the github account to pull from:

````
./build-meta.sh meta-admin-1.0.0 ncievs
````
When this completes there will be a new subdirectory. Change to that:

````
cd meta-admin-app

````
Run the app:

````
./meta-admin.sh
````
This last script just runs the `run.sh` script that is installed in the protege directory as part of the build. That `run.sh` comes from the `run-meta-admin.sh` script that is in the top directory. This is the scripts that can be modified locally.
