FROM docker.1ms.run/library/node:20-alpine AS frontend-builder
RUN npm install -g bun
ENV BUN_CONFIG_REGISTRY=https://registry.npmmirror.com
WORKDIR /build/web
COPY web/package.json ./
COPY web/default/package.json ./default/package.json
COPY web/classic/package.json ./classic/package.json
COPY web/bun.lock ./bun.lock
RUN cd default && bun install && bun run build
RUN cd classic && bun install && bun run build

FROM docker.1ms.run/library/golang:1.26.1-alpine AS backend-builder
ENV GO111MODULE=on CGO_ENABLED=0
ARG TARGETOS
ARG TARGETARCH
ENV GOOS=${TARGETOS:-linux} GOARCH=${TARGETARCH:-amd64}
ENV GOEXPERIMENT=greenteagc
WORKDIR /build
ADD go.mod go.sum ./
RUN go mod download
COPY . .
COPY --from=frontend-builder /build/web/default/dist ./web/default/dist
COPY --from=frontend-builder /build/web/classic/dist ./web/classic/dist
RUN go build -ldflags "-s -w -X 'github.com/QuantumNous/new-api/common.Version=$(cat VERSION)'" -o new-api

FROM docker.1ms.run/library/debian:bookworm-slim
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates tzdata libasan8 wget \
    && rm -rf /var/lib/apt/lists/* \
    && update-ca-certificates
COPY --from=backend-builder /build/new-api /
COPY LICENSE NOTICE THIRD-PARTY-LICENSES.md /licenses/
EXPOSE 3000
WORKDIR /data
ENTRYPOINT ["/new-api"]
