#!/bin/sh
getenforce && SELINUX=':z'

docker build \
  -t localhost/mycloud-builder \
  -f docker/Dockerfile

docker rm mycloud-builder -f

docker run -it --rm \
  --name mycloud-builder \
  -v $(pwd):/build${SELINUX} \
  --privileged \
  localhost/mycloud-builder
