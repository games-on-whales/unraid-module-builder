# Building Kernel Modules for unRAID

This is a Docker container that can build additional kernel modules for unRAID servers. Just give it one or more kernel config snippets and an unRAID version to build for, and it will produce an output folder containing all of the newly built modules.

```console
$ sudo docker --rm -it \
    -v /path/to/custom/config:/config \
    -v /path/to/output:/output \
    -e UNRAID_VERSION=6.9.2
    # optional:
    -v /path/to/download/cache:/cache \
    gameonwhales/unraid-module-builder
```

The image [`gameonwhales/unraid-module-builder`](https://hub.docker.com/r/gameonwhales/unraid-module-builder) is automatically generated using Github Actions, alternatively, you can build your own by cloning this repo.

## Inputs

`/path/to/config` should be a directory containing one or more files ending in `.config`.  These files should contain a snippet of configuration in the same format as the Linux kernel's `.config` file.  For example, to build the `uinput.ko` module, it might look like this:
```conf
CONFIG_INPUT_UINPUT=m
```

`/path/to/output` is simply a directory where the build script will put the generated modules once they're built.

`/path/to/download/cache` is a directory that can be used to cache downloaded files between runs, so they don't have to be redownloaded. This is optional; if you don't provide it, the files will simply be downloaded each time.

`UNRAID_VERSION` should be set to the version of unRAID you're building for.
