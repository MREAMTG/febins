ARG BUILD_IMAGE=ubuntu:bionic-20210512
ARG PLATFORM=linux/amd64


FROM --platform=${PLATFORM} ${BUILD_IMAGE} AS python_build

ARG UID=${UID}
ARG GID=${GID}
ARG TZ="America/Toronto"
ARG PYTHON_VERSION="3.11.9"
ARG PYTHON_DIR="/usr/local/factoryengine/python"
ARG PYTHON_BUILD_DIR="/usr/local/factoryengine/build"

ENV TZ=${TZ} \
  PYTHON_VERSION=${PYTHON_VERSION} \
  PYTHON_DIR=${PYTHON_DIR} \
  PYTHON_BUILD_DIR=${PYTHON_BUILD_DIR} \
  APT_CMD="$(which apt-get)" \
  YUM_CMD="$(which yum)" \
  DNF_CMD="$(which dnf)" \
  ZYPPER_CMD="$(which zypper)" \
  APK_CMD="$(which apk)"

# Create a user to run the build process
RUN groupadd -o -g ${GID} factoryengine
RUN useradd -o -u ${UID} -g ${GID} -s /bin/sh -d /home/factoryengine -m factoryengine

RUN if [ -n "${APT_CMD}" ]; then \
  apt-get update && apt-get install -y tzdata; \
  elif [ -n "${YUM_CMD}" ]; then \
    yum install -y tzdata; \
  elif [ -n "${DNF_CMD}" ]; then \
    dnf install -y tzdata; \
  else \
    echo "Package manager not supported."; exit 1; \
  fi

RUN echo "${TZ}" > /etc/timezone \
  && ln -fsn "/usr/share/zoneinfo/${TZ}" /etc/localtime \
  && dpkg-reconfigure --frontend noninteractive tzdata

RUN if [ -n "${APT_CMD}" ]; then \
  apt-get install -y \
    build-essential \
    checkinstall \
    libncursesw5-dev \
    libssl-dev \
    libsqlite3-dev \
    tk-dev \
    libgdbm-dev \
    libc6-dev \
    libbz2-dev \
    libffi-dev \
    software-properties-common \
    python3-launchpadlib \
    wget; \
  elif [ -n "${YUM_CMD}" ]; then \
    yum groupinstall 'Development Tools' -y && yum install -y \
      gcc \
      ncurses-devel \
      openssl-devel \
      bzip2-devel \
      libffi-devel \
      glibc-devel \
      sqlite-devel \
      zlib-devel; \
  elif [ -n "${DNF_CMD}" ]; then \
    dnf groupinstall 'Development Tools' -y && dnf install -y \
      gcc \
      ncurses-devel \
      openssl-devel \
      bzip2-devel \
      libffi-devel \
      glibc-devel \
      sqlite-devel \
      zlib-devel; \
  elif [ -n "${ZYPPER_CMD}" ]; then \
    echo "Zypper is not supported yet in our system."; exit 1; \
  elif [ -n "${APK_CMD}" ]; then \
    apk add --no-cache gcc gcompat musl-dev \
      sqlite-dev \
      zlib-dev; echo "apk is not yet supported."; exit 1; \
  else \
    echo "Unknown package manager"; exit 1; \
  fi

# If running Ubuntu Version 20.04 or later, install the following dependencies
RUN if [ -n "${APT_CMD}" ] && [ "$(grep '^ID=' /etc/os-release | awk -F'=' '{print $2}')" != "ubuntu" ] || [ dpkg --compare-versions "$(grep '^VERSION=' /etc/os-release | sed -n 's/VERSION=\"\([0-9]*\.[0-9]*\.[0-9]*\).*/\1/p')" lt '20.04' ]; then \
  apt-get install -y libgdbm-compat-dev; \
fi

# Create the build directory for Python and give permissions to the user
RUN mkdir -p "${PYTHON_BUILD_DIR}" && chown -R ${UID}:${GID} "${PYTHON_BUILD_DIR}"
RUN mkdir -p "${PYTHON_DIR}" && chown -R ${UID}:${GID} "${PYTHON_DIR}"

