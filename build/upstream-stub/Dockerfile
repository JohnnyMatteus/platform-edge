# syntax=docker/dockerfile:1
FROM golang:1.25-alpine AS build
WORKDIR /src
COPY go.mod ./
COPY cmd ./cmd
COPY internal ./internal
RUN CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o /out/upstream-stub ./cmd/upstream-stub

FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=build /out/upstream-stub /upstream-stub
USER nonroot:nonroot
EXPOSE 8080
ENTRYPOINT ["/upstream-stub"]
