#!/bin/sh

podman build \
  -t localhost/mycloud-builder \
  -f docker/Dockerfile

podman rm mycloud-builder -f

podman run -it --rm \
  --name mycloud-builder \
  -v $(pwd):/build:z \
  --privileged \
  localhost/mycloud-builder
