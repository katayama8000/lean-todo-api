FROM ubuntu:24.04 AS toolchain
ARG TARGETARCH
WORKDIR /app
COPY lean-toolchain .
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates curl zstd \
    && rm -rf /var/lib/apt/lists/*
RUN case "$TARGETARCH" in arm64) platform=linux_aarch64 ;; amd64) platform=linux ;; *) exit 1 ;; esac \
    && version=$(sed 's|leanprover/lean4:v||' lean-toolchain) \
    && curl -fsSL --retry 3 "https://github.com/leanprover/lean4/releases/download/v$version/lean-$version-$platform.tar.zst" -o /tmp/lean.tar.zst \
    && mkdir /opt/lean \
    && tar --zstd -xf /tmp/lean.tar.zst -C /opt/lean --strip-components=1 \
    && rm /tmp/lean.tar.zst
ENV PATH="/opt/lean/bin:$PATH"

FROM toolchain AS build
COPY lakefile.toml Main.lean ./
COPY TodoApi ./TodoApi
RUN lake build

FROM ubuntu:24.04
RUN apt-get update && apt-get install -y --no-install-recommends sqlite3 \
    && rm -rf /var/lib/apt/lists/* \
    && mkdir /data && chown 65532:65532 /data
COPY --from=build /app/.lake/build/bin/lean-todo-api /usr/local/bin/lean-todo-api
USER 65532:65532
ENV TODO_BIND=0.0.0.0 TODO_DB=/data/todos.sqlite3 TODO_PORT=8080
EXPOSE 8080
ENTRYPOINT ["/usr/local/bin/lean-todo-api"]
