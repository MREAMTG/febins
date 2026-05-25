#############
# GCC + GDB #
#############
ARG BUILD_IMAGE=ubuntu:focal
ARG PLATFORM=linux/amd64
ARG UID=1000
ARG GID=1000
ARG TZ="America/Toronto"
ARG GCC_VERSION=16.1.0
ARG GDB_VERSION=16.3
ARG FE_DIR="/opt/FactoryEngine"

FROM --platform=${PLATFORM} ${BUILD_IMAGE} AS cpp_build

ARG UID
ARG GID
ARG TZ
ARG GCC_VERSION
ARG GDB_VERSION
ARG FE_DIR

ENV UID=${UID} \
    GID=${GID} \
    TZ=${TZ} \
    GCC_VERSION=${GCC_VERSION} \
    GDB_VERSION=${GDB_VERSION} \
    FE_DIR=${FE_DIR} \
    APT_CMD="$(which apt-get)"

# ── Users & timezone ────────────────────────────────────────────────────────
RUN groupadd -o -g ${GID} factoryengine \
 && useradd -o -u ${UID} -g ${GID} -s /bin/sh -d /home/factoryengine -m factoryengine

RUN if [ -n "${APT_CMD}" ]; then \
      export DEBIAN_FRONTEND=noninteractive; \
      apt-get update && apt-get install -y --no-install-recommends tzdata; \
    fi

RUN echo "${TZ}" > /etc/timezone \
 && ln -fsn "/usr/share/zoneinfo/${TZ}" /etc/localtime \
 && if [ -n "${APT_CMD}" ]; then \
      DEBIAN_FRONTEND=noninteractive dpkg-reconfigure --frontend noninteractive tzdata; \
    fi

# ── All build dependencies (GCC + GDB combined) ──────────────────────────────
RUN if [ -n "${APT_CMD}" ]; then \
      export DEBIAN_FRONTEND=noninteractive; \
      apt-get update && apt-get install -y --no-install-recommends \
        autoconf libtool gettext bison dejagnu flex procps gobjc \
        libexpat1-dev libncurses5-dev libreadline-dev zlib1g-dev liblzma-dev \
        libbabeltrace-dev libxxhash-dev libmpfr-dev pkg-config python3-dev \
        build-essential git libgmp-dev texinfo python3 ca-certificates \
        make gawk libmpc-dev binutils perl tar gzip bzip2 curl \
        libisl-dev libzstd-dev; \
      apt-get install -y --no-install-recommends \
        libc-dbg source-highlight libsource-highlight-dev libdebuginfod-dev || true; \
      update-ca-certificates || true; \
    fi

RUN if [ -n "${APT_CMD}" ] && [ "$(uname -m)" = "x86_64" ]; then \
      apt-get install -y --no-install-recommends libipt-dev || true; \
    fi

# ── Output dir ───────────────────────────────────────────────────────────────
RUN mkdir -p "${FE_DIR}/gcc" "${FE_DIR}/gdb" /home/factoryengine/out \
 && chown -R ${UID}:${GID} "${FE_DIR}/gcc" "${FE_DIR}/gdb" /home/factoryengine/out

USER factoryengine
WORKDIR /home/factoryengine

# ── Clone GCC ────────────────────────────────────────────────────────────────
RUN if [ -n "${APT_CMD}" ]; then \
      git clone git://gcc.gnu.org/git/gcc.git \
        -b releases/gcc-${GCC_VERSION} --depth=1; \
    fi

# ── Build & install GCC ───────────────────────────────────────────────────────
ENV CONFIG_SHELL=/bin/bash
ENV PATH=${FE_DIR}/gcc/bin:${PATH}
ENV LD_LIBRARY_PATH=${FE_DIR}/gcc/lib64:${LD_LIBRARY_PATH}

WORKDIR /home/factoryengine/gcc
RUN if [ -n "${APT_CMD}" ]; then ./contrib/download_prerequisites; fi
RUN mkdir -p build

