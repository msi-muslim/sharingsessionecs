FROM golang:1.22-alpine AS builder
WORKDIR /app
COPY go.mod ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -o prabogo-app ./cmd

FROM gcr.io/distroless/base-debian12
WORKDIR /app
COPY --from=builder /app/prabogo-app .
EXPOSE 8080
CMD ["./prabogo-app"]
