# NCI Protege 5

NCI Protege 5 is the port of NCI's terminology tools from protege 3.4
to Protege 5.0. This is a collaboration between NCI, Stanford University, and
Clark&Parsia, LLC.

This repository is a place for various scripts, notes, etc.. that
pulls together work from several repositories, [nci-edit-tab][1],
[metaproject][2], [protege-client][3], [protege-server][4],
[lucene-search-plugin][5], [pellet server][7], and [protege][6] itself.

## Build

To build, a simple [script][8] can be executed, .eg.:

````
cd scripts

./build.sh nci-1.0081 ncievs

````
where `nci-1.0081` is a tag, and `ncievs` is the name of the GitHub you wish to build from.

This will pull all the code from the various repositories and run maven. If successful, it
will produce a directory named `nci-protege5` in which there will also
be a zip file named `nci-protege5-<today's date>`.

This zip contains two scripts:

````
./run-server.sh
````

and

````
./run_protege.sh
````

The first starts the server and the second will run the editor. A
small sample database is included with the server.

## Releases

The branches of these repositories being worked on change from time to time, so we're
producing daily [releases][9]. The releases include the `zip` file, so
one can just download those and they should run on most
platforms. Each release is based on a tag of this repository so if
there are questions about which code was included the source scripts
can be downloaded and run locally




----
[1]: https://github.com/bdionne/nci-edit-tab
[2]: https://github.com/bdionne/metaproject
[3]: https://github.com/bdionne/protege-client
[4]: https://github.com/bdionne/protege-server

[5]: https://github.com/bdionne/lucene-search-plugin
[6]: https://github.com/bdionne/protege
[7]: https://github.com/Complexible/pellet/tree/service
[8]: https://github.com/NCIEVS/nci-protege5/blob/master/scripts/build.sh
[9]: https://github.com/NCIEVS/nci-protege5/releases
