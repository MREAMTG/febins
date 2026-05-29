ARG BUILD_IMAGE=ubuntu:focal
ARG PLATFORM=linux/amd64
ARG UID=1000
ARG GID=1000
ARG TZ="America/Toronto"
ARG FE_DIR="/opt/FactoryEngine"
ARG GCC_VERSION=16.1.0
ARG GDB_VERSION=16.3
ARG PYTHON_VERSION=3.11.13
ARG VALGRIND_VERSION="3.24.0"
ARG CMAKE_VERSION=3.31.12
ARG DOXYGEN_VERSION=1.17.0
ARG LLVM_VERSION=22

###############
# setup_build #
###############
# Common base inherited by all builder stages: user/group, timezone, and the
# base /opt/FactoryEngine and /home/factoryengine/out directories.
FROM --platform=${PLATFORM} ${BUILD_IMAGE} AS setup_build

ARG UID
ARG GID
ARG TZ
ARG FE_DIR

ENV UID=${UID} \
    GID=${GID} \
    TZ=${TZ} \
    FE_DIR=${FE_DIR}

# ── User & group ──────────────────────────────────────────────────────────────
RUN if command -v apk >/dev/null 2>&1; then \
      addgroup -g ${GID} factoryengine \
      && adduser -u ${UID} -D -G factoryengine -h /home/factoryengine -s /bin/sh factoryengine; \
    else \
      groupadd -o -g ${GID} factoryengine \
      && useradd -o -u ${UID} -g ${GID} -s /bin/sh -d /home/factoryengine -m factoryengine; \
    fi

# ── Timezone ──────────────────────────────────────────────────────────────────
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

# ── Base directories ──────────────────────────────────────────────────────────
RUN mkdir -p "${FE_DIR}" /home/factoryengine/out \
 && chown ${UID}:${GID} "${FE_DIR}" /home/factoryengine/out

#######
# GCC #
#######
FROM setup_build AS gcc_build

ARG GCC_VERSION

ENV GCC_VERSION=${GCC_VERSION}

# ── Build dependencies ───────────────────────────────────────────────────────
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

# ── GCC output dir ───────────────────────────────────────────────────────────
RUN mkdir -p "${FE_DIR}/gcc" && chown -R ${UID}:${GID} "${FE_DIR}/gcc"

USER factoryengine
WORKDIR /home/factoryengine

# ── Clone GCC ────────────────────────────────────────────────────────────────
RUN if command -v apt-get >/dev/null 2>&1; then \
      git clone git://gcc.gnu.org/git/gcc.git \
        -b releases/gcc-${GCC_VERSION} --depth=1; \
    fi

# ── Build & install GCC ───────────────────────────────────────────────────────
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

# ── Unversioned symlinks so downstream stages can call gcc/g++ directly ───────
RUN if command -v apt-get >/dev/null 2>&1; then \
      gccMajorVersion="$(echo ${GCC_VERSION} | cut -d. -f1)"; \
      ln -sf "${FE_DIR}/gcc/bin/gcc-${gccMajorVersion}" "${FE_DIR}/gcc/bin/gcc"; \
      ln -sf "${FE_DIR}/gcc/bin/g++-${gccMajorVersion}" "${FE_DIR}/gcc/bin/g++"; \
      ln -sf "${FE_DIR}/gcc/bin/cpp-${gccMajorVersion}" "${FE_DIR}/gcc/bin/cpp" || true; \
    fi

# ── Package GCC artifact ──────────────────────────────────────────────────────
WORKDIR ${FE_DIR}/gcc
RUN if command -v apt-get >/dev/null 2>&1; then \
      tar cvf - . | gzip -9 - > \
        "/home/factoryengine/out/gcc-${GCC_VERSION}-$(grep '^ID=' /etc/os-release | awk -F'=' '{print $2}')_$(grep -oP '^VERSION_ID=\"\d+.*$' /etc/os-release | sed -n 's/VERSION_ID=\"\([0-9]*\).*/\1/p')_$(uname -m).tar.gz"; \
    fi

WORKDIR /home/factoryengine

#######
# GDB #
#######

# Build GDB on top of gcc_build: inherits the installed GCC, all build
# dependencies, PATH, and LD_LIBRARY_PATH — no reinstall needed.
FROM gcc_build AS gdb_build

ARG GDB_VERSION

ENV GDB_VERSION=${GDB_VERSION}

# ── GDB output dir (needs root) ───────────────────────────────────────────────
USER root
RUN mkdir -p "${FE_DIR}/gdb" && chown -R ${UID}:${GID} "${FE_DIR}/gdb"
USER factoryengine

