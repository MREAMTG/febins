#!/bin/env bash

set -euo pipefail

docker run --privileged --name binfmt --rm tonistiigi/binfmt --install all

COMPOSE_FILE="docker-compose.yaml"

if [[ ! -f "${COMPOSE_FILE}" ]]; then
  echo "Missing ${COMPOSE_FILE}. Run from the repo root."
  exit 1
fi

ALL_OUTPUTS=(python cpp valgrind doxygen)
ALL_PLATFORMS=(amd64 arm64)
ALL_OSES=(
  "ubuntu:focal"
  "ubuntu:jammy"
  "ubuntu:noble"
  "ubuntu:resolute"
  "debian:bullseye"
  "debian:bookworm"
  "debian:trixie"
  "alpine:3.23"
)

usage() {
  cat <<EOF
Usage: $0 [--platform=amd64,arm64] [--os=ubuntu:jammy,debian:bookworm] [--output=python,gcc]

Examples:
  $0
  $0 --platform=amd64
  $0 --os=ubuntu:jammy,ubuntu:noble
  $0 --output=python
  $0 --platform=amd64,arm64 --os=ubuntu:jammy --output=python,gdb
EOF
  exit 1
}

normalize_platform() {
  local p="$1"
  if [[ "$p" == */* ]]; then
    echo "${p##*/}"
  else
    echo "$p"
  fi
}

split_csv() {
  local input="$1"
  local -n out_arr=$2
  IFS=',' read -ra out_arr <<< "$input"
}

platform_filter=()
os_filter=()
output_filter=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --platform=*)
      split_csv "${1#*=}" platform_filter
      shift
      ;;
    --os=*)
      split_csv "${1#*=}" os_filter
      shift
      ;;
    --output=*)
      split_csv "${1#*=}" output_filter
      shift
      ;;
    -h|--help)
      usage
      ;;
    *)
      echo "Unknown argument: $1"
      usage
      ;;
  esac
done

if [[ ${#platform_filter[@]} -eq 0 ]]; then
  platform_filter=("${ALL_PLATFORMS[@]}")
fi
if [[ ${#os_filter[@]} -eq 0 ]]; then
  os_filter=("${ALL_OSES[@]}")
fi
if [[ ${#output_filter[@]} -eq 0 ]]; then
  output_filter=("${ALL_OUTPUTS[@]}")
fi

services=()
for output in "${output_filter[@]}"; do
  case "$output" in
    python|cpp|valgrind|doxygen) : ;;
    *)
      echo "Unknown output: $output"
      exit 2
      ;;
  esac
  for os in "${os_filter[@]}"; do
    os_name="${os//:/-}"
    for platform in "${platform_filter[@]}"; do
      platform_norm="$(normalize_platform "$platform")"
      services+=("${output}-${os_name}-${platform_norm}")
    done
  done
done

if [[ ${#services[@]} -eq 0 ]]; then
  echo "No services selected. Check your filters."
  exit 2
fi

echo "Building selected services: ${services[*]}"
docker compose -f "${COMPOSE_FILE}" build --parallel "${services[@]}"
docker compose -f "${COMPOSE_FILE}" up --no-build --abort-on-container-exit --remove-orphans "${services[@]}"

echo "Finished mass build"
