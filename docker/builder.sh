#!/bin/sh

docker build \
  -t localhost/mycloud-builder \
  -f docker/Dockerfile

docker rm mycloud-builder -f

docker run -it --rm \
  --name mycloud-builder \
  -v $(pwd):/build:z \
  --privileged \
  localhost/mycloud-builder
