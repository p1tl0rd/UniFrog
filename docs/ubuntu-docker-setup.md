# Ubuntu 24.04 & Docker Development Setup

Short guide for building and verifying UniFrog on Ubuntu 24.04 (native or
Docker) and Ubuntu 22.04 without root-only assumptions.

## 1. Host Packages (Native Ubuntu 24.04)

```sh
sudo apt-get update && sudo apt-get install -y \
  git make gcc g++ perl device-tree-compiler tcc zlib1g-dev \
  ccache curl xz-utils zip pkg-config libxcb1-dev ripgrep ca-certificates
```

`make deps-ubuntu` prints the same package list. `tcc` speeds up host checks;
if absent, `HOSTCC` automatically falls back to `gcc`.

## 2. Ubuntu 24.04 Docker Setup

Save a minimal image locally (keep Dockerfiles untracked unless shared):

```dockerfile
FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates ccache curl device-tree-compiler g++ gcc git \
      libxcb1-dev make perl pkg-config ripgrep tcc xz-utils zip zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*

# Reuse the built-in non-root `ubuntu` user (UID/GID 1000) to avoid root-owned
# files in the bind-mounted workspace.
USER ubuntu
WORKDIR /workspace/UniFrog
```

Build and run the container with the repo and ccache mounted:

```sh
docker build -t unifrog-dev -f Dockerfile.ubuntu24 .

docker run --rm -it \
  -v "$PWD:/workspace/UniFrog" \
  -v unifrog-ccache:/home/ubuntu/.cache/ccache \
  -e CCACHE_DIR=/home/ubuntu/.cache/ccache \
  unifrog-dev bash
```

If your host UID/GID is not `1000:1000`, pass `--user "$(id -u):$(id -g)"` and
`-e HOME=/tmp` (with `-e CCACHE_DIR=/tmp/ccache` or a writable bind mount).

Optional X11 forwarding for `make host-frontend-run` / `make linux-xcb-run`:

```sh
docker run --rm -it \
  -e DISPLAY="$DISPLAY" \
  -v /tmp/.X11-unix:/tmp/.X11-unix:ro \
  -v "$PWD:/workspace/UniFrog" \
  -v unifrog-ccache:/home/ubuntu/.cache/ccache \
  -e CCACHE_DIR=/home/ubuntu/.cache/ccache \
  unifrog-dev bash
```

## 3. First Setup & Verification

Inside the workspace (host or container):

```sh
# 1. Fetch MIPS toolchain (.deps/), SDK submodule, FFmpeg, LVGL, JS2300, fast cores
make setup JOBS=$(nproc)

# 2. Verify toolchain and dependency layout
make doctor

# 3. Fast dev loop (host checks, firmware link, one quick core)
make dev-check QUICK_CORE=quicknes JOBS=$(nproc)

# 4. Full verification (required before handoff; run `make clean && make verify`
#    after editing Makefiles, linker scripts, or dependency wiring)
make verify JOBS=$(nproc)
```

## 4. Building Firmware & Full SD-Card Zip

```sh
# Firmware + fast cores (everyday iteration)
make JOBS=$(nproc)

# Single core
make CORE=quicknes JOBS=$(nproc)

# Full SD-card release zip (includes slow cores: fbalpha2012, mame2000,
# gpsp, gpsp-gbac-prosty, picodrive, qpsx)
make -C cores deps FAST_BUILD=0 JOBS=$(nproc)
make sd-zip JOBS=$(nproc)
```

Output artifacts:

- `bisrv.asd` — standalone SF2000 boot image
- `output/unifrog.bin` — firmware payload
- `output/UniFrog-sdcard.zip` — complete SD-card package

Notes:

- Do not pass `-j1` to `make sd-zip`; the root `Makefile` skips `-j$(JOBS)`
  when `-j` is already set, forcing slow cores like `mame2000` and
  `fbalpha2012` to compile single-threaded.
- Never commit `.deps/`, `build/`, `output/`, or `bisrv.asd`. Run `make setup`
  (or `make deps`) to restore `.deps/` on a fresh checkout.
