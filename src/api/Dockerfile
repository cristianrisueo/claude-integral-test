# The API image that ships: a static linux/amd64 binary on distroless,
# listening on 8080. VERSION is the git commit SHA, baked in at link time;
# a build without it reports "dev".
FROM --platform=$BUILDPLATFORM golang:1.27 AS build
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY . .
ARG VERSION=dev
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 \
    go build -trimpath -ldflags "-s -w -X main.version=${VERSION}" -o /out/api ./cmd/api

FROM --platform=linux/amd64 gcr.io/distroless/static-debian12:nonroot
COPY --from=build /out/api /api
EXPOSE 8080
ENTRYPOINT ["/api"]