WORKDIR /home/factoryengine

# ── Clone GDB ────────────────────────────────────────────────────────────────
RUN if command -v apt-get >/dev/null 2>&1; then \
      git clone https://sourceware.org/git/binutils-gdb.git \
        -b gdb-${GDB_VERSION}-release --depth=1; \
    fi

# ── Build & install GDB ───────────────────────────────────────────────────────
WORKDIR /home/factoryengine/binutils-gdb
RUN mkdir -p build

WORKDIR /home/factoryengine/binutils-gdb/build
RUN if command -v apt-get >/dev/null 2>&1; then \
      if [ -f /etc/os-release ] \
        && grep -q "Ubuntu" /etc/os-release \
        && grep -q "26" /etc/os-release; then \
          echo "Ubuntu 26 detected"; \
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
        "/home/factoryengine/out/gdb-${GDB_VERSION}-$(grep '^ID=' /etc/os-release | awk -F'=' '{print $2}')_$(grep -oP '^VERSION_ID=\"\d+.*$' /etc/os-release | sed -n 's/VERSION_ID=\"\([0-9]*\).*/\1/p')_$(uname -m).tar.gz"; \
    fi

WORKDIR /home/factoryengine

##########
# PYTHON #
##########
FROM setup_build AS python_build

ARG PYTHON_VERSION

ENV PYTHON_VERSION=${PYTHON_VERSION}

RUN if command -v apt-get >/dev/null 2>&1; then \
        export DEBIAN_FRONTEND=noninteractive; \
        apt-get update && apt-get install -y --no-install-recommends \
            build-essential \
            checkinstall \
            libncursesw5-dev \
            libssl-dev \
            libsqlite3-dev \
            openssl \
            tk-dev \
            libgdbm-dev \
            libc6-dev \
            libbz2-dev \
            libffi-dev \
            wget \
            ca-certificates; \
        apt-get install -y --no-install-recommends software-properties-common python3-launchpadlib || true; \
        apt-get install -y --no-install-recommends libgdbm-compat-dev || true; \
        update-ca-certificates || true; \
    elif command -v apk >/dev/null 2>&1; then \
        apk add --no-cache \
            bash curl gcc make \
            musl-dev gcompat libffi-dev \
            openssl-dev openssl \
            jpeg-dev zlib-dev \
            cairo-dev pango-dev gdk-pixbuf-dev \
            ca-certificates \
            bzip2-dev xz-dev readline-dev sqlite-dev; \
    else \
        echo "Unknown package manager"; exit 1; \
    fi

# ── Import custom GCC ─────────────────────────────────────────────────────────
COPY --from=gcc_build ${FE_DIR}/gcc ${FE_DIR}/gcc
ENV PATH=${FE_DIR}/gcc/bin:${PATH}
ENV LD_LIBRARY_PATH=${FE_DIR}/gcc/lib64:${LD_LIBRARY_PATH}

# ── Python output dirs ────────────────────────────────────────────────────────
RUN mkdir -p "${FE_DIR}/build" "${FE_DIR}/python" \
 && chown -R ${UID}:${GID} "${FE_DIR}/build" "${FE_DIR}/python"

USER factoryengine
WORKDIR ${FE_DIR}/build

# ── Download & build Python from source using our custom GCC ──────────────────
RUN wget "https://www.python.org/ftp/python/${PYTHON_VERSION}/Python-${PYTHON_VERSION}.tgz"
RUN tar -xvf "Python-${PYTHON_VERSION}.tgz" -C "${FE_DIR}/build" --strip-components=1

RUN CC="${FE_DIR}/gcc/bin/gcc" CXX="${FE_DIR}/gcc/bin/g++" \
    ./configure --prefix="${FE_DIR}/python" \
    --enable-shared  \
    --with-openssl=/usr \
    --with-openssl-rpath=auto \
    --enable-shared
RUN make -j$(nproc)
RUN make install -j$(nproc)

# ── Package Python artifact ───────────────────────────────────────────────────
WORKDIR ${FE_DIR}/python
RUN ln -s ./bin/python3 ./python
RUN tar cvf - . | gzip -9  - > "/home/factoryengine/out/python-${PYTHON_VERSION}-$(grep '^ID=' /etc/os-release | awk -F'=' '{print $2}')_$(grep -oP '^VERSION_ID=\"\d+.*$' /etc/os-release | sed -n 's/VERSION_ID=\"\([0-9]*\).*/\1/p')_$(uname -m).tar.gz"

WORKDIR /home/factoryengine

