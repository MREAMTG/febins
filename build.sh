#!/bin/env bash

set -e

# Parse build-id argument for unique container names
BUILD_ID=""
ARGS=()

while [[ $# -gt 0 ]]; do
  case $1 in
    --build-id)
      BUILD_ID="$2"
      shift 2
      ;;
    *)
      ARGS+=("$1")
      shift
      ;;
  esac
done

# Set unique container names
BINFMT_CONTAINER_NAME="binfmt${BUILD_ID:+_$BUILD_ID}"
DOCKER_CONTAINER_NAME="fe-bin-build${BUILD_ID:+_$BUILD_ID}"

echo "Using container names: $BINFMT_CONTAINER_NAME, $DOCKER_CONTAINER_NAME"

# Run binfmt with unique name
docker run --privileged --name "$BINFMT_CONTAINER_NAME" --rm tonistiigi/binfmt --install all
set +e

if [ -f .env ]; then
  source .env

  HAS_UID=0
  HAS_GID=0
  HAS_TZ=0

  while IFS= read -r line || [[ -n "$line" ]]; do
    # Use awk to split the line into the variable name and value
    var_name=$(echo "$line" | awk -F'=' '{print $1}')
    var_value=$(echo "$line" | awk -F'=' '{print $2}')

    # Check if the variable is UID, GID, or TZ
    if [ "$var_name" == "UID" ]; then
      HAS_UID=1
    elif [ "$var_name" == "GID" ]; then
      HAS_GID=1
    elif [ "$var_name" == "TZ" ]; then
      HAS_TZ=1
    fi

    # Append the variable as a build argument
    build_args="$build_args --build-arg $var_name=$var_value"
  done <.env

  if [ $HAS_UID -eq 0 ]; then
    build_args="$build_args --build-arg UID=$(id -u)"
  fi

  if [ $HAS_GID -eq 0 ]; then
    build_args="$build_args --build-arg GID=$(id -g)"
  fi

  if [ $HAS_TZ -eq 0 ]; then
    build_args="$build_args --build-arg TZ=$(cat /etc/timezone)"
  fi

  echo "Build arguments: $build_args\n"

  docker build \
    $build_args \
    -f ./Dockerfile \
    -t ${DOCKER_CONTAINER_NAME} \
    "${ARGS[@]}" \
    .
    # --progress=plain \
    # --no-cache \
    SUCCESS=$?
else
  docker build \
    --build-arg UID=$(id -u) \
    --build-arg GID=$(id -g) \
    --build-arg TZ=$(cat /etc/timezone) \
    -f ./Dockerfile \
    -t ${DOCKER_CONTAINER_NAME} \
    "${ARGS[@]}" \
    .
    # --progress=plain \
    # --no-cache \
    SUCCESS=$?
fi


if [ $SUCCESS -eq 0 ]; then
  echo "Building complete, copying data..."
  set -e
  docker run --name ${DOCKER_CONTAINER_NAME} ${DOCKER_CONTAINER_NAME}
  set +e

  # Create unique output directory
  OUT_DIR="out${BUILD_ID:+_$BUILD_ID}"
  docker cp ${DOCKER_CONTAINER_NAME}:/home/factoryengine/out "$OUT_DIR"

  docker stop ${DOCKER_CONTAINER_NAME}
  docker rm ${DOCKER_CONTAINER_NAME}
  echo "Finished - output in $OUT_DIR"
else
  echo "Building Failed or canceled"
fi

exit ${SUCCESS}