#!/bin/sh
getenforce && SELINUX=':z'

getenforce && SELINUX=':z'
which podman && alias docker=podman

# docker rm mycloud-builder -f

docker build \
  -t localhost/mycloud-builder \
  -f docker/Dockerfile

docker run -it --rm \
  --name mycloud-builder \
  -v $(pwd):/build${SELINUX} \
  --privileged \
  localhost/mycloud-builder