USER factoryengine
WORKDIR ${PYTHON_BUILD_DIR}

# Download the Python source code
RUN wget "https://www.python.org/ftp/python/${PYTHON_VERSION}/Python-${PYTHON_VERSION}.tgz"
RUN tar -xvf "Python-${PYTHON_VERSION}.tgz" -C "${PYTHON_BUILD_DIR}" --strip-components=1

# Build Python from source
RUN ./configure --prefix="${PYTHON_DIR}" --enable-shared
RUN make -j$(nproc)
RUN make install -j$(nproc)

WORKDIR ${PYTHON_DIR}

# Next, create the symlink for `python` inside `${PYTHON_DIR}/`
RUN ln -s ./bin/python3 ./python

RUN mkdir -p /home/factoryengine/out

# Now, tar the 4 folders and symlink
RUN tar cvf - ./bin ./include ./lib ./share ./python | gzip -9  - > "/home/factoryengine/out/Python-${PYTHON_VERSION}-$(grep '^ID=' /etc/os-release | awk -F'=' '{print $2}')_$(grep -oP '^VERSION="\d+.*$' /etc/os-release | sed -n 's/VERSION="\([0-9]*\).*/\1/p')_$(uname -m).tar.gz"

WORKDIR /home/factoryengine

#######
# GCC #
#######
FROM --platform=${PLATFORM} ${BUILD_IMAGE} AS gcc_build

ARG UID=${UID}
ARG GID=${GID}
ARG TZ="America/Toronto"
ENV TZ=${TZ} \
  APT_CMD="$(which apt-get)"

RUN groupadd -o -g ${GID} factoryengine
RUN useradd -o -u ${UID} -g ${GID} -s /bin/sh -d /home/factoryengine -m factoryengine

ARG GCC_VERSION="15.1.0"
ARG GCC_TAG="releases/gcc-${GCC_VERSION}"
ENV GCC_INSTALL_DIR="/usr/local/factoryengine/gcc"

RUN if [ -n "${APT_CMD}" ]; then \
  apt-get update && apt-get install -y tzdata; \
  fi

RUN echo "${TZ}" > /etc/timezone \
  && ln -fsn "/usr/share/zoneinfo/${TZ}" /etc/localtime \
  && dpkg-reconfigure --frontend noninteractive tzdata


RUN if [ -n "${APT_CMD}" ]; then \
  apt-get install -y build-essential python3 git make gawk flex bison libgmp-dev libmpfr-dev libmpc-dev binutils perl libisl-dev libzstd-dev tar gzip bzip2 curl; \
  fi

WORKDIR /home/factoryengine

RUN mkdir -p "${GCC_INSTALL_DIR}" && chown -R ${UID}:${GID} "${GCC_INSTALL_DIR}"
USER factoryengine

RUN if [ -n "${APT_CMD}" ]; then \
    git clone git://gcc.gnu.org/git/gcc.git -b ${GCC_TAG} --depth=1; \
  fi

# https://gcc.gnu.org/git.html
# https://medium.com/@xersendo/moving-to-c-26-how-to-build-and-set-up-gcc-15-1-on-ubuntu-f52cc9173fa0
ENV CONFIG_SHELL=/bin/bash

WORKDIR ./gcc
RUN if [ -n "${APT_CMD}" ]; then \
    ./contrib/download_prerequisites; \
  fi
RUN if [ -n "${APT_CMD}" ]; then \
    mkdir build -p; \
  fi
WORKDIR ./build


RUN if [ -n "${APT_CMD}" ] & [ "$(uname -m)" = "x86_64" ]; then \
    export SPECIAL_FLAGS=""; \
    export LOCAL_TRIPLET="x86_64"; \
    echo "Using x86_64"; \
else \
    export SPECIAL_FLAGS="--enable-fix-cortex-a53-843419"; \
    export LOCAL_TRIPLET="aarch64"; \
    echo "Using aarch64"; \
