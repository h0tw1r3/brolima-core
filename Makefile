# core dependency
DEBIAN_VERSION ?= 13
DEBIAN_CODENAME ?= trixie
DEBIAN_BUILD ?= 20260525-2489
DEBIAN_IMAGE_BASE_URL ?= https://cloud.debian.org/images/cloud/$(DEBIAN_CODENAME)/$(DEBIAN_BUILD)

BINFMT_VERSION ?= deploy/v7.0.0-28
BINFMT_QEMU_VERSION ?= 7.0.0

# runtime
RUNTIME ?= docker

# docker
DOCKER_VERSION=29.3.1

# containerd dependency
NERDCTL_VERSION ?= 2.2.2
FLANNEL_VERSION ?= 1.9.0-flannel1
FLANNEL_MINI_VERSION ?= 1.9.0

# architecture defaults to the current system's.
OS_ARCH ?= $(shell uname -m)
ifeq ($(strip $(OS_ARCH)),arm64)
OS_ARCH = aarch64
endif

# OS_ARCH is derived from `uname -m` but the alternate architecture name (e.g. amd64, arm64)
# is required for Docker and asset downloads.
ARCH_x86_64 = amd64
ARCH_aarch64 = arm64
ARCH = $(shell echo "$(ARCH_$(OS_ARCH))")

# binfmt needs the opposite of OS_ARCH
BINFMT_ARCH = aarch64
ifeq ($(strip $(OS_ARCH)),aarch64)
BINFMT_ARCH = x86_64
endif

#
# targets
#

all: image

.PHONY: clean cloud-image
clean:
	rm -rf dist

cloud-image: dist/img/debian-$(DEBIAN_VERSION)-genericcloud-$(ARCH)-$(DEBIAN_BUILD).qcow2.sha512sum

dist/img/debian-$(DEBIAN_VERSION)-genericcloud-$(ARCH)-$(DEBIAN_BUILD).qcow2:
	@mkdir -p dist/img && cd dist/img && curl -L -O -C - $(DEBIAN_IMAGE_BASE_URL)/$(notdir $@)

dist/img/debian-$(DEBIAN_VERSION)-genericcloud-$(ARCH)-$(DEBIAN_BUILD).qcow2.sha512sum: dist/img/debian-$(DEBIAN_VERSION)-genericcloud-$(ARCH)-$(DEBIAN_BUILD).qcow2
	@shasum -a 512 $< > $@.tmp
	@cd dist/img && ( curl -sL $(DEBIAN_IMAGE_BASE_URL)/SHA512SUMS | grep "debian-$(DEBIAN_VERSION)-genericcloud-$(ARCH)-$(DEBIAN_BUILD)\.qcow2" | shasum -a 512 --check --status )
	@mv $@.tmp $@

binfmt:
	ARCH=$(ARCH) BINFMT_ARCH=$(BINFMT_ARCH) BINFMT_VERSION=$(BINFMT_VERSION) BINFMT_QEMU_VERSION=$(BINFMT_QEMU_VERSION) scripts/binfmt.sh

containerd:
	ARCH=$(ARCH) NERDCTL_VERSION=$(NERDCTL_VERSION) FLANNEL_VERSION=$(FLANNEL_VERSION) FLANNEL_MINI_VERSION=$(FLANNEL_MINI_VERSION) RUNTIME=$(RUNTIME) scripts/containerd.sh

image: cloud-image binfmt containerd
	ARCH=$(ARCH) BINFMT_ARCH=$(BINFMT_ARCH) DEBIAN_VERSION=$(DEBIAN_VERSION) DOCKER_VERSION=$(DOCKER_VERSION) RUNTIME=$(RUNTIME) scripts/image.docker.sh
