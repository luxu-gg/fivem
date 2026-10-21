FROM alpine:3.16

# Architecture of the Alpine rootfs used as the build environment (x86_64 or aarch64).
# Override with `--build-arg ALPINE_ARCH=aarch64` when building the image on/for arm64.
ARG ALPINE_ARCH=x86_64

# Set the working directory in the container
RUN mkdir -p /app
WORKDIR /app

# Update local package lists and install necessary packages
RUN apk update && apk add --no-cache \
    curl git xz sudo rsync openssh-client binutils build-base pkgconfig \
    libarchive-dev talloc-dev uthash-dev linux-headers musl-dev \
    bsd-compat-headers dotnet6-sdk

# Configure git
RUN git config --global safe.directory '*'

# Get an Alpine rootfs
RUN curl -sLo alpine-minirootfs-3.16.5-${ALPINE_ARCH}.tar.gz https://dl-cdn.alpinelinux.org/alpine/v3.16/releases/${ALPINE_ARCH}/alpine-minirootfs-3.16.5-${ALPINE_ARCH}.tar.gz

# Extract the rootfs into /alpine folder
RUN mkdir alpine && tar -xzf alpine-minirootfs-3.16.5-${ALPINE_ARCH}.tar.gz -C alpine && rm alpine-minirootfs-3.16.5-${ALPINE_ARCH}.tar.gz

# Create necessary directories inside the Alpine environment
RUN mkdir -p alpine/src alpine/fivem-private

# Ensure the resolv.conf file exists and set DNS servers
RUN echo "nameserver 1.1.1.1" > alpine/etc/resolv.conf && \
    echo "nameserver 8.8.8.8" >> alpine/etc/resolv.conf

# Clone and build proot
# TODO(arm64): the 32-bit `loader-m32.elf` target only builds on x86; skip it for aarch64 images.
RUN git clone https://github.com/proot-me/proot.git && \
    cd proot && \
    make -C src loader.elf loader-m32.elf build.h && \
    make -C src proot care && \
    cp src/proot /usr/local/bin/proot && \
    cd .. && rm -rf proot

# Copy the preparation script into the Alpine environment
COPY code/tools/ci/docker-builder/proot_prepare.sh /app/alpine/utils/proot_prepare.sh

# aarch64: the mono runtime comes from a tarball instead of the cfx apk repository (see arm64/README.md);
# drop mono-5.16.1.0-r9991-aarch64-musl.tar.xz into code/tools/ci/docker-builder/arm64/ before building
COPY code/tools/ci/docker-builder/arm64/ /app/alpine/utils/arm64/

# Run the preparation script using PRoot inside the Alpine environment
RUN /usr/local/bin/proot \
    --kill-on-exit \
    -b /dev:/dev \
    -b /sys:/sys \
    -b /proc:/proc \
    -b /tmp:/tmp \
    -b /root:/root \
    -R /app/alpine /bin/sh /utils/proot_prepare.sh
