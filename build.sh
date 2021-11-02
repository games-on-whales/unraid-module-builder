#!/bin/bash

# exit codes:
# 1: failed to download the stock images
# 2: did not find bzroot in the downloaded unRAID package
# 3: downloading a file failed
# 4: checksum mismatch on downloaded unRAID image
# 5: signature validation failed on linux kernel

set -e

SRC_DIR=/usr/src
if [ ! -d $OUTPUT_DIR ]; then
    mkdir -p $OUTPUT_DIR
fi

# is stdout a terminal?
if test -t 1; then
    # does it support colors?
    ncolors=$(tput colors)

    if test -n "$ncolors" && test $ncolors -ge 8; then
        bold="$(tput bold)"
        underline="$(tput smul)"
        standout="$(tput smso)"
        normal="$(tput sgr0)"

        black="$(tput setaf 0)"
        red="$(tput setaf 1)"
        green="$(tput setaf 2)"
        yellow="$(tput setaf 3)"
        blue="$(tput setaf 4)"
        magenta="$(tput setaf 5)"
        cyan="$(tput setaf 6)"
        white="$(tput setaf 7)"

        bright_black="$(tput setaf 8)"
        bright_red="$(tput setaf 9)"
        bright_green="$(tput setaf 10)"
        bright_yellow="$(tput setaf 11)"
        bright_blue="$(tput setaf 12)"
        bright_magenta="$(tput setaf 13)"
        bright_cyan="$(tput setaf 14)"
        bright_white="$(tput setaf 15)"
    fi
fi

# TODO: q/d log levels
function error {
    echo -n "${bright_red}ERROR${normal}   │ " >&2
    echo $* >&2
}

function warn {
    echo -n "${yellow}WARNING${normal} │ " >&2
    echo $* >&2
}

function info {
    echo -n "${blue}INFO${normal}    │ " >&2
    echo $*
}

function debug {
    echo -n "${white}DEBUG${normal}   │ " >&2
    echo $*
}

function fetch() {
    local dest=$1
    local url=$2

    local file=$(basename "$url")

    if [ -z "$file" ] || [ ! -s "/cache/$file" ]; then
        wget -q -nc --show-progress --progress=bar:force:noscroll -O "/cache/$file" "$url"
    else
        debug "Using cached file $file"
    fi

    if [ ! -s "/cache/$file" ]; then
        error "Failed to download $file"
        exit 3
    fi

    cp "/cache/$file" "$dest"
}

function get_branch() {
    local archive=$1

    local d='[[:digit:]]'
    local ver="$d+\.$d+\.$d+"
    local tag="(alpha|beta|rc)$d+"

    local branch=stable
    if [[ $archive =~ -$ver-$tag- ]]; then
        branch=next
    fi

    echo $branch
}

function fetch_unraid_img() {
    local version=$1
    local location=$2

    if [ -d $location ]; then
        if [ "$FORCE" != "true" ]; then
            error "Stock unRAID images were found to already exist. If you want to delete them and continue, set the FORCE variable to 'true'"
        else
            warn "Stock unRAID images were found to already exist. Removing them..."
            rm -rf $location
        fi
    fi

    info "Downloading stock unRAID v${UNRAID_VERSION}..."

    mkdir -p $location
    cd $location

    local archive=unRAIDServer-${UNRAID_VERSION}-x86_64.zip

    local branch=$(get_branch "$archive")
    local download_url=$UNRAID_DL_URL/${branch:-stable}/$archive

    if fetch "$location/$archive" "$download_url" ; then
        debug "Package downloaded"
    else
        error "Failed to download stock unRAID v${UNRAID_VERSION}, exiting"
        exit 1
    fi

    unzip -o $location/$archive bzroot\* bzfirmware\* &>/dev/null
    # Don't need the -gui image
    rm -f bzroot-gui*

    # Verify the hashes
    for image in bzroot bzfirmware; do
        local download_sum=$(cat $image.sha256)
        local calc_sum=$(sha256sum $image | cut -d' ' -f 1)

        if [ "$download_sum" != "$calc_sum" ]; then
            error "Checksum mismatch: $image"
            exit 4
        fi
    done

    # Extract the bzroot package
    info "Extracting bzroot; this may take a while..."
    if [ ! -d $location/root ]; then
        mkdir $location/root
    fi

    if [ ! -f $location/bzroot ] || [ ! -f $location/bzfirmware ]; then
        error "Couldn't find stock bzroot"
        exit 2
    fi

    cd $location/root
    local bzroot=$location/bzroot

    dd if=$bzroot bs=512 skip=$(cpio -ivt -H newc < $bzroot 2>&1 > /dev/null | awk '{print $1}') 2>/dev/null | xzcat | cpio -i -d -H newc --no-absolute-filenames &>/dev/null

    # TODO: it doesn't seem like a good plan to forcibly remove modules from
    # the container like this... this could use some more investigation

    # make room for the modules and firmware
    for dir in /lib/modules /lib/firmware; do
        if [ -d $dir ]; then
            rm -rf $dir
        fi
        mkdir $dir
    done

    unsquashfs -f -d /lib/firmware $location/bzfirmware &>/dev/null

    info "Extraction complete!"
}

