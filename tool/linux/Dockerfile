# Flutter cannot cross-compile a Linux desktop app, so each architecture
# builds in a container of its own. Ubuntu 22.04 keeps the glibc floor at
# 2.35, which every maintained desktop distribution clears.
FROM ubuntu:22.04

ARG FLUTTER_VERSION

RUN apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      ca-certificates curl git unzip xz-utils \
      clang cmake ninja-build pkg-config \
      libgtk-3-dev liblzma-dev libstdc++-12-dev \
 && rm -rf /var/lib/apt/lists/*

RUN git clone --depth 1 --branch "$FLUTTER_VERSION" \
      https://github.com/flutter/flutter.git /opt/flutter
ENV PATH=/opt/flutter/bin:$PATH
RUN flutter config --no-analytics --enable-linux-desktop \
 && flutter precache --linux
