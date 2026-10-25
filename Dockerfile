# Build and run on the same Cloudron base so strfry links against the runtime's
# own libraries.
FROM cloudron/base:6.0.1@sha256:7b1e729960c3ca312d26e886917ba89483241bba0219ff292858e10d9d5768ee AS builder

ARG STRFRY_VERSION=1.1.3
ARG STRFRY_COMMIT=16c00df04e264f4d68db5e10a48127f015c7824b
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates git g++ make libssl-dev zlib1g-dev liblmdb-dev \
    libflatbuffers-dev libsecp256k1-dev libzstd-dev && \
    rm -rf /var/lib/apt/lists/*
WORKDIR /build
RUN git clone --branch "${STRFRY_VERSION}" --depth 1 --recurse-submodules https://github.com/hoytech/strfry.git . && \
    test "$(git rev-parse HEAD)" = "${STRFRY_COMMIT}" && \
    make setup-golpe && make -j"$(nproc)"

FROM cloudron/base:6.0.1@sha256:7b1e729960c3ca312d26e886917ba89483241bba0219ff292858e10d9d5768ee

LABEL org.opencontainers.image.source="https://github.com/marcusquinn/cloudron-nostr-relay-app"

RUN apt-get update && apt-get install -y --no-install-recommends \
    liblmdb0 libsecp256k1-6 libzstd1 python3 && \
    rm -rf /var/lib/apt/lists/*

COPY --from=builder /build/strfry /app/code/strfry
COPY --from=builder /build/LICENSE /app/code/licenses/strfry-GPL-3.0.txt
COPY start.sh /app/code/start.sh
COPY plugins/allowlist.py /app/code/plugins/allowlist.py
RUN chmod 755 /app/code/strfry /app/code/start.sh /app/code/plugins/allowlist.py && \
    if ldd /app/code/strfry | grep -F 'not found'; then exit 1; fi

EXPOSE 7777
CMD ["/app/code/start.sh"]
