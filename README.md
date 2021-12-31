# Core packages for the Archon Linux ISO

The scripts expect this repository folder `archon-core` to be in the same folder as the `archon-repo` folder.

You can build a single package by running the `build.sh` in each folder, or build all of them with the `build.sh` at the root of the project.
## calamares

Simply build the calamares release we want from their git repository.

## calamares-config

Configuration for linux-zen kernel and btrfs by default. `post_install.sh` and `chrooted_post_install.sh` scripts are a key part of our installation, be sure to review those files.

## chaotic

Simply run the `chaotic-aur.sh` script to package the mirrorlist and keyring