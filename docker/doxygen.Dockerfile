ARG BUILD_IMAGE=ubuntu:focal
ARG PLATFORM=linux/amd64
ARG UID=1000
ARG GID=1000
ARG TZ="America/Toronto"
ARG CMAKE_VERSION=3.31.12
ARG DOXYGEN_VERSION=1.17.0
ARG LLVM_VERSION=22
ARG FE_DIR="/opt/FactoryEngine"

FROM --platform=${PLATFORM} ${BUILD_IMAGE} AS doxygen_build

ARG UID
ARG GID
ARG TZ
ARG CMAKE_VERSION
ARG DOXYGEN_VERSION
ARG LLVM_VERSION
ARG FE_DIR

ENV UID=${UID} \
  GID=${GID} \
  TZ=${TZ} \
  DOXYGEN_VERSION=${DOXYGEN_VERSION} \
  CMAKE_VERSION=${CMAKE_VERSION} \
  LLVM_VERSION=${LLVM_VERSION}

RUN groupadd -o -g ${GID} factoryengine
RUN useradd -o -u ${UID} -g ${GID} -s /bin/sh -d /home/factoryengine -m factoryengine

RUN if command -v apt-get >/dev/null 2>&1; then \
  export DEBIAN_FRONTEND=noninteractive; \
  apt-get update && apt-get install -y --no-install-recommends tzdata; \
  fi

RUN echo "${TZ}" > /etc/timezone \
  && ln -fsn "/usr/share/zoneinfo/${TZ}" /etc/localtime \
  && if command -v apt-get >/dev/null 2>&1; then DEBIAN_FRONTEND=noninteractive dpkg-reconfigure --frontend noninteractive tzdata; fi

RUN if command -v apt-get >/dev/null 2>&1; then \
  export DEBIAN_FRONTEND=noninteractive; \
  apt-get update && apt-get install -y --no-install-recommends git build-essential tar cmake flex libzstd-dev bison graphviz wget curl zip unzip ca-certificates python3; \
  apt-get install -y --no-install-recommends lsb-release gnupg software-properties-common || true; \
  update-ca-certificates || true; \
  fi

WORKDIR /home/factoryengine

RUN mkdir -p "${FE_DIR}/doxygen" && chown -R ${UID}:${GID} "${FE_DIR}/doxygen"
USER factoryengine

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
      /home/factoryengine/cmake/bin/cmake .. -Duse_libclang=ON -DLLVM_DIR="${LLVM_DIR}" -DClang_DIR="${CLANG_DIR}" -DCMAKE_INSTALL_PREFIX=${FE_DIR}/doxygen; \
    else \
      /home/factoryengine/cmake/bin/cmake .. -Duse_libclang=OFF -DCMAKE_INSTALL_PREFIX=${FE_DIR}/doxygen; \
    fi; \
  fi

RUN if command -v apt-get >/dev/null 2>&1; then \
    make -j$(nproc); \
  fi
RUN if command -v apt-get >/dev/null 2>&1; then \
    make install; \
  fi

RUN mkdir -p /home/factoryengine/out

WORKDIR ${FE_DIR}/doxygen
RUN if command -v apt-get >/dev/null 2>&1; then \
    tar cvf - . | gzip -9  - > "/home/factoryengine/out/doxygen-${DOXYGEN_VERSION}-$(grep '^ID=' /etc/os-release | awk -F'=' '{print $2}')_$(grep -oP '^VERSION_ID=\"\d+.*$' /etc/os-release | sed -n 's/VERSION_ID=\"\([0-9]*\).*/\1/p')_$(uname -m).tar.gz"; \
fi

WORKDIR /home/factoryengine
