#!/bin/sh

sudo podman build \
  -t localhost/mycloud-builder \
  -f docker/Dockerfile

sudo podman run -it --rm \
  --name mycloud-builder \
  -v $(pwd):/build:z \
  --privileged \
  --cap-add mknod \
  --device-cgroup-rule='b 8:* rmw' \
  localhost/mycloud-builder