function fetch_kernel_tarball() {
    local version=$1
    local dest=$2
    local major_ver="$(echo $version | cut -d '.' -f 1)"
    local kernel_tarball=linux-$version.tar.gz
    local kernel_sign=linux-$version.tar.sign

    # Get the keys that can be used to verify the signature
    gpg2 --locate-keys torvalds@kernel.org gregkh@kernel.org &>/dev/null

    info "Fetching kernel v$version"
    fetch "/tmp/$kernel_tarball" "https://mirrors.edge.kernel.org/pub/linux/kernel/v$major_ver.x/$kernel_tarball"
    fetch "/tmp/$kernel_sign" "https://mirrors.edge.kernel.org/pub/linux/kernel/v$major_ver.x/$kernel_sign"

    # verify the signature
    gunzip /tmp/$kernel_tarball
    kernel_tarball=$(basename "$kernel_tarball" ".gz")

    if ! gpg2 --verify /tmp/$kernel_sign &>/dev/null; then
        error "Couldn't verify kernel signature"
        exit 5
    fi

    info "Extracting kernel; this may take a bit"

    tar -C $dest --strip-components=1 -xf /tmp/$kernel_tarball
}

if [ ! -d /cache ]; then
    mkdir /cache
fi

## Set build variables
if [ "$CPU_COUNT" == "all" ];then
	CPU_COUNT="$(grep -c ^processor /proc/cpuinfo)"
	debug "Setting compile cores to $CPU_COUNT"
else
	debug "Setting compile cores to $CPU_COUNT"
fi

# Download the stock unRAID images so we can get their kernel patches
stock_dir="${SRC_DIR}/stock/${UNRAID_VERSION}"
fetch_unraid_img "${UNRAID_VERSION}" "$stock_dir"

# Work out which version of the kernel we're building now
KERNEL_VERSION_STR="$(ls $stock_dir/root/usr/src/ | cut -d '-' -f2,3 | cut -d '/' -f1)"
KERNEL_VERSION="$(echo $KERNEL_VERSION_STR | cut -d '-' -f 1)"

if [ "${KERNEL_VERSION##*.}" == "0" ]; then
	KERNEL_VERSION="${KERNEL_VERSION%.*}"
fi

# Download the matching kernel source tarball
cd ${SRC_DIR}
kernel_dir=${SRC_DIR}/linux-$KERNEL_VERSION_STR

if [ ! -d $kernel_dir ]; then
	mkdir $kernel_dir
fi

fetch_kernel_tarball "$KERNEL_VERSION" "$kernel_dir"

info "Copying unRAID config and patches to kernel source"
stock_kernel_dir=$stock_dir/root/usr/src/linux-$KERNEL_VERSION_STR
rsync -aq "$stock_kernel_dir/" $kernel_dir

info "Applying custom configuration"
KCONFIG_CONFIG=$kernel_dir/.config $kernel_dir/scripts/kconfig/merge_config.sh -m $stock_kernel_dir/.config /config/*.config

info "Applying kernel patches..."
cd $kernel_dir
find . -type f -iname '*.patch' -print0 | xargs -n1 -0 patch -p1 -i

info "Starting kernel build"
make oldconfig
make -j${CPU_COUNT}

info "Building modules"
make -j${CPU_COUNT} modules_install

config_items=$(grep -hoP 'CONFIG_[A-Z_]+(?==m)' /config/*.config)
for mod in $(/opt/scripts/get-modules.pl "$kernel_dir" "$KERNEL_VERSION_STR" $config_items); do
    cp --parents /lib/modules/$KERNEL_VERSION_STR/$mod $OUTPUT_DIR
done

info "Build complete!"


