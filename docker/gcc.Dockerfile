ARG BUILD_IMAGE=ubuntu:focal
ARG PLATFORM=linux/amd64
ARG UID=1000
ARG GID=1000
ARG TZ="America/Toronto"
ARG GCC_VERSION=1.17.0
ARG FE_DIR="/opt/FactoryEngine"

FROM --platform=${PLATFORM} ${BUILD_IMAGE} AS gcc_build

ARG UID
ARG GID
ARG TZ
ARG GCC_VERSION
ARG FE_DIR

ENV UID=${UID} \
    GID=${GID} \
    TZ=${TZ} \
    FE_DIR=${FE_DIR} \
    GCC_VERSION=${GCC_VERSION} \
    APT_CMD="$(which apt-get)"

RUN groupadd -o -g ${GID} factoryengine
RUN useradd -o -u ${UID} -g ${GID} -s /bin/sh -d /home/factoryengine -m factoryengine

RUN if [ -n "${APT_CMD}" ]; then \
  export DEBIAN_FRONTEND=noninteractive; \
  apt-get update && apt-get install -y --no-install-recommends tzdata; \
  fi

RUN echo "${TZ}" > /etc/timezone \
  && ln -fsn "/usr/share/zoneinfo/${TZ}" /etc/localtime \
  && if [ -n "${APT_CMD}" ]; then DEBIAN_FRONTEND=noninteractive dpkg-reconfigure --frontend noninteractive tzdata; fi

RUN if [ -n "${APT_CMD}" ]; then \
  export DEBIAN_FRONTEND=noninteractive; \
  apt-get update && apt-get install -y --no-install-recommends build-essential python3 git make gawk flex bison libgmp-dev libmpfr-dev libmpc-dev binutils perl tar gzip bzip2 curl ca-certificates; \
  apt-get install -y --no-install-recommends libisl-dev libzstd-dev || true; \
  update-ca-certificates || true; \
  fi

WORKDIR /home/factoryengine

RUN mkdir -p "${FE_DIR}/gcc" && chown -R ${UID}:${GID} "${FE_DIR}/gcc"
USER factoryengine

RUN if [ -n "${APT_CMD}" ]; then \
    git clone git://gcc.gnu.org/git/gcc.git -b releases/gcc-${GCC_VERSION} --depth=1; \
  fi

ENV CONFIG_SHELL=/bin/bash

WORKDIR /home/factoryengine/gcc
RUN if [ -n "${APT_CMD}" ]; then \
    ./contrib/download_prerequisites; \
  fi
RUN if [ -n "${APT_CMD}" ]; then \
    mkdir build -p; \
  fi
WORKDIR /home/factoryengine/gcc/build

RUN if [ -n "${APT_CMD}" ] && [ "$(uname -m)" = "x86_64" ]; then \
    export SPECIAL_FLAGS=""; \
    export LOCAL_TRIPLET="x86_64"; \
    echo "Using x86_64"; \
else \
    export SPECIAL_FLAGS="--enable-fix-cortex-a53-843419"; \
    export LOCAL_TRIPLET="aarch64"; \
    echo "Using aarch64"; \
fi && if [ -n "${APT_CMD}" ]; then \
  ../configure --enable-languages=c,c++,fortran --prefix=${FE_DIR}/gcc --disable-multilib --disable-multi-arch \
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

WORKDIR ${FE_DIR}/gcc
RUN if [ -n "${APT_CMD}" ]; then \
    tar cvf - . | gzip -9  - > "/home/factoryengine/out/gcc-${GCC_VERSION}-$(grep '^ID=' /etc/os-release | awk -F'=' '{print $2}')_$(grep -oP '^VERSION=\"\d+.*$' /etc/os-release | sed -n 's/VERSION=\"\([0-9]*\).*/\1/p')_$(uname -m).tar.gz"; \
fi

WORKDIR /home/factoryengine
