# Use exactly the Go release src/go.mod requires; GOTOOLCHAIN=local stops go from
# auto-downloading a read-only toolchain into the shared $GOPATH module cache.
export GO_VERSION := $(shell awk '$$1 == "go" { print $$2; exit }' $(CURDIR)/../../go.mod)
export GO_LOCAL := $(CURDIR)/go_dist
export CONFIGURED_ARCH ?= amd64
export GOTOOLCHAIN := local
# Keep module cache dirs writable so other packages' "rm -rf $GOPATH" succeeds.
export GOFLAGS += -modcacherw

all: pkt-handler

# Asking the binary (not go_dist/VERSION) and extracting into .tmp means a partial
# download or a go_dist for another arch is never mistaken for a usable one.
pkt-handler:
	@if [ "$$($(GO_LOCAL)/bin/go env GOVERSION GOHOSTARCH 2>/dev/null | tr '\n' ' ')" != "go$(GO_VERSION) $(CONFIGURED_ARCH) " ]; then \
		echo "Downloading Go $(GO_VERSION)..."; \
		rm -rf $(GO_LOCAL) $(GO_LOCAL).tmp && \
		mkdir -p $(GO_LOCAL).tmp && \
		curl -fL https://go.dev/dl/go$(GO_VERSION).linux-$(CONFIGURED_ARCH).tar.gz | tar -C $(GO_LOCAL).tmp --strip-components=1 -xz && \
		mv $(GO_LOCAL).tmp $(GO_LOCAL) || exit 1; \
	fi

	$(GO_LOCAL)/bin/go version
	$(GO_LOCAL)/bin/go build -buildvcs=false -o pkt-handler

install:
	install -D ./pkt-handler $(DESTDIR)/usr/bin/pkt-handler
	install -m 644 -D ./lucius-pkthandler.service $(DESTDIR)/lib/systemd/system/lucius-pkthandler.service

clean:
	rm -rf pkt-handler

.PHONY: all pkt-handler clean install
