#!/bin/env bash

set -e

echo "ubuntu:bionic x86_64" \
  && ./build.sh --build-arg BUILD_IMAGE=ubuntu:bionic-20210512   --build-arg PLATFORM=linux/amd64 \
  && echo "ubuntu:focal x86_64" \
  && ./build.sh --build-arg BUILD_IMAGE=ubuntu:focal             --build-arg PLATFORM=linux/amd64 \
  && echo "ubuntu:jammy x86_64" \
  && ./build.sh --build-arg BUILD_IMAGE=ubuntu:jammy             --build-arg PLATFORM=linux/amd64 \
  && echo "ubuntu:noble x86_64" \
  && ./build.sh --build-arg BUILD_IMAGE=ubuntu:noble             --build-arg PLATFORM=linux/amd64 \
  && echo "debian:bookworm x86_64" \
  && ./build.sh --build-arg BUILD_IMAGE=debian:bookworm          --build-arg PLATFORM=linux/amd64 \
  && echo "debian:bullseye x86_64" \
  && ./build.sh --build-arg BUILD_IMAGE=debian:bullseye          --build-arg PLATFORM=linux/amd64 \
  && echo "ubuntu:bionic aarch64" \
  && ./build.sh --build-arg BUILD_IMAGE=ubuntu:bionic-20210512   --build-arg PLATFORM=linux/arm64 \
  && echo "ubuntu:focal aarch64" \
  && ./build.sh --build-arg BUILD_IMAGE=ubuntu:focal             --build-arg PLATFORM=linux/arm64 \
  && echo "ubuntu:jammy aarch64" \
  && ./build.sh --build-arg BUILD_IMAGE=ubuntu:jammy             --build-arg PLATFORM=linux/arm64 \
  && echo "ubuntu:noble aarch64" \
  && ./build.sh --build-arg BUILD_IMAGE=ubuntu:noble             --build-arg PLATFORM=linux/arm64 \
  && echo "debian:bookworm aarch64" \
  && ./build.sh --build-arg BUILD_IMAGE=debian:bookworm          --build-arg PLATFORM=linux/arm64 \
  && echo "debian:bullseye aarch64" \
  && ./build.sh --build-arg BUILD_IMAGE=debian:bullseye          --build-arg PLATFORM=linux/arm64 \
  && echo "Finished mass build"