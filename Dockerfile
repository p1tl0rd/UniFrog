FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive
ENV HOSTCC=gcc
ENV CCACHE_DIR=/home/ubuntu/.cache/ccache

RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates \
      ccache \
      curl \
      device-tree-compiler \
      g++ \
      gcc \
      git \
      libxcb1-dev \
      make \
      patch \
      perl \
      pkg-config \
      ripgrep \
      unzip \
      xz-utils \
      zip \
      zlib1g-dev \
    && rm -rf /var/lib/apt/lists/* \
    && mkdir -p /home/ubuntu/.cache/ccache \
    && chown -R ubuntu:ubuntu /home/ubuntu/.cache

# Reuse the built-in non-root `ubuntu` user (UID/GID 1000) to avoid root-owned
# files in the bind-mounted workspace on standard Linux developer machines.
USER ubuntu
RUN git config --global --add safe.directory /workspace/UniFrog
WORKDIR /workspace/UniFrog
