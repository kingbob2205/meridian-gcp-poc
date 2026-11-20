# Multi-stage hardened build: Go static binary -> distroless nonroot runtime.
FROM golang:1.23-alpine AS builder

WORKDIR /src
COPY go.mod main.go main_test.go ./

RUN go mod tidy && go test -v ./...

ARG GIT_SHA=unknown
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 \
    go build -trimpath -ldflags="-s -w -X main.gitCommit=${GIT_SHA}" \
    -o /out/meridian-api .

FROM gcr.io/distroless/static-debian12:nonroot

COPY --from=builder /out/meridian-api /meridian-api

USER nonroot:nonroot
EXPOSE 8080

ENTRYPOINT ["/meridian-api"]