############
# VALGRIND #
############
FROM setup_build AS valgrind_build

ARG VALGRIND_VERSION

ENV VALGRIND_VERSION=${VALGRIND_VERSION}

RUN if command -v apt-get >/dev/null 2>&1; then \
  export DEBIAN_FRONTEND=noninteractive; \
  apt-get update && apt-get install -y --no-install-recommends git build-essential tar autoconf automake libtool m4 pkg-config ca-certificates; \
  apt-get install -y --no-install-recommends mpi-default-dev xsltproc libc-dbg || true; \
  update-ca-certificates || true; \
  fi

# ── Import custom GCC ─────────────────────────────────────────────────────────
COPY --from=gcc_build ${FE_DIR}/gcc ${FE_DIR}/gcc
ENV PATH=${FE_DIR}/gcc/bin:${PATH}
ENV LD_LIBRARY_PATH=${FE_DIR}/gcc/lib64:${LD_LIBRARY_PATH}

# ── Valgrind output dir ───────────────────────────────────────────────────────
RUN mkdir -p "${FE_DIR}/valgrind" && chown -R ${UID}:${GID} "${FE_DIR}/valgrind"
USER factoryengine
WORKDIR /home/factoryengine

RUN if command -v apt-get >/dev/null 2>&1; then \
    VALGRIND_TAG=$(echo ${VALGRIND_VERSION} | tr '.' '_'); \
    git clone https://sourceware.org/git/valgrind.git -b VALGRIND_${VALGRIND_TAG} --depth=1; \
  fi

WORKDIR /home/factoryengine/valgrind

RUN if command -v apt-get >/dev/null 2>&1; then \
  ./autogen.sh; \
fi
RUN if command -v apt-get >/dev/null 2>&1 && [ "$(uname -m)" = "x86_64" ]; then \
    export SPECIAL_FLAGS=""; \
    echo "Using x86_64"; \
else \
    export SPECIAL_FLAGS="--enable-only64bit"; \
    echo "Using aarch64"; \
fi && if command -v apt-get >/dev/null 2>&1; then \
  CC="${FE_DIR}/gcc/bin/gcc" CXX="${FE_DIR}/gcc/bin/g++" \
  ./configure --enable-lto=yes --enable-tls --prefix=${FE_DIR}/valgrind ${SPECIAL_FLAGS}; \
fi
RUN if command -v apt-get >/dev/null 2>&1; then \
    make -j$(nproc); \
  fi
RUN if command -v apt-get >/dev/null 2>&1; then \
    make install; \
  fi

# ── Package Valgrind artifact ─────────────────────────────────────────────────
WORKDIR ${FE_DIR}/valgrind
RUN if command -v apt-get >/dev/null 2>&1; then \
    tar cvf - . | gzip -9  - > "/home/factoryengine/out/valgrind-${VALGRIND_VERSION}-$(grep '^ID=' /etc/os-release | awk -F'=' '{print $2}')_$(grep -oP '^VERSION_ID=\"\d+.*$' /etc/os-release | sed -n 's/VERSION_ID=\"\([0-9]*\).*/\1/p')_$(uname -m).tar.gz"; \
fi

WORKDIR /home/factoryengine

###########
# DOXYGEN #
###########
FROM setup_build AS doxygen_build

ARG CMAKE_VERSION
ARG DOXYGEN_VERSION
ARG LLVM_VERSION

ENV DOXYGEN_VERSION=${DOXYGEN_VERSION} \
    CMAKE_VERSION=${CMAKE_VERSION} \
    LLVM_VERSION=${LLVM_VERSION}

RUN if command -v apt-get >/dev/null 2>&1; then \
  export DEBIAN_FRONTEND=noninteractive; \
  apt-get update && apt-get install -y --no-install-recommends git build-essential tar cmake flex libzstd-dev bison graphviz wget curl zip unzip ca-certificates python3; \
  apt-get install -y --no-install-recommends lsb-release gnupg software-properties-common || true; \
  update-ca-certificates || true; \
  fi

# ── Import custom GCC ─────────────────────────────────────────────────────────
COPY --from=gcc_build ${FE_DIR}/gcc ${FE_DIR}/gcc
ENV PATH=${FE_DIR}/gcc/bin:${PATH}
ENV LD_LIBRARY_PATH=${FE_DIR}/gcc/lib64:${LD_LIBRARY_PATH}

# ── Doxygen output dir ────────────────────────────────────────────────────────
RUN mkdir -p "${FE_DIR}/doxygen" && chown -R ${UID}:${GID} "${FE_DIR}/doxygen"
USER factoryengine
WORKDIR /home/factoryengine

