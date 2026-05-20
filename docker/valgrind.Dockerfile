ARG BUILD_IMAGE=ubuntu:bionic
ARG PLATFORM=linux/amd64
ARG UID=1000
ARG GID=1000
ARG TZ="America/Toronto"
ARG VALGRIND_VERSION="3.24.0"
ARG FE_DIR="/opt/FactoryEngine"

FROM --platform=${PLATFORM} ${BUILD_IMAGE} AS valgrind_build

ARG UID
ARG GID
ARG TZ
ARG VALGRIND_VERSION
ARG FE_DIR

ENV UID=${UID} \
    GID=${GID} \
    TZ=${TZ} \
    VALGRIND_VERSION=${VALGRIND_VERSION} \
    FE_DIR=${FE_DIR} \
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
  apt-get update && apt-get install -y --no-install-recommends git build-essential tar autoconf automake libtool m4 pkg-config ca-certificates; \
  apt-get install -y --no-install-recommends mpi-default-dev xsltproc libc-dbg || true; \
  update-ca-certificates || true; \
  fi

WORKDIR /home/factoryengine

RUN mkdir -p "${FE_DIR}/valgrind" && chown -R ${UID}:${GID} "${FE_DIR}/valgrind"
USER factoryengine

RUN if [ -n "${APT_CMD}" ]; then \
    VALGRIND_TAG=$(echo ${VALGRIND_VERSION} | tr '.' '_'); \
    git clone https://sourceware.org/git/valgrind.git -b VALGRIND_${VALGRIND_TAG} --depth=1; \
  fi

WORKDIR /home/factoryengine/valgrind

RUN if [ -n "${APT_CMD}" ]; then \
  ./autogen.sh; \
fi
RUN if [ -n "${APT_CMD}" ] && [ "$(uname -m)" = "x86_64" ]; then \
    export SPECIAL_FLAGS=""; \
    echo "Using x86_64"; \
else \
    export SPECIAL_FLAGS="--enable-only64bit"; \
    echo "Using aarch64"; \
fi && if [ -n "${APT_CMD}" ]; then \
  ./configure --enable-lto=yes --enable-tls --prefix=${FE_DIR}/valgrind ${SPECIAL_FLAGS}; \
fi
RUN if [ -n "${APT_CMD}" ]; then \
    make -j$(nproc); \
  fi
RUN if [ -n "${APT_CMD}" ]; then \
    make install; \
  fi

RUN mkdir -p /home/factoryengine/out

WORKDIR ${FE_DIR}/valgrind
RUN if [ -n "${APT_CMD}" ]; then \
    tar cvf - . | gzip -9  - > "/home/factoryengine/out/valgrind-${VALGRIND_VERSION}-$(grep '^ID=' /etc/os-release | awk -F'=' '{print $2}')_$(grep -oP '^VERSION=\"\d+.*$' /etc/os-release | sed -n 's/VERSION=\"\([0-9]*\).*/\1/p')_$(uname -m).tar.gz"; \
fi

WORKDIR /home/factoryengine
