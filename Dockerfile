# --- STAGE 1: The Builder Environment ---
FROM debian:bookworm-slim AS builder

RUN apt-get update && apt-get install -y \
    build-essential bison gawk texinfo wget python3 \
    && rm -rf /var/lib/apt/lists/*

# Use ENV so these are available in all RUN instructions
ENV LFS=/mnt/lfs \
    LFS_TGT=x86_64-lfs-linux-gnu \
    PATH=/mnt/lfs/tools/bin:$PATH \
    MAKEFLAGS="-j$(nproc)"

WORKDIR /sources

# Define versions
ENV BINUTILS_VER=2.41 \
    GCC_VER=13.2.0 \
    LINUX_VER=6.4.12 \
    GLIBC_VER=2.38 \
    BASH_VER=5.2.15 \
    COREUTILS_VER=9.3

# Download sources
RUN wget https://ftp.gnu.org/gnu/binutils/binutils-${BINUTILS_VER}.tar.xz \
    https://ftp.gnu.org/gnu/gcc/gcc-${GCC_VER}/gcc-${GCC_VER}.tar.xz \
    https://www.kernel.org/pub/linux/kernel/v6.x/linux-${LINUX_VER}.tar.xz \
    https://ftp.gnu.org/gnu/glibc/glibc-${GLIBC_VER}.tar.xz \
    https://ftp.gnu.org/gnu/bash/bash-${BASH_VER}.tar.gz \
    https://ftp.gnu.org/gnu/coreutils/coreutils-${COREUTILS_VER}.tar.xz

# --- STAGE 2: Building the Toolchain ---
# FIX: Added usr/include to the initial directory creation
RUN mkdir -pv $LFS/bin $LFS/lib $LFS/sbin $LFS/tools \
    && mkdir -pv $LFS/usr/bin $LFS/usr/lib $LFS/usr/sbin $LFS/usr/include

# 1. Install Linux Headers (Added mkdir -p safety check)
RUN tar -xf linux-${LINUX_VER}.tar.xz && cd linux-${LINUX_VER} && \
    make mrproper && make headers && \
    find usr/include -type f ! -name '*.h' -delete && \
    mkdir -pv $LFS/usr/include && \
    cp -rv usr/include/* $LFS/usr/include

# 2. Build Binutils (Pass 1)
RUN tar -xf binutils-${BINUTILS_VER}.tar.xz && mkdir -v binutils-build && cd binutils-build && \
    ../binutils-${BINUTILS_VER}/configure --prefix=$LFS/tools \
    --with-sysroot=$LFS --target=$LFS_TGT --disable-nls --enable-gprofng=no --disable-werror && \
    make && make install

# 3. Build GCC (Pass 1)
RUN tar -xf gcc-${GCC_VER}.tar.xz && cd gcc-${GCC_VER} && \
    mkdir -v build && cd build && \
    ../configure --target=$LFS_TGT --prefix=$LFS/tools --with-glibc-version=2.38 \
    --with-sysroot=$LFS --with-newlib --without-headers --enable-default-pie \
    --enable-default-ssp --disable-nls --disable-shared --disable-multilib \
    --disable-threads --disable-libatomic --disable-libgomp --disable-libquadmath \
    --disable-libssp --disable-libvtv --disable-libstdcxx --enable-languages=c,c++ && \
    make && make install

# 4. Build Glibc
RUN tar -xf glibc-${GLIBC_VER}.tar.xz && mkdir -v glibc-build && cd glibc-build && \
    ../glibc-${GLIBC_VER}/configure --prefix=/usr --host=$LFS_TGT --build=$(../glibc-${GLIBC_VER}/scripts/config.guess) \
    --enable-kernel=4.14 --with-headers=$LFS/usr/include libc_cv_slibdir=/usr/lib && \
    make && make DESTDIR=$LFS install

# 5. Build Bash
RUN tar -xf bash-${BASH_VER}.tar.gz && cd bash-${BASH_VER} && \
    ./configure --prefix=/usr --build=$(support/config.guess) --host=$LFS_TGT --without-bash-malloc && \
    make && make DESTDIR=$LFS install && \
    ln -sv bash $LFS/bin/sh

# 6. Build Coreutils
RUN tar -xf coreutils-${COREUTILS_VER}.tar.xz && cd coreutils-${COREUTILS_VER} && \
    ./configure --prefix=/usr --host=$LFS_TGT --build=$(build-aux/config.guess) \
    --enable-install-program=hostname --enable-no-install-program=kill,uptime && \
    make && make DESTDIR=$LFS install

# --- STAGE 3: Final Runtime ---
FROM scratch
COPY --from=builder /mnt/lfs /
ENV PATH=/usr/bin:/bin:/usr/sbin:/sbin
CMD ["/bin/bash"]
