# syntax=docker/dockerfile:1

# Stage 1: Build binary and dependencies
FROM golang:1.22-alpine AS builder

WORKDIR /build

# Install CA certificates and add an unprivileged non-root user
RUN apk --no-cache add ca-certificates && \
    adduser -D -g '' -u 10001 -s /sbin/nologin appuser

# Copy module definitions and pre-download dependencies for layer caching
COPY app/go.mod ./
RUN go mod download

# Copy source code
COPY app/ .

# Run tests to guarantee build integrity
RUN CGO_ENABLED=0 go test -v ./...

# Build statically linked binary with stripped symbols and trimmed paths
RUN CGO_ENABLED=0 GOOS=linux go build \
    -trimpath \
    -ldflags="-s -w" \
    -o /greeter .

# Stage 2: Minimal runtime image from scratch
FROM scratch

# Import CA certificates for TLS support
COPY --from=builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/

# Import unprivileged user credentials
COPY --from=builder /etc/passwd /etc/passwd
COPY --from=builder /etc/group /etc/group

# Import compiled static executable
COPY --from=builder /greeter /greeter

# Run as non-root user (UID 10001)
USER 10001:10001

# Document exposed HTTP port
EXPOSE 8080

# Execute the application directly as PID 1 to receive OS signals (SIGTERM/SIGINT) cleanly
ENTRYPOINT ["/greeter"]
