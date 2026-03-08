# --- STAGE 1: Base Environment & Dependencies ---
FROM debian:bookworm-slim AS lfs_base
RUN apt-get update && apt-get install -y \
    build-essential bison gawk texinfo wget python3 \
    && rm -rf /var/lib/apt/lists/*

ENV LFS=/mnt/lfs \
    LFS_TGT=x86_64-lfs-linux-gnu \
    PATH=/mnt/lfs/tools/bin:$PATH \
    MAKEFLAGS="-j$(nproc)"
WORKDIR /sources

# --- STAGE 2: Source Acquisition ---
FROM lfs_base AS lfs_sources
ENV BINUTILS_VER=2.41 \
    GCC_VER=13.2.0 \
    LINUX_VER=6.4.12 \
    GLIBC_VER=2.38 \
    BASH_VER=5.2.15 \
    COREUTILS_VER=9.3 \
    GMP_VER=6.3.0 \
    MPFR_VER=4.2.1 \
    MPC_VER=1.3.1

RUN wget https://ftp.gnu.org/gnu/binutils/binutils-${BINUTILS_VER}.tar.xz \
    https://ftp.gnu.org/gnu/gcc/gcc-${GCC_VER}/gcc-${GCC_VER}.tar.xz \
    https://www.kernel.org/pub/linux/kernel/v6.x/linux-${LINUX_VER}.tar.xz \
    https://ftp.gnu.org/gnu/glibc/glibc-${GLIBC_VER}.tar.xz \
    https://ftp.gnu.org/gnu/bash/bash-${BASH_VER}.tar.gz \
    https://ftp.gnu.org/gnu/coreutils/coreutils-${COREUTILS_VER}.tar.xz \
    https://ftp.gnu.org/gnu/gmp/gmp-${GMP_VER}.tar.xz \
    https://ftp.gnu.org/gnu/mpfr/mpfr-${MPFR_VER}.tar.xz \
    https://ftp.gnu.org/gnu/mpc/mpc-${MPC_VER}.tar.gz

# --- STAGE 3: Filesystem Setup ---
FROM lfs_sources AS lfs_filesystem
RUN mkdir -pv $LFS/bin $LFS/lib $LFS/sbin $LFS/tools \
    && mkdir -pv $LFS/usr/bin $LFS/usr/lib $LFS/usr/sbin $LFS/usr/include

# --- STAGE 4: Linux Headers ---
FROM lfs_filesystem AS build_headers
RUN tar -xf linux-*.tar.xz && cd linux-*/ && \
    make mrproper && make headers && \
    cp -rv usr/include/* $LFS/usr/include && \
    cd .. && rm -rf linux-*

# --- STAGE 5: Binutils Pass 1 ---
FROM build_headers AS build_binutils_1
RUN tar -xf binutils-*.tar.xz && mkdir binutils-build && cd binutils-build && \
    ../binutils-*/configure --prefix=$LFS/tools \
    --with-sysroot=$LFS --target=$LFS_TGT --disable-nls --enable-gprofng=no --disable-werror && \
    make && make install && \
    cd .. && rm -rf binutils-*

# --- STAGE 6: GCC Pass 1 (with GMP, MPFR, MPC) ---
FROM build_binutils_1 AS build_gcc_1
RUN tar -xf gcc-*.tar.xz && cd gcc-*/ && \
    tar -xf ../gmp-*.tar.xz && mv -v gmp-* gmp && \
    tar -xf ../mpfr-*.tar.xz && mv -v mpfr-* mpfr && \
    tar -xf ../mpc-*.tar.gz && mv -v mpc-* mpc && \
    mkdir build && cd build && \
    ../configure --target=$LFS_TGT --prefix=$LFS/tools --with-glibc-version=2.38 \
    --with-sysroot=$LFS --with-newlib --without-headers --enable-default-pie \
    --enable-default-ssp --disable-nls --disable-shared --disable-multilib \
    --disable-threads --disable-libatomic --disable-libgomp --disable-libquadmath \
    --disable-libssp --disable-libvtv --disable-libstdcxx --enable-languages=c,c++ && \
    make && make install && \
    cd ../.. && rm -rf gcc-*

# --- STAGE 7: Glibc ---
FROM build_gcc_1 AS build_glibc
RUN tar -xf glibc-*.tar.xz && mkdir glibc-build && cd glibc-build && \
    ../glibc-*/configure --prefix=/usr --host=$LFS_TGT --build=$(../glibc-*/scripts/config.guess) \
    --enable-kernel=4.14 --with-headers=$LFS/usr/include libc_cv_slibdir=/usr/lib && \
    make && make DESTDIR=$LFS install && \
    cd .. && rm -rf glibc-*

# --- STAGE 8: Bash ---
FROM build_glibc AS build_bash
RUN tar -xf bash-*.tar.gz && cd bash-*/ && \
    ./configure --prefix=/usr --build=$(support/config.guess) --host=$LFS_TGT --without-bash-malloc && \
    make && make DESTDIR=$LFS install && \
    ln -sv bash $LFS/bin/sh && \
    cd .. && rm -rf bash-*

# --- STAGE 9: Coreutils ---
FROM build_bash AS build_coreutils
RUN tar -xf coreutils-*.tar.xz && cd coreutils-*/ && \
    ./configure --prefix=/usr --host=$LFS_TGT --build=$(build-aux/config.guess) \
    --enable-install-program=hostname --enable-no-install-program=kill,uptime && \
    make && make DESTDIR=$LFS install && \
    cd .. && rm -rf coreutils-*

# --- STAGE 10: Final Runtime ---
FROM scratch
COPY --from=build_coreutils /mnt/lfs /
ENV PATH=/usr/bin:/bin:/usr/sbin:/sbin
CMD ["/bin/bash"]