fi && if [ -n "${APT_CMD}" ]; then \
  ../configure --enable-languages=c,c++,fortran --prefix=${GCC_INSTALL_DIR} --disable-multilib --disable-multi-arch \
  --program-suffix=-15 \
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
RUN if [ -n "${APT_CMD}" ]; then \
    make -j$(nproc); \
  fi
RUN if [ -n "${APT_CMD}" ]; then \
    make install; \
  fi

RUN mkdir -p /home/factoryengine/out

RUN if [ -n "${APT_CMD}" ]; then \
    tar cvf - ${GCC_INSTALL_DIR} | gzip -9  - > "/home/factoryengine/out/gcc-${GCC_VERSION}-$(grep '^ID=' /etc/os-release | awk -F'=' '{print $2}')_$(grep -oP '^VERSION=\"\d+.*$' /etc/os-release | sed -n 's/VERSION=\"\([0-9]*\).*/\1/p')_$(uname -m).tar.gz"; \
fi

WORKDIR /home/factoryengine


#######
# GDB #
#######
FROM --platform=${PLATFORM} ${BUILD_IMAGE} AS gdb_build

ARG UID=${UID}
ARG GID=${GID}
ARG TZ="America/Toronto"
ENV TZ=${TZ} \
  APT_CMD="$(which apt-get)"

RUN groupadd -o -g ${GID} factoryengine
RUN useradd -o -u ${UID} -g ${GID} -s /bin/sh -d /home/factoryengine -m factoryengine

ARG GDB_VERSION="16.3"
ARG GDB_TAG="gdb-${GDB_VERSION}-release"
ENV GDB_INSTALL_DIR="/usr/local/factoryengine/gdb"

RUN if [ -n "${APT_CMD}" ]; then \
  apt-get update && apt-get install -y tzdata; \
  fi

RUN echo "${TZ}" > /etc/timezone \
  && ln -fsn "/usr/share/zoneinfo/${TZ}" /etc/localtime \
  && dpkg-reconfigure --frontend noninteractive tzdata

RUN if [ -n "${APT_CMD}" ]; then \
  apt-get install -y autoconf libtool gettext bison dejagnu flex procps gobjc libexpat1-dev libncurses5-dev \
    libreadline-dev zlib1g-dev liblzma-dev libbabeltrace-dev libxxhash-dev libmpfr-dev pkg-config python3-dev \
    build-essential git libgmp-dev texinfo python3 libc-dbg source-highlight libsource-highlight-dev; \
  fi
RUN if [ -n "${APT_CMD}" ] & [ "$(grep '^ID=' /etc/os-release | awk -F'=' '{print $2}')" = "ubuntu" ] & [ dpkg --compare-versions "$(grep '^VERSION=' /etc/os-release | sed -n 's/VERSION=\"\([0-9]*\.[0-9]*\.[0-9]*\).*/\1/p')" eq '22.04' ]; then \
  apt-get install -y libdebuginfod-dev; \
fi
RUN if [ -n "${APT_CMD}" ] & [ "$(grep '^ID=' /etc/os-release | awk -F'=' '{print $2}')" = "ubuntu" ] & [ dpkg --compare-versions "$(grep '^VERSION=' /etc/os-release | sed -n 's/VERSION=\"\([0-9]*\.[0-9]*\.[0-9]*\).*/\1/p')" eq '24.04' ]; then \
  apt-get install -y libdebuginfod-dev; \
fi
RUN if [ -n "${APT_CMD}" ] & [ "$(grep '^ID=' /etc/os-release | awk -F'=' '{print $2}')" = "debian" ]; then \
  apt-get install -y libdebuginfod-dev; \
fi
RUN if [ -n "${APT_CMD}" ] & [ "$(uname -m)" = "x86_64" ]; then \
    echo "Using x86_64"; \
    apt-get install -y libipt-dev; \
  else \
    echo "Using aarch64"; \
  fi

WORKDIR /home/factoryengine

RUN mkdir -p "${GDB_INSTALL_DIR}" && chown -R ${UID}:${GID} "${GDB_INSTALL_DIR}"
USER factoryengine

