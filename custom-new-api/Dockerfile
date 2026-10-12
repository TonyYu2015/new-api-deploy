ARG UPSTREAM_COMMIT=c6741c36a9a1a729554ad94ee99f21602a214a23
ARG UPSTREAM_VERSION=v1.0.0-rc.43

FROM alpine/git:2.49.1@sha256:c0280cf9572316299b08544065d3bf35db65043d5e3963982ec50647d2746e26 AS source
ARG UPSTREAM_COMMIT
RUN git init /src \
    && cd /src \
    && git remote add origin https://github.com/QuantumNous/new-api.git \
    && git fetch --depth 1 origin "${UPSTREAM_COMMIT}" \
    && git checkout --detach FETCH_HEAD \
    && test "$(git rev-parse HEAD)" = "${UPSTREAM_COMMIT}"
COPY custom-new-api/ccai.patch /tmp/ccai.patch
COPY custom-new-api/waffo-pancake-min-topup.patch /tmp/waffo-pancake-min-topup.patch
COPY custom-new-api/pancake-balance-baseline.patch /tmp/pancake-balance-baseline.patch
COPY custom-new-api/tiered-price-summary.patch /tmp/tiered-price-summary.patch
RUN cd /src \
    && git apply --check /tmp/ccai.patch \
    && git apply /tmp/ccai.patch \
    && git apply --check /tmp/waffo-pancake-min-topup.patch \
    && git apply /tmp/waffo-pancake-min-topup.patch \
    && git apply --check /tmp/pancake-balance-baseline.patch \
    && git apply /tmp/pancake-balance-baseline.patch \
    && git apply --check /tmp/tiered-price-summary.patch \
    && git apply /tmp/tiered-price-summary.patch

FROM oven/bun:1.4.0@sha256:5ff609364c049b54eb0ff560ec96319729a972078ef2c755d758f0c6ef89c2d6 AS builder
ARG UPSTREAM_VERSION
WORKDIR /build/web
COPY --from=source /src/web/package.json /src/web/bun.lock ./
RUN bun install --frozen-lockfile
COPY --from=source /src/web ./
RUN DISABLE_ESLINT_PLUGIN='true' \
    VITE_REACT_APP_VERSION="${UPSTREAM_VERSION}-ccai.1" \
    bun run build

FROM golang:1.26.1-alpine@sha256:2389ebfa5b7f43eeafbd6be0c3700cc46690ef842ad962f6c5bd6be49ed82039 AS builder2
ENV GO111MODULE=on CGO_ENABLED=0 GOWORK=off
# proxy.golang.org is not directly reachable from this build network (Google
# endpoints time out); use the Qiniu mirror with a direct-VCS fallback.
ENV GOPROXY=https://goproxy.cn,direct
ARG TARGETOS
ARG TARGETARCH
ARG UPSTREAM_VERSION
ENV GOOS=${TARGETOS:-linux} GOARCH=${TARGETARCH:-amd64}
ENV GOEXPERIMENT=greenteagc
WORKDIR /build
COPY --from=source /src/go.mod /src/go.sum ./
# relaykit and tokenkit are local submodules referenced via replace; their
# go.mod files must be present for go mod download to resolve the main module graph.
COPY --from=source /src/relaykit/go.mod ./relaykit/go.mod
COPY --from=source /src/tokenkit/go.mod ./tokenkit/go.mod
RUN go mod download
COPY --from=source /src .
COPY --from=builder /build/web/dist ./web/dist
RUN go build \
    -pgo="$(go list -m -f '{{.Dir}}' github.com/Calcium-Ion/moejs)/default.pgo" \
    -ldflags "-s -w -X 'github.com/QuantumNous/new-api/common.Version=${UPSTREAM_VERSION}-ccai.1'" \
    -o new-api

FROM debian:bookworm-slim@sha256:f06537653ac770703bc45b4b113475bd402f451e85223f0f2837acbf89ab020a
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates tzdata libasan8 wget \
    && rm -rf /var/lib/apt/lists/* \
    && update-ca-certificates
COPY --from=builder2 /build/new-api /
COPY --from=source /src/LICENSE /src/NOTICE /src/THIRD-PARTY-LICENSES.md /licenses/
EXPOSE 3000
WORKDIR /data
ENTRYPOINT ["/new-api"]
