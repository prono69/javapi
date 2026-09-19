# Stage 1: Build binary
FROM golang:1.26-alpine AS builder

# Install tzdata in builder stage if timezones are required by your app
RUN apk add --no-cache ca-certificates tzdata

WORKDIR /app

# Leverage layer caching: download dependencies before copying source code
COPY go.mod go.sum ./
RUN --mount=type=cache,target=/go/pkg/mod \
    go mod download

COPY . .

# Build statically linked binary with Go build cache enabled
RUN --mount=type=cache,target=/go/pkg/mod \
    --mount=type=cache,target=/root/.cache/go-build \
    CGO_ENABLED=0 GOOS=linux go build \
    -trimpath \
    -ldflags="-s -w" \
    -o /javapi ./cmd/api

# Stage 2: Final runtime image
FROM alpine:3.20

WORKDIR /

# Copy certificates and timezone data from builder (avoids extra apk layer)
COPY --from=builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/
COPY --from=builder /usr/share/zoneinfo /usr/share/zoneinfo

# Security: Run as a non-root user
RUN adduser -D -u 10001 appuser
USER appuser

COPY --from=builder --chown=appuser:appuser /javapi /javapi
COPY --chown=appuser:appuser configs/ /configs/

ENV GOMEMLIMIT=400MiB
EXPOSE 8080

ENTRYPOINT ["/javapi"]
