ARG BUILD_IMAGE=ubuntu:focal
ARG PLATFORM=linux/amd64
ARG UID=1000
ARG GID=1000
ARG TZ="America/Toronto"
ARG FE_DIR="/opt/FactoryEngine"
ARG GCC_VERSION=16.1.0
ARG GDB_VERSION=17.1

###############
# setup_build #
###############
FROM --platform=${PLATFORM} ${BUILD_IMAGE} AS setup_build

ARG UID
ARG GID
ARG TZ
ARG FE_DIR

ENV UID=${UID} \
    GID=${GID} \
    TZ=${TZ} \
    FE_DIR=${FE_DIR}

RUN if command -v apk >/dev/null 2>&1; then \
      addgroup -g ${GID} factoryengine \
      && adduser -u ${UID} -D -G factoryengine -h /home/factoryengine -s /bin/sh factoryengine; \
    else \
      groupadd -o -g ${GID} factoryengine \
      && useradd -o -u ${UID} -g ${GID} -s /bin/sh -d /home/factoryengine -m factoryengine; \
    fi

RUN if command -v apt-get >/dev/null 2>&1; then \
      export DEBIAN_FRONTEND=noninteractive; \
      apt-get update && apt-get install -y --no-install-recommends tzdata; \
    elif command -v apk >/dev/null 2>&1; then \
      apk add --no-cache tzdata; \
    elif command -v yum >/dev/null 2>&1; then \
      yum install -y tzdata; \
    elif command -v dnf >/dev/null 2>&1; then \
      dnf install -y tzdata; \
    fi

RUN echo "${TZ}" > /etc/timezone \
 && ln -fsn "/usr/share/zoneinfo/${TZ}" /etc/localtime \
 && if command -v apt-get >/dev/null 2>&1; then \
      DEBIAN_FRONTEND=noninteractive dpkg-reconfigure --frontend noninteractive tzdata; \
    fi

RUN mkdir -p "${FE_DIR}" /home/factoryengine/out \
 && chown ${UID}:${GID} "${FE_DIR}" /home/factoryengine/out

#######
# GCC #
#######
FROM setup_build AS gcc_build

ARG GCC_VERSION

ENV GCC_VERSION=${GCC_VERSION}

RUN if command -v apt-get >/dev/null 2>&1; then \
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

RUN if command -v apt-get >/dev/null 2>&1 && [ "$(uname -m)" = "x86_64" ]; then \
      apt-get install -y --no-install-recommends libipt-dev || true; \
    fi

RUN mkdir -p "${FE_DIR}/gcc" && chown -R ${UID}:${GID} "${FE_DIR}/gcc"

USER factoryengine
WORKDIR /home/factoryengine

RUN if command -v apt-get >/dev/null 2>&1; then \
      git clone git://gcc.gnu.org/git/gcc.git \
        -b releases/gcc-${GCC_VERSION} --depth=1; \
    fi

ENV CONFIG_SHELL=/bin/bash
ENV PATH=${FE_DIR}/gcc/bin:${PATH}
ENV LD_LIBRARY_PATH=${FE_DIR}/gcc/lib64:${LD_LIBRARY_PATH}

WORKDIR /home/factoryengine/gcc
RUN if command -v apt-get >/dev/null 2>&1; then ./contrib/download_prerequisites; fi
RUN mkdir -p build

WORKDIR /home/factoryengine/gcc/build
RUN if command -v apt-get >/dev/null 2>&1; then \
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
RUN if command -v apt-get >/dev/null 2>&1; then make -j$(nproc); fi
RUN if command -v apt-get >/dev/null 2>&1; then make install; fi

RUN if command -v apt-get >/dev/null 2>&1; then \
      gccMajorVersion="$(echo ${GCC_VERSION} | cut -d. -f1)"; \
      ln -sf "${FE_DIR}/gcc/bin/gcc-${gccMajorVersion}" "${FE_DIR}/gcc/bin/gcc"; \
      ln -sf "${FE_DIR}/gcc/bin/g++-${gccMajorVersion}" "${FE_DIR}/gcc/bin/g++"; \
      ln -sf "${FE_DIR}/gcc/bin/cpp-${gccMajorVersion}" "${FE_DIR}/gcc/bin/cpp" || true; \
    fi

#######
# GDB #
#######
FROM gcc_build AS gdb_build

ARG GDB_VERSION

ENV GDB_VERSION=${GDB_VERSION}

USER root
RUN mkdir -p "${FE_DIR}/gdb" && chown -R ${UID}:${GID} "${FE_DIR}/gdb"
USER factoryengine

RUN if command -v apt-get >/dev/null 2>&1; then \
      git clone https://sourceware.org/git/binutils-gdb.git \
        -b gdb-${GDB_VERSION}-release --depth=1; \
    fi

WORKDIR /home/factoryengine/binutils-gdb
RUN mkdir -p build

WORKDIR /home/factoryengine/binutils-gdb/build
RUN if command -v apt-get >/dev/null 2>&1; then \
      if [ -f /etc/os-release ] \
        && grep -q "Ubuntu" /etc/os-release \
        && grep -q "26" /etc/os-release; then \
          CC="${FE_DIR}/gcc/bin/gcc" CXX="${FE_DIR}/gcc/bin/g++" \
          ../configure --prefix=${FE_DIR}/gdb \
            --disable-gprofng \
            --with-auto-load-dir=\$debugdir:\$datadir/auto-load \
            --with-auto-load-safe-path=${FE_DIR}/gcc/lib64:\$debugdir:\$datadir/auto-load; \
      else \
          CC="${FE_DIR}/gcc/bin/gcc" CXX="${FE_DIR}/gcc/bin/g++" \
          ../configure --prefix=${FE_DIR}/gdb \
            --with-auto-load-dir=\$debugdir:\$datadir/auto-load \
            --with-auto-load-safe-path=${FE_DIR}/gcc/lib64:\$debugdir:\$datadir/auto-load; \
      fi; \
    fi
RUN if command -v apt-get >/dev/null 2>&1; then make -j$(nproc); fi
RUN if command -v apt-get >/dev/null 2>&1; then make install; fi

# ── Package GDB artifact ──────────────────────────────────────────────────────
WORKDIR ${FE_DIR}/gdb
RUN if command -v apt-get >/dev/null 2>&1; then \
      tar cvf - . | gzip -9 - > \
        "/home/factoryengine/out/gdb-${GDB_VERSION}-$(grep '^ID=' /etc/os-release | awk -F'=' '{print $2}')_$(grep -oP '^VERSION_ID=\"[0-9]+.*$' /etc/os-release | sed -n 's/VERSION_ID=\"\([0-9]*\).*/\1/p')_$(uname -m).tar.gz"; \
    fi

WORKDIR /home/factoryengine
