# Build stage — compile the Go binary in a full Go image
FROM golang:1.23-alpine AS builder

WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download

COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -o server .

# Runtime stage — minimal Alpine image, only the binary and curl for the ECS health check
FROM alpine:3.20
RUN apk add --no-cache ca-certificates curl

WORKDIR /app
COPY --from=builder /app/server .

EXPOSE 8080
CMD ["./server"]
