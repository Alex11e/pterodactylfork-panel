FROM golang:1.24.11-alpine AS build
ARG WINGS_REF=d6116827313dae176ddf4741e233554392993398
RUN apk add --no-cache git mailcap
WORKDIR /src
RUN git init && git remote add origin https://github.com/Alex11e/wings.git \
    && git fetch --depth 1 origin "$WINGS_REF" && git checkout --detach FETCH_HEAD
RUN CGO_ENABLED=0 go build -trimpath -ldflags '-s -w' -o /wings wings.go
FROM alpine:3.22
RUN apk add --no-cache ca-certificates tzdata
COPY --from=build /wings /usr/local/bin/wings
COPY --from=build /etc/mime.types /etc/mime.types
ENTRYPOINT ["/usr/local/bin/wings"]
