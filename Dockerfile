# Multi-arch (linux/amd64 + linux/arm64): only the relay binary and its
# runtime libraries differ per architecture. The web build is the same for
# every target, so Flutter and the Dart compiler run once on the build
# machine's own platform, and no stage needs emulation.

#Stage 1 - Install dependencies and build the app in a build environment
FROM --platform=$BUILDPLATFORM debian:latest AS build-env
# Install flutter dependencies
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        curl \
        git \
        wget \
        unzip \
        gdb \
        libstdc++6 \
        libglu1-mesa \
        python3 \
        sed \
        ca-certificates \
        gnupg \
        lsb-release \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*
# Clone the flutter repo
RUN git clone https://github.com/flutter/flutter.git /usr/local/flutter
# Set flutter path
ENV PATH="${PATH}:/usr/local/flutter/bin:/usr/local/flutter/bin/cache/dart-sdk/bin"
# Run flutter doctor
RUN flutter doctor -v
RUN flutter channel master
RUN flutter upgrade
# Copy files to container and build
RUN mkdir /app/
COPY . /app/
WORKDIR /app/
# NATS_TCP_RELAY offers nats:// in the browser, connecting through the relay
# built below (see lib/tcp_relay.dart)
RUN flutter build web --dart-define=NATS_TCP_RELAY=true

# Stage 2 - Build the server: serves the web build and relays nats://
# connections from the browser to NATS servers over TCP
FROM --platform=$BUILDPLATFORM dart:stable AS relay-build
ARG TARGETARCH
WORKDIR /relay/
COPY docker/tcp_relay/pubspec.* ./
RUN dart pub get
COPY docker/tcp_relay/ ./
# Cross-compiles for the target; Docker says amd64 where Dart says x64
RUN dart compile exe bin/server.dart --target-os linux \
        --target-arch "$([ "$TARGETARCH" = amd64 ] && echo x64 || echo "$TARGETARCH")" \
        -o /relay/server

# The target platform's minimal runtime libraries (only copied from, never
# run, so no emulation)
FROM dart:stable AS relay-runtime

# Stage 3 - Create the run-time image: just the AOT-compiled server, the
# minimal runtime it needs (provided by the dart image) and the web build
FROM scratch
COPY --from=relay-runtime /runtime/ /
COPY --from=relay-build /relay/server /app/server
COPY --from=build-env /app/build/web /app/web
EXPOSE 80
ENTRYPOINT ["/app/server"]