RUN if command -v apt-get >/dev/null 2>&1; then \
    arch_suffix="$(if [ "$(uname -m)" = "x86_64" ]; then echo x86_64; else echo aarch64; fi)"; \
    CMAKE_MAJOR_MINOR="$(echo "${CMAKE_VERSION}" | awk -F. '{print $1"."$2}')"; \
    downloadURL="https://github.com/MREAMTG/febins/releases/download/cmake/cmake-${CMAKE_VERSION}-linux-${arch_suffix}.tar.gz"; \
    downloadName="cmake-${CMAKE_VERSION}-linux-${arch_suffix}.tar.gz"; \
    folderName="cmake-${CMAKE_VERSION}-linux-${arch_suffix}"; \
    wget "${downloadURL}"; \
    if tar -tzf "./${downloadName}" | head -1 | grep -qE "^${folderName}/"; then \
      tar -xzvf "./${downloadName}"; \
    else \
      mkdir -p "${folderName}"; \
      tar -xzvf "./${downloadName}" -C "${folderName}"; \
    fi; \
    mv "${folderName}" cmake; \
  fi

RUN if command -v apt-get >/dev/null 2>&1; then \
  wget https://apt.llvm.org/llvm.sh; \
  chmod +x llvm.sh; \
fi

USER root
RUN if command -v apt-get >/dev/null 2>&1; then \
  ./llvm.sh ${LLVM_VERSION} all || true; \
fi
USER factoryengine

RUN if command -v apt-get >/dev/null 2>&1; then \
    DOXYGEN_TAG="Release_$(echo "${DOXYGEN_VERSION}" | tr '.' '_')"; \
    git clone https://github.com/doxygen/doxygen.git -b "${DOXYGEN_TAG}" --depth=1; \
  fi

WORKDIR /home/factoryengine/doxygen
RUN mkdir -p build
WORKDIR /home/factoryengine/doxygen/build

RUN if command -v apt-get >/dev/null 2>&1; then \
    LLVM_DIR="/usr/lib/llvm-${LLVM_VERSION}/lib/cmake/llvm"; \
    CLANG_DIR="/usr/lib/llvm-${LLVM_VERSION}/lib/cmake/clang"; \
    if [ -d "${LLVM_DIR}" ] && [ -d "${CLANG_DIR}" ]; then \
      export CMAKE_PREFIX_PATH="/usr/lib/llvm-${LLVM_VERSION}/lib/cmake:${CMAKE_PREFIX_PATH}"; \
      CC="${FE_DIR}/gcc/bin/gcc" CXX="${FE_DIR}/gcc/bin/g++" \
      /home/factoryengine/cmake/bin/cmake .. -Duse_libclang=ON -DLLVM_DIR="${LLVM_DIR}" -DClang_DIR="${CLANG_DIR}" -DCMAKE_INSTALL_PREFIX=${FE_DIR}/doxygen; \
    else \
      CC="${FE_DIR}/gcc/bin/gcc" CXX="${FE_DIR}/gcc/bin/g++" \
      /home/factoryengine/cmake/bin/cmake .. -Duse_libclang=OFF -DCMAKE_INSTALL_PREFIX=${FE_DIR}/doxygen; \
    fi; \
  fi

RUN if command -v apt-get >/dev/null 2>&1; then \
    make -j$(nproc); \
  fi
RUN if command -v apt-get >/dev/null 2>&1; then \
    make install; \
  fi

# ── Package Doxygen artifact ──────────────────────────────────────────────────
WORKDIR ${FE_DIR}/doxygen
RUN if command -v apt-get >/dev/null 2>&1; then \
    tar cvf - . | gzip -9  - > "/home/factoryengine/out/doxygen-${DOXYGEN_VERSION}-$(grep '^ID=' /etc/os-release | awk -F'=' '{print $2}')_$(grep -oP '^VERSION_ID=\"\d+.*$' /etc/os-release | sed -n 's/VERSION_ID=\"\([0-9]*\).*/\1/p')_$(uname -m).tar.gz"; \
fi

WORKDIR /home/factoryengine

##########
# OUTPUT #
##########
FROM setup_build AS build

WORKDIR /home/factoryengine
USER factoryengine

COPY --from=python_build /home/factoryengine/out ./out
COPY --from=gcc_build /home/factoryengine/out ./out
COPY --from=gdb_build /home/factoryengine/out ./out
COPY --from=valgrind_build /home/factoryengine/out ./out
COPY --from=doxygen_build /home/factoryengine/out ./out

WORKDIR /home/factoryengine
