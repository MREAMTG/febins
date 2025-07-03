#!/bin/env bash

set -e

# Create logs directory
mkdir -p build_logs

# Function to run a single build with logging
run_build() {
    local name="$1"
    local build_image="$2"
    local platform="$3"
    local unique_id="$4"
    local log_file="build_logs/${name// /_}.log"

    echo "Starting: $name" | tee "$log_file"
    echo "$(date): Starting build for $name" >> "$log_file"

    # Pass unique ID to build script to avoid container name conflicts
    if ./build.sh --build-arg BUILD_IMAGE="$build_image" --build-arg PLATFORM="$platform" --build-id "$unique_id" >> "$log_file" 2>&1; then
        echo "✅ COMPLETED: $name" | tee -a "$log_file"
        echo "$(date): Build completed successfully for $name" >> "$log_file"
        return 0
    else
        echo "❌ FAILED: $name" | tee -a "$log_file"
        echo "$(date): Build failed for $name" >> "$log_file"
        return 1
    fi
}

# Array to store background process PIDs
declare -a pids=()
declare -a build_names=()

echo "Starting parallel builds..."
echo "Logs will be written to build_logs/ directory"
echo "Cleaning up any existing containers..."

# Clean up any existing containers that might conflict
docker rm -f binfmt 2>/dev/null || true

echo "=========================================="

# Start all builds in parallel
run_build "ubuntu:bionic x86_64" "ubuntu:bionic-20210512" "linux/amd64" "1" &
pids+=($!)
build_names+=("ubuntu:bionic x86_64")

run_build "ubuntu:focal x86_64" "ubuntu:focal" "linux/amd64" "2" &
pids+=($!)
build_names+=("ubuntu:focal x86_64")

run_build "ubuntu:jammy x86_64" "ubuntu:jammy" "linux/amd64" "3" &
pids+=($!)
build_names+=("ubuntu:jammy x86_64")

run_build "ubuntu:noble x86_64" "ubuntu:noble" "linux/amd64" "4" &
pids+=($!)
build_names+=("ubuntu:noble x86_64")

run_build "debian:bookworm x86_64" "debian:bookworm" "linux/amd64" "5" &
pids+=($!)
build_names+=("debian:bookworm x86_64")

run_build "debian:bullseye x86_64" "debian:bullseye" "linux/amd64" "6" &
pids+=($!)
build_names+=("debian:bullseye x86_64")

# run_build "ubuntu:bionic aarch64" "ubuntu:bionic-20210512" "linux/arm64" "7" &
# pids+=($!)
# build_names+=("ubuntu:bionic aarch64")

# run_build "ubuntu:focal aarch64" "ubuntu:focal" "linux/arm64" "8" &
# pids+=($!)
# build_names+=("ubuntu:focal aarch64")

# run_build "ubuntu:jammy aarch64" "ubuntu:jammy" "linux/arm64" "9" &
# pids+=($!)
# build_names+=("ubuntu:jammy aarch64")

# run_build "ubuntu:noble aarch64" "ubuntu:noble" "linux/arm64" "10" &
# pids+=($!)
# build_names+=("ubuntu:noble aarch64")

# run_build "debian:bookworm aarch64" "debian:bookworm" "linux/arm64" "11" &
# pids+=($!)
# build_names+=("debian:bookworm aarch64")

# run_build "debian:bullseye aarch64" "debian:bullseye" "linux/arm64" "12" &
# pids+=($!)
# build_names+=("debian:bullseye aarch64")

echo "All builds started. Monitoring progress..."
echo "You can check individual logs with: tail -f build_logs/<build_name>.log"
echo ""

# Monitor progress
failed_builds=()
completed_count=0
total_builds=${#pids[@]}

while [ $completed_count -lt $total_builds ]; do
    for i in "${!pids[@]}"; do
        pid=${pids[$i]}
        if [ -n "$pid" ]; then
            if ! kill -0 "$pid" 2>/dev/null; then
                # Process has finished
                if wait "$pid"; then
                    echo "✅ Completed: ${build_names[$i]}"
                else
                    echo "❌ Failed: ${build_names[$i]}"
                    failed_builds+=("${build_names[$i]}")
                fi
                pids[$i]=""  # Clear the PID
                ((completed_count++))
            fi
        fi
    done

    # Show progress
    echo "Progress: $completed_count/$total_builds builds completed"

    # Wait a bit before checking again
    sleep 5
done

echo ""
echo "=========================================="
echo "All builds completed!"
echo "Successful builds: $((total_builds - ${#failed_builds[@]}))/$total_builds"

# List output directories
if [ $((total_builds - ${#failed_builds[@]})) -gt 0 ]; then
    echo ""
    echo "Output directories created:"
    for i in {1..12}; do
        if [ -d "out_$i" ]; then
            echo "  - out_$i"
        fi
    done
fi

if [ ${#failed_builds[@]} -gt 0 ]; then
    echo "Failed builds:"
    for build in "${failed_builds[@]}"; do
        echo "  - $build"
    done
    echo ""
    echo "Check logs in build_logs/ directory for details"
    exit 1
else
    echo "All builds completed successfully!"
fi