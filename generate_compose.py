#!/usr/bin/env python3
"""
Generates docker-compose.yaml for all build targets and platforms.
Edit this file to add/change OSes, platforms, outputs, or version defaults.
Run:  python3 generate_compose.py
"""

VERSIONS = {
    "GCC_VERSION": "16.1.0",
    "GDB_VERSION": "17.1",
    "PYTHON_VERSION": "3.12.13",
    "VALGRIND_VERSION": "3.27.0",
    "DOXYGEN_VERSION": "1.17.0",
    "CMAKE_VERSION": "3.31.12",
    "LLVM_VERSION": "22",
    "UID": "1000",
    "GID": "1000",
    "TZ": "America/Toronto",
}

PLATFORMS = ["amd64", "arm64"]

BASE_OSES = {
    "ubuntu-focal": "ubuntu:focal",
    "ubuntu-jammy": "ubuntu:jammy",
    "ubuntu-noble": "ubuntu:noble",
    "ubuntu-resolute": "ubuntu:resolute",
    "debian-bullseye": "debian:bullseye",
    "debian-bookworm": "debian:bookworm",
    "debian-trixie": "debian:trixie",
}

# Extra OSes appended for specific outputs only
EXTRA_OSES = {
    "python": {"alpine-3.23": "alpine:3.23"},
}

OUTPUTS = {
    "gcc": "./docker/gcc.Dockerfile",
    "gdb": "./docker/gdb.Dockerfile",
    "python": "./docker/python.Dockerfile",
    "valgrind": "./docker/valgrind.Dockerfile",
    "doxygen": "./docker/doxygen.Dockerfile",
    "combined": "./docker/combined.Dockerfile",
}


def generate() -> str:
    lines = ["services:"]
    for output, dockerfile in OUTPUTS.items():
        oses = dict(BASE_OSES)
        if output in EXTRA_OSES:
            oses.update(EXTRA_OSES[output])

        section = output.upper()
        border = "#" * (len(section) + 6)
        lines.append(f"    {border}")
        lines.append(f"    # {section} #")
        lines.append(f"    {border}")

        for os_slug, os_image in oses.items():
            for platform in PLATFORMS:
                name = f"{output}-{os_slug}-{platform}"
                args = [f"BUILD_IMAGE={os_image}", f"PLATFORM=linux/{platform}"]
                for k, v in VERSIONS.items():
                    args.append(f"{k}={v}")
                lines.append(f"    {name}:")
                lines.append("        build:")
                lines.append("            context: .")
                lines.append(f"            dockerfile: {dockerfile}")
                lines.append("            args:")
                for arg in args:
                    lines.append(f"                - {arg}")
                lines.append(f"        platform: linux/{platform}")
                lines.append("        volumes:")
                lines.append("            - ./out:/out")
                lines.append(
                    '        command: ["/bin/sh", "-c", "cp -a /home/factoryengine/out/. /out"]'
                )
                lines.append("")

    return "\n".join(lines) + "\n"


if __name__ == "__main__":
    import os

    script_dir = os.path.dirname(os.path.abspath(__file__))
    out_path = os.path.join(script_dir, "docker-compose.yaml")
    content = generate()
    with open(out_path, "w") as f:
        f.write(content)
    services_count = content.count("\n        build:")
    print(f"Generated {out_path} ({services_count} services)")
