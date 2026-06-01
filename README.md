# brolima-core

Dependencies for [Brolima](https://github.com/h0tw1r3/brolima)

## Generating image

Generate a raw disk image compressed with gzip (`.raw.gz`) for the OS architecture and default runtime (docker).

```sh
make image
```

Generate a `.raw.gz` image for another architecture. `OS_ARCH` must be one of `aarch64`, `x86_64`

```sh
OS_ARCH=x86_64 make image
```

Generate a `.raw.gz` image for another runtime. `RUNTIME` must be one of `docker`, `containerd`, `incus`, `none`

```sh
RUNTIME=containerd make image
```
