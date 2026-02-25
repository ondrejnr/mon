#!/bin/bash
# Spustenie inštalácie s tokenom ako argumentom
docker run --rm --privileged --net=host \
  -v /:/host \
  -v /run/systemd:/run/systemd \
  -v /etc/rancher/k3s:/etc/rancher/k3s \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -e GITHUB_TOKEN="${1:-$GITHUB_TOKEN}" \
  ondrejnr1/mon:latest
