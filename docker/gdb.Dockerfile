ARG BUILD_IMAGE=ubuntu:focal
ARG PLATFORM=linux/amd64
ARG UID=1000
ARG GID=1000
ARG TZ="America/Toronto"
ARG GDB_VERSION="16.3"
ARG FE_DIR="/opt/FactoryEngine"

FROM --platform=${PLATFORM} ${BUILD_IMAGE} AS gdb_build

ARG UID
ARG GID
ARG TZ
ARG GDB_VERSION
ARG FE_DIR

ENV UID=${UID} \
    GID=${GID} \
    TZ=${TZ} \
    GDB_VERSION=${GDB_VERSION} \
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
  apt-get update && apt-get install -y --no-install-recommends autoconf libtool gettext bison dejagnu flex procps gobjc libexpat1-dev libncurses5-dev \
    libreadline-dev zlib1g-dev liblzma-dev libbabeltrace-dev libxxhash-dev libmpfr-dev pkg-config python3-dev \
    build-essential git libgmp-dev texinfo python3 ca-certificates; \
  apt-get install -y --no-install-recommends libc-dbg source-highlight libsource-highlight-dev libdebuginfod-dev || true; \
  update-ca-certificates || true; \
  fi
RUN if [ -n "${APT_CMD}" ] && [ "$(uname -m)" = "x86_64" ]; then \
    echo "Using x86_64"; \
    apt-get install -y --no-install-recommends libipt-dev || true; \
  else \
    echo "Using aarch64"; \
  fi

WORKDIR /home/factoryengine

RUN mkdir -p "${FE_DIR}/gdb" && chown -R ${UID}:${GID} "${FE_DIR}/gdb"
USER factoryengine

RUN if [ -n "${APT_CMD}" ]; then \
    git clone https://sourceware.org/git/binutils-gdb.git -b gdb-${GDB_VERSION}-release --depth=1; \
  fi

WORKDIR /home/factoryengine/binutils-gdb
RUN if [ -n "${APT_CMD}" ]; then \
    mkdir build -p; \
  fi
WORKDIR /home/factoryengine/binutils-gdb/build

RUN if [ -n "${APT_CMD}" ]; then \
  # If Ubuntu v26, we need a special flag to avoid a build failure due to a change in the default behavior of auto-load directories. See https://bugs.launchpad.net/ubuntu/+source/gdb/+bug/2004418 for more details. \
  if [ -f /etc/os-release ] && grep -q "Ubuntu" /etc/os-release && grep -q "26" /etc/os-release; then \
    echo "Ubuntu 26 detected, adding --with-auto-load-safe-path=/opt/FactoryEngine/gcc/lib64 to configure options"; \
    ../configure --prefix=${FE_DIR}/gdb \
      --disable-gprofng \
      --with-auto-load-dir=\$debugdir:\$datadir/auto-load \
      --with-auto-load-safe-path=/opt/FactoryEngine/gcc/lib64:\$debugdir:\$datadir/auto-load; \
  else \
    ../configure --prefix=${FE_DIR}/gdb \
      --with-auto-load-dir=\$debugdir:\$datadir/auto-load \
      --with-auto-load-safe-path=/opt/FactoryEngine/gcc/lib64:\$debugdir:\$datadir/auto-load ; \
    fi; \
fi
RUN if [ -n "${APT_CMD}" ]; then \
    make -j$(nproc); \
  fi
RUN if [ -n "${APT_CMD}" ]; then \
    make install; \
  fi

RUN mkdir -p /home/factoryengine/out

WORKDIR ${FE_DIR}/gdb
RUN if [ -n "${APT_CMD}" ]; then \
    tar cvf - . | gzip -9  - > "/home/factoryengine/out/gdb-${GDB_VERSION}-$(grep '^ID=' /etc/os-release | awk -F'=' '{print $2}')_$(grep -oP '^VERSION=\"\d+.*$' /etc/os-release | sed -n 's/VERSION=\"\([0-9]*\).*/\1/p')_$(uname -m).tar.gz"; \
fi

WORKDIR /home/factoryengine