RUN if [ -n "${APT_CMD}" ]; then \
    git clone https://sourceware.org/git/binutils-gdb.git -b ${GDB_TAG} --depth=1; \
  fi

WORKDIR ./binutils-gdb
RUN if [ -n "${APT_CMD}" ]; then \
    mkdir build -p; \
  fi
WORKDIR ./build

# RUN if [ -n "${APT_CMD}" ] && [ "$(grep '^ID=' /etc/os-release | awk -F'=' '{print $2}')" -eq "ubuntu" ] || [ dpkg --compare-versions "$(grep '^VERSION=' /etc/os-release | sed -n 's/VERSION=\"\([0-9]*\.[0-9]*\.[0-9]*\).*/\1/p')" eq '22.04' ]; then \
#     export SPECIAL_FLAGS="--with-debuginfod"; \
# fi && if [ -n "${APT_CMD}" ] && [ "$(grep '^ID=' /etc/os-release | awk -F'=' '{print $2}')" -eq "ubuntu" ] || [ dpkg --compare-versions "$(grep '^VERSION=' /etc/os-release | sed -n 's/VERSION=\"\([0-9]*\.[0-9]*\.[0-9]*\).*/\1/p')" eq '24.04' ]; then \
#     export SPECIAL_FLAGS="--with-debuginfod"; \
# fi && if [ -n "${APT_CMD}" ] && [ "$(grep '^ID=' /etc/os-release | awk -F'=' '{print $2}')" -eq "debian" ]; then \
#     export SPECIAL_FLAGS="--with-debuginfod"; \
# fi && if [ -n "${APT_CMD}" ] & [ "$(uname -m)" = "x86_64" ]; then \
#     export SPECIAL_FLAGS="--with-intel-pt ${SPECIAL_FLAGS}"; \
#     echo "Using x86_64"; \
# else \
#     echo "Using aarch64"; \
# fi &&
RUN if [ -n "${APT_CMD}" ]; then \
  ../configure --prefix=${GDB_INSTALL_DIR} \
    --with-auto-load-dir=\$debugdir:\$datadir/auto-load \
    --with-auto-load-safe-path=/usr/local/factoryengine/gcc/lib64:\$debugdir:\$datadir/auto-load ; \
fi
# fi && if [ -n "${APT_CMD}" ]; then \
#   ../configure --prefix=${GDB_INSTALL_DIR} \
#     --host=$(uname -m)-linux-gnu --target=$(uname -m)-linux-gnu \
#     --with-auto-load-dir=\$debugdir:\$datadir/auto-load \
#     --with-auto-load-safe-path=\$debugdir:\$datadir/auto-load \
#     --with-expat \
#     --with-gdb-datadir=/usr/local/factoryengine/gdb/share \
#     --with-jit-reader-dir=/usr/local/factoryengine/gdb/lib \
#     --without-libunwind-ia64 \
#     --with-lzma \
#     --with-babeltrace \
#     --with-mpfr \
#     --with-xxhash \
#     --with-python=python3 \
#     # --with-python-libdir=/usr/lib \
#     --without-guile \
#     --enable-source-highlight \
#     --with-separate-debug-dir=/usr/lib/debug \
#     --with-gmp-lib=/usr/lib/$(uname -m)-linux-gnu \
#     --with-gmp-include=/usr/include/$(uname -m)-linux-gnu \
#     --with-system-gdbinit=/etc/gdb/gdbinit \
#     --with-system-gdbinit-dir=/etc/gdb/gdbinit.d ${SPECIAL_FLAGS}; \
# fi
RUN if [ -n "${APT_CMD}" ]; then \
    make -j$(nproc); \
  fi
RUN if [ -n "${APT_CMD}" ]; then \
    make install; \
  fi

RUN mkdir -p /home/factoryengine/out

RUN if [ -n "${APT_CMD}" ]; then \
    tar cvf - ${GDB_INSTALL_DIR} | gzip -9  - > "/home/factoryengine/out/gdb-${GDB_VERSION}-$(grep '^ID=' /etc/os-release | awk -F'=' '{print $2}')_$(grep -oP '^VERSION=\"\d+.*$' /etc/os-release | sed -n 's/VERSION=\"\([0-9]*\).*/\1/p')_$(uname -m).tar.gz"; \
