FROM debian:trixie-slim

RUN apt-get -y update \
 && apt-get -y dist-upgrade \
 && apt-get -y --no-install-recommends install wget curl ca-certificates unzip \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/*
