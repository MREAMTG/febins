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
  PYTHON_VERSION=${PYTHON_VERSION}

# Create a user to run the build process
RUN if command -v apk >/dev/null 2>&1; then \
    addgroup -g ${GID} factoryengine && adduser -u ${UID} -D -G factoryengine -h /home/factoryengine -s /bin/sh factoryengine; \
  else \
    groupadd -o -g ${GID} factoryengine && useradd -o -u ${UID} -g ${GID} -s /bin/sh -d /home/factoryengine -m factoryengine; \
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
  else \
    echo "Package manager not supported."; exit 1; \
  fi

RUN echo "${TZ}" > /etc/timezone \
  && ln -fsn "/usr/share/zoneinfo/${TZ}" /etc/localtime \
  && if command -v apt-get >/dev/null 2>&1; then DEBIAN_FRONTEND=noninteractive dpkg-reconfigure --frontend noninteractive tzdata; fi

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
  elif command -v yum >/dev/null 2>&1; then \
    yum groupinstall 'Development Tools' -y && yum install -y \
      gcc \
      ncurses-devel \
      openssl-devel \
      bzip2-devel \
      libffi-devel \
      glibc-devel \
      sqlite-devel \
      zlib-devel; \
  elif command -v dnf >/dev/null 2>&1; then \
    dnf groupinstall 'Development Tools' -y && dnf install -y \
      gcc \
      ncurses-devel \
      openssl-devel \
      bzip2-devel \
      libffi-devel \
      glibc-devel \
      sqlite-devel \
      zlib-devel; \
  elif command -v zypper >/dev/null 2>&1; then \
    echo "Zypper is not supported yet in our system."; exit 1; \
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

# Create the build directory for Python and give permissions to the user
RUN mkdir -p "${FE_DIR}/build" && chown -R ${UID}:${GID} "${FE_DIR}/build"
RUN mkdir -p "${FE_DIR}/python" && chown -R ${UID}:${GID} "${FE_DIR}/python"

USER factoryengine
WORKDIR ${FE_DIR}/build

# Download the Python source code
RUN wget "https://www.python.org/ftp/python/${PYTHON_VERSION}/Python-${PYTHON_VERSION}.tgz"
RUN tar -xvf "Python-${PYTHON_VERSION}.tgz" -C "${FE_DIR}/build" --strip-components=1

# Build Python from source
RUN ./configure --prefix="${FE_DIR}/python" \
    --enable-shared  \
    --with-openssl=/usr \
    --with-openssl-rpath=auto \
    --enable-shared
RUN make -j$(nproc)
RUN make install -j$(nproc)

RUN mkdir -p /home/factoryengine/out

# Next, create the symlink for `python` inside `${FE_DIR}/python`
WORKDIR ${FE_DIR}/python
RUN ln -s ./bin/python3 ./python
RUN tar cvf - . | gzip -9  - > "/home/factoryengine/out/python-${PYTHON_VERSION}-$(grep '^ID=' /etc/os-release | awk -F'=' '{print $2}')_$(grep -oP '^VERSION=\"\d+.*$' /etc/os-release | sed -n 's/VERSION=\"\([0-9]*\).*/\1/p')_$(uname -m).tar.gz"

WORKDIR /home/factoryengine
