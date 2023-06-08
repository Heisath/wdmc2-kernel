# Build with docker / podman

```
podman build \
  -t localhost/mycloud-builder \
  -f docker/Dockerfile

podman run -it --rm \
  --name mycloud-builder \
  -v $(pwd):/build:z \
  --privileged \
  --cap-add mknod \
  --device-cgroup-rule='b 8:* rmw' \
  localhost/mycloud-builder
```
