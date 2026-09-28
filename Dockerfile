FROM debian:bookworm-slim@sha256:ef95d00655aa3f6c23fdda5ff7c153010abc86e77bd4e0147bada04115e5d705 AS builder

ARG STRFRY_VERSION=1.1.3
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates git g++ make libssl-dev zlib1g-dev liblmdb-dev \
    libflatbuffers-dev libsecp256k1-dev libzstd-dev && \
    rm -rf /var/lib/apt/lists/*
WORKDIR /build
RUN git clone --branch "${STRFRY_VERSION}" --depth 1 --recurse-submodules https://github.com/hoytech/strfry.git . && \
    make setup-golpe && make -j"$(nproc)"

FROM cloudron/base:5.1.0@sha256:1c0666c9abe9e2090d33686826d4e97769b799124573118d41e0d7485135748e

LABEL org.opencontainers.image.source="https://github.com/marcusquinn/cloudron-nostr-relay-app"

RUN apt-get update && apt-get install -y --no-install-recommends \
    libflatbuffers2 liblmdb0 libsecp256k1-1 libzstd1 python3 && \
    rm -rf /var/lib/apt/lists/*

COPY --from=builder /build/strfry /app/code/strfry
COPY --from=builder /build/LICENSE /app/code/licenses/strfry-GPL-3.0.txt
COPY start.sh /app/code/start.sh
COPY plugins/allowlist.py /app/code/plugins/allowlist.py
RUN chmod 755 /app/code/strfry /app/code/start.sh /app/code/plugins/allowlist.py

EXPOSE 7777
CMD ["/app/code/start.sh"]
