# OpenResty

## Build image with podman

### Pass proxy arguments to podman build

```shell
podman login \
  --username=your@mail.domain \
  your.registry.domain

podman manifest create \
  your.registry.domain/dianplus/openresty:1.27.1.1-alpine

podman manifest create \
  your.registry.domain/dianplus/openresty:1.27.1.1-0-alpine

podman build \
  --build-arg NO_PROXY=192.168.*,10.*,172.*,mirrors.tuna.tsinghua.edu.cn,mirrors.aliyun.com,*.aliyun.com,*.aliyuncs.com,*.dianplus.cn,*.dianjia.io,*.taobao.com \
  --build-arg HTTP_PROXY=http://192.168.168.105:1088 \
  --build-arg HTTPS_PROXY=http://192.168.168.105:1088 \
  --platform linux/amd64,linux/arm64 \
  --manifest your.registry.domain/dianplus/openresty:1.27.1.1-alpine \
  .

podman manifest push \
  --all your.registry.domain/dianplus/openresty:1.27.1.1-alpine
```
