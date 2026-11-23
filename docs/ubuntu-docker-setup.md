# Ubuntu 24.04 & Docker Development Setup

Short guide for building and verifying UniFrog on Ubuntu 24.04 (native or
Docker) and Ubuntu 22.04 without root-only assumptions.

## 1. Host Packages (Native Ubuntu 24.04)

```sh
sudo apt-get update && sudo apt-get install -y \
  git make gcc g++ patch perl device-tree-compiler zlib1g-dev \
  ccache curl xz-utils zip unzip pkg-config libxcb1-dev ripgrep ca-certificates
```

On Ubuntu 24.04, `tcc` (0.9.27) rejects `-INFINITY` initializers in `js2300`, so
prefer `HOSTCC=gcc` (or omit `tcc`).

## 2. Ubuntu 24.04 Docker Setup

Build the reproducible image from the repository root [Dockerfile](../Dockerfile):

```sh
docker build -t unifrog-dev .

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
make -C cores init FAST_BUILD=0 JOBS=$(nproc)
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
