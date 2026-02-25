#!/bin/bash
docker run --rm --privileged \
  -v /:/host \
  -v /run/systemd:/run/systemd \
  -v /etc/rancher/k3s:/etc/rancher/k3s \
  -v /usr/local/bin:/usr/local/bin \
  --net=host \
  ondrejnr1/mon-installer:latest
