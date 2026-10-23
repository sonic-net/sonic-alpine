SHELL := /bin/bash
.SHELLFLAGS := -eu -o pipefail -c

LEMMING_SOURCE := $(abspath ../libsai-grpc/lemming)
BUILD_DIR := $(CURDIR)/build
GOARCH ?= $(shell dpkg-architecture -qDEB_HOST_ARCH)
export GOWORK := off
# Debhelper cleans its temporary HOME, including Go's downloaded module cache.
export GOFLAGS += -modcacherw

.PHONY: all lemctl test install clean
all: lemctl

lemctl:
	test -f "$(LEMMING_SOURCE)/go.mod"
	rm -rf "$(BUILD_DIR)"
	mkdir -p "$(BUILD_DIR)"
	git -C "$(LEMMING_SOURCE)" archive HEAD | tar -x -C "$(BUILD_DIR)"
	cd "$(BUILD_DIR)" && patch --batch --forward --fuzz=0 -p1 < "$(CURDIR)/patches/0001-luciusctl-transport-policy.patch"
	cd "$(BUILD_DIR)" && CGO_ENABLED=1 GOOS=linux GOARCH=$(GOARCH) go build -buildvcs=false -trimpath -ldflags="-s -w" -o "$(CURDIR)/lemctl" ./cmd/lemctl
	cd "$(BUILD_DIR)" && CGO_ENABLED=1 GOOS=linux GOARCH=$(GOARCH) python3 "$(CURDIR)/collect-notices.py" "$(CURDIR)/THIRD_PARTY_NOTICES"

test:
	python3 -m unittest discover -s tests -p 'test_*.py'
	cd "$(BUILD_DIR)" && go test -count=1 ./dataplane/luciusctl/...
	./tests/test-binary.sh ./lemctl

install:
	install -D -m 0755 lemctl "$(DESTDIR)/usr/bin/lemctl"
	install -D -m 0644 THIRD_PARTY_NOTICES "$(DESTDIR)/usr/share/lemctl/THIRD_PARTY_NOTICES"

clean:
	rm -rf "$(BUILD_DIR)"
	rm -f lemctl
	rm -f THIRD_PARTY_NOTICES
