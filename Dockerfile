FROM ubuntu:20.04

ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=America/Chicago

# linux build dependencies
RUN apt-get update \
	&& apt-get -y install --no-install-recommends \
        autoconf \
        automake \
        bc \
        bison \
        cpio \
        curl \
        debhelper \
        default-jdk-headless \
        dh-systemd \
        dkms \
        flex \
        gawk \
        java-common \
        kernel-wedge \
        kmod \
        libaudit-dev \
        libdw-dev \
        libelf-dev \
        libiberty-dev \
        liblzma-dev \
        libncurses-dev \
        libnewt-dev \
        libnuma-dev \
        libpci-dev \
        libssl-dev \
        libtool \
        libudev-dev \
        libunwind8-dev \
        lsb-release \
        makedumpfile \
        openssl \
        pkg-config \
        python-dev \
        python3 \
        python3-apt \
        rsync \
        uuid-dev

# these are some utilities we might need
RUN apt-get update \
	&& apt-get -y install --no-install-recommends \
        gnupg2 \
        libfile-find-rule-perl \
        procps \
        squashfs-tools \
        unzip \
        vim-tiny \
        wget \
        xz-utils \
	&& apt-get -y install --reinstall ca-certificates \
	&& rm -rf /var/lib/apt/lists/*

ENV OUTPUT_DIR=/output
ENV UNRAID_VERSION=6.9.2
ENV FORCE=false
ENV UNRAID_DL_URL=https://unraid-dl.sfo2.cdn.digitaloceanspaces.com
ENV CPU_COUNT=all

RUN ulimit -n 2048

COPY ./get-modules.pl /opt/scripts/get-modules.pl
COPY ./build.sh /opt/scripts/build.sh

RUN chmod -R 770 /opt/scripts/

ENTRYPOINT [ "/opt/scripts/build.sh" ]

