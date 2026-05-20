ARG BUILD_IMAGE=ubuntu:focal
ARG PLATFORM=linux/amd64
ARG UID=1000
ARG GID=1000
ARG TZ="America/Toronto"
ARG PYTHON_VERSION=3.12.13
ARG FE_DIR="/opt/FactoryEngine"

FROM --platform=${PLATFORM} ${BUILD_IMAGE} AS python_build

ARG UID
ARG GID
ARG TZ
ARG PYTHON_VERSION
ARG FE_DIR

ENV UID=${UID} \
  GID=${GID} \
  TZ=${TZ} \
  PYTHON_VERSION=${PYTHON_VERSION} \
  APT_CMD="$(which apt-get)" \
  YUM_CMD="$(which yum)" \
  DNF_CMD="$(which dnf)" \
  ZYPPER_CMD="$(which zypper)" \
  APK_CMD="$(which apk)"

# Create a user to run the build process
RUN groupadd -o -g ${GID} factoryengine
RUN useradd -o -u ${UID} -g ${GID} -s /bin/sh -d /home/factoryengine -m factoryengine

RUN if [ -n "${APT_CMD}" ]; then \
  export DEBIAN_FRONTEND=noninteractive; \
  apt-get update && apt-get install -y --no-install-recommends tzdata; \
  elif [ -n "${YUM_CMD}" ]; then \
    yum install -y tzdata; \
  elif [ -n "${DNF_CMD}" ]; then \
    dnf install -y tzdata; \
  else \
    echo "Package manager not supported."; exit 1; \
  fi

RUN echo "${TZ}" > /etc/timezone \
  && ln -fsn "/usr/share/zoneinfo/${TZ}" /etc/localtime \
  && if [ -n "${APT_CMD}" ]; then DEBIAN_FRONTEND=noninteractive dpkg-reconfigure --frontend noninteractive tzdata; fi

RUN if [ -n "${APT_CMD}" ]; then \
  export DEBIAN_FRONTEND=noninteractive; \
  apt-get update && apt-get install -y --no-install-recommends \
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
    wget \
    ca-certificates; \
  apt-get install -y --no-install-recommends software-properties-common python3-launchpadlib || true; \
  apt-get install -y --no-install-recommends libgdbm-compat-dev || true; \
  update-ca-certificates || true; \
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

# Create the build directory for Python and give permissions to the user
RUN mkdir -p "${FE_DIR}/build" && chown -R ${UID}:${GID} "${FE_DIR}/build"
RUN mkdir -p "${FE_DIR}/python" && chown -R ${UID}:${GID} "${FE_DIR}/python"

USER factoryengine
WORKDIR ${FE_DIR}/build

# Download the Python source code
RUN wget "https://www.python.org/ftp/python/${PYTHON_VERSION}/Python-${PYTHON_VERSION}.tgz"
RUN tar -xvf "Python-${PYTHON_VERSION}.tgz" -C "${FE_DIR}/build" --strip-components=1

# Build Python from source
RUN ./configure --prefix="${FE_DIR}/python" --enable-shared
RUN make -j$(nproc)
RUN make install -j$(nproc)

RUN mkdir -p /home/factoryengine/out

# Next, create the symlink for `python` inside `${FE_DIR}/python`
WORKDIR ${FE_DIR}/python
RUN ln -s ./bin/python3 ./python
RUN tar cvf - . | gzip -9  - > "/home/factoryengine/out/Python-${PYTHON_VERSION}-$(grep '^ID=' /etc/os-release | awk -F'=' '{print $2}')_$(grep -oP '^VERSION=\"\d+.*$' /etc/os-release | sed -n 's/VERSION=\"\([0-9]*\).*/\1/p')_$(uname -m).tar.gz"

WORKDIR /home/factoryengine