fi

WORKDIR /home/factoryengine



############
# Valgrind #
############
FROM --platform=${PLATFORM} ${BUILD_IMAGE} AS valgrind_build

ARG UID=${UID}
ARG GID=${GID}
ARG TZ="America/Toronto"
ENV TZ=${TZ} \
  APT_CMD="$(which apt-get)"

RUN groupadd -o -g ${GID} factoryengine
RUN useradd -o -u ${UID} -g ${GID} -s /bin/sh -d /home/factoryengine -m factoryengine

ARG VALGRIND_VERSION="3.24.0"
ARG VALGRIND_TAG="VALGRIND_3_24_0"
ENV VALGRIND_INSTALL_DIR="/usr/local/factoryengine/valgrind"

RUN if [ -n "${APT_CMD}" ]; then \
  apt-get update && apt-get install -y tzdata; \
  fi

RUN echo "${TZ}" > /etc/timezone \
  && ln -fsn "/usr/share/zoneinfo/${TZ}" /etc/localtime \
  && dpkg-reconfigure --frontend noninteractive tzdata

RUN if [ -n "${APT_CMD}" ]; then \
  apt-get install -y git build-essential tar autoconf mpi-default-dev xsltproc pkg-config libc-dbg; \
  fi

WORKDIR /home/factoryengine

RUN mkdir -p "${VALGRIND_INSTALL_DIR}" && chown -R ${UID}:${GID} "${VALGRIND_INSTALL_DIR}"
USER factoryengine

RUN if [ -n "${APT_CMD}" ]; then \
    git clone https://sourceware.org/git/valgrind.git -b ${VALGRIND_TAG} --depth=1; \
  fi

WORKDIR ./valgrind

RUN if [ -n "${APT_CMD}" ]; then \
  ./autogen.sh; \
fi
RUN if [ -n "${APT_CMD}" ] & [ "$(uname -m)" = "x86_64" ]; then \
    export SPECIAL_FLAGS=""; \
    echo "Using x86_64"; \
else \
    export SPECIAL_FLAGS="--enable-only64bit"; \
    echo "Using aarch64"; \
fi && if [ -n "${APT_CMD}" ]; then \
  ./configure --enable-lto=yes --enable-tls --prefix=${VALGRIND_INSTALL_DIR} ${SPECIAL_FLAGS}; \
fi
RUN if [ -n "${APT_CMD}" ]; then \
    make -j$(nproc); \
  fi
RUN if [ -n "${APT_CMD}" ]; then \
    make install; \
  fi

RUN mkdir -p /home/factoryengine/out

RUN if [ -n "${APT_CMD}" ]; then \
    tar cvf - ${VALGRIND_INSTALL_DIR} | gzip -9  - > "/home/factoryengine/out/valgrind-${VALGRIND_VERSION}-$(grep '^ID=' /etc/os-release | awk -F'=' '{print $2}')_$(grep -oP '^VERSION=\"\d+.*$' /etc/os-release | sed -n 's/VERSION=\"\([0-9]*\).*/\1/p')_$(uname -m).tar.gz"; \
fi

WORKDIR /home/factoryengine

FROM --platform=${PLATFORM} ${BUILD_IMAGE} AS build

ARG UID=${UID}
ARG GID=${GID}

RUN groupadd -o -g ${GID} factoryengine
RUN useradd -o -u ${UID} -g ${GID} -s /bin/sh -d /home/factoryengine -m factoryengine

WORKDIR /home/factoryengine
USER factoryengine
RUN mkdir -p /home/factoryengine/out

COPY --from=python_build /home/factoryengine/out ./out
COPY --from=gcc_build /home/factoryengine/out ./out
COPY --from=gdb_build /home/factoryengine/out ./out
COPY --from=valgrind_build /home/factoryengine/out ./out

WORKDIR /home/factoryengine
