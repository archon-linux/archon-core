# Core packages for the Archon Linux ISO
## Building the packages

The scripts expect this repository folder `archon-core` to be in the same root folder as the `archon-repo` folder.

I suggest making an `archon-linux` folder and cloning [archon-iso](https://github.com/archon-linux/archon-iso), [archon-core](https://github.com/archon-linux/archon-core) and [archon-repo](https://github.com/archon-linux/archon-repo) inside of it. But if you are going through that trouble, you should be doing this with your own forks so you can save changes and even offer pull requests ;)

You can build a single package by running `./build.sh` in each folder, or build all of them with `./build.sh` at the root of the project. They will be moved to the `archon-repo/x86_64` folder once built, so don't forget to rebuild the repository when done with `./build.sh` in `archon-repo`.

## archon-aur
`aurpackages` has a list of all the AUR packages we will need when building the iso.
## archon-grub-theme
Custom grub theme.
## archon-gtk3-themes
Dynamic gtk3 themes to change colors with `flavours`. Also has the skel files to set those themes as default.
## archon-system

The issue I ran into was of course file conflicts. I only had the issue for a few files but it was key ones. When the iso is being built if my `archon-system` package also had a `/etc/lightdm/lightdm.conf` file with my changes it would conflict with the one from the `lightdm` package.

How I dealt with that initially was by bloating the `airootfs` folders with those files that would conflict and remove them from my package as the `airootfs` files take precendence and will not conflict during the build. There is no problem with doing that but that was not my *plan*, I wanted clean packages that had the proper configs, which would make things much easier to maintain and develop.

My next take on it was to compile my own `lightdm` package with my defaults and that would have been fine as well. But compiling my own package just for a config file seemed overkill and that also moved the config file away from my `archon-system` package, so I did not like it either.

Then I tried something else, compiling the package without the config files which solved them being moved away from my custom config packages, but still, compiling my own version of `grub` and `bash` for a config seemed silly. Keeping up this readme 'blog' helped rubber ducky debug those choices and I came up with this solution.

I had only a few files that had the issue, but more could come along the way so I settled on using scripts to fix my configs.

I have my custom packages `PKGBUILD` rename my conflicting configs to `original_name.archon` in order to avoid the file conflicts, and they keep their proper names in the packages code repositories.

`archon-system` package, sets up a new service that gets run before the user login at boot and starts the `before_login.sh` scripts.

I use this script to fix all the things required for the live boot. This includes replacing `pacman.conf`, `pamac.conf` and `lightdm.conf` with the `.archon` ones that came from our packages. Then fixing the default cursor, and creating the default xdg directories, I did not like the capitalized names so mine are called `documents`, `downloads` and so on. Small things, but very much needed for a semi-proper live environment experience. The goal is not to make a complete mirror of the installed system in the live boot, but something close to it and useable. As we'll see a lot will happen still after the first boot on the installed system.

Now comes the post installation scripts. `post_install.sh` is started by calamares at the end of the install process, in a normal non-chrooted environment. It is mainly used to detect the current graphics card to remove unsued drives under chroot later and copies over the `stub-resolv.conf` to have network access under chroot.

Once that is done it starts the `chrooted_post_install.sh` script. This is a big boy and very important. It removes unused packages, starts and cleans up services, such as removing our `before_login.service` and script, cleans up the graphics and vm drivers, removes autologin from display managers configs, setup snapshots for snapper, and once again does the same config fixes `before_login.sh` did along with a few other tweaks for the installed system such as `zramd` settings.

And that is how I eneded up dealing with conflicts while keeping clean looking packages.

I made the choice to include the `calamares-config` files in `archon-system` as it was also in charge of system setup.

All of those post install changes were system wide, but we need to finalize our user home folder with a few more things. I could have done it all in the `chrooted_post_install.sh` script but that would have made it a really single user system, so thats why most distros have a welcome app to setup user specific changes that can be run again by newly created user.

I chose to use `ansible` for that as it's part of my regular workflow and it does the job. I know I am taking a gun to a knife fight :) So until you run a task once or any time you type `archon` a welcome script will start that will finalize the installation.

I highly suggest running all the tasks, expect things to be half broken if you dont. Check [archon-iso](https://github.com/archon-linux/archon-iso) for more info.

## archon-wallpapers

A short selection of wallpapers, will grow over time.
## calamares

Simply builds the calamares release we want from their git repository.

## chaotic-aur

Package the mirrorlist and keyring into the `archon-repo/x86_64` folder.