WORKDIR /home/factoryengine/gcc/build
RUN if [ -n "${APT_CMD}" ]; then \
      if [ "$(uname -m)" = "x86_64" ]; then \
        SPECIAL_FLAGS=""; LOCAL_TRIPLET="x86_64"; \
      else \
        SPECIAL_FLAGS="--enable-fix-cortex-a53-843419"; LOCAL_TRIPLET="aarch64"; \
      fi; \
      gccMajorVersion="$(echo ${GCC_VERSION} | cut -d. -f1)"; \
      ../configure \
        --enable-languages=c,c++,fortran \
        --prefix=${FE_DIR}/gcc \
        --disable-multilib \
        --disable-multi-arch \
        --program-suffix=-${gccMajorVersion} \
        --host=${LOCAL_TRIPLET}-linux-gnu \
        --target=${LOCAL_TRIPLET}-linux-gnu \
        --disable-werror \
        --enable-checking=release \
        --enable-clocale=gnu \
        --enable-default-pie \
        --enable-gnu-unique-object \
        --enable-libphobos-checking=release \
        --enable-libstdcxx-debug \
        --enable-libstdcxx-time=yes \
        --enable-linker-build-id \
        --enable-nls \
        --enable-plugin \
        --enable-shared \
        --enable-threads=posix \
        --with-default-libstdcxx-abi=new \
        --with-gcc-major-version-only ${SPECIAL_FLAGS}; \
    fi
RUN if [ -n "${APT_CMD}" ]; then make -j$(nproc); fi
RUN if [ -n "${APT_CMD}" ]; then make install; fi

# ── Clone GDB ────────────────────────────────────────────────────────────────
WORKDIR /home/factoryengine
RUN if [ -n "${APT_CMD}" ]; then \
      git clone https://sourceware.org/git/binutils-gdb.git \
        -b gdb-${GDB_VERSION}-release --depth=1; \
    fi

# ── Build & install GDB ───────────────────────────────────────────────────────
WORKDIR /home/factoryengine/binutils-gdb
RUN mkdir -p build

WORKDIR /home/factoryengine/binutils-gdb/build
RUN if [ -n "${APT_CMD}" ]; then \
      if [ -f /etc/os-release ] \
        && grep -q "Ubuntu" /etc/os-release \
        && grep -q "26" /etc/os-release; then \
          echo "Ubuntu 26 detected"; \
          ../configure --prefix=${FE_DIR}/gdb \
            --disable-gprofng \
            --with-auto-load-dir=\$debugdir:\$datadir/auto-load \
            --with-auto-load-safe-path=${FE_DIR}/gcc/lib64:\$debugdir:\$datadir/auto-load; \
      else \
          ../configure --prefix=${FE_DIR}/gdb \
            --with-auto-load-dir=\$debugdir:\$datadir/auto-load \
            --with-auto-load-safe-path=${FE_DIR}/gcc/lib64:\$debugdir:\$datadir/auto-load; \
      fi; \
    fi
RUN if [ -n "${APT_CMD}" ]; then make -j$(nproc); fi
RUN if [ -n "${APT_CMD}" ]; then make install; fi

# ── Package both artifacts ────────────────────────────────────────────────────
WORKDIR ${FE_DIR}/gdb
RUN if [ -n "${APT_CMD}" ]; then \
      tar cvf - . | gzip -9 - > \
        "/home/factoryengine/out/gdb-${GDB_VERSION}-$(grep '^ID=' /etc/os-release | awk -F'=' '{print $2}')_$(grep -oP '^VERSION=\"\d+.*$' /etc/os-release | sed -n 's/VERSION=\"\([0-9]*\).*/\1/p')_$(uname -m).tar.gz"; \
    fi

WORKDIR ${FE_DIR}/gcc
RUN if [ -n "${APT_CMD}" ]; then \
      tar cvf - . | gzip -9 - > \
        "/home/factoryengine/out/gcc-${GCC_VERSION}-$(grep '^ID=' /etc/os-release | awk -F'=' '{print $2}')_$(grep -oP '^VERSION=\"\d+.*$' /etc/os-release | sed -n 's/VERSION=\"\([0-9]*\).*/\1/p')_$(uname -m).tar.gz"; \
    fi

WORKDIR /home/factoryengine
