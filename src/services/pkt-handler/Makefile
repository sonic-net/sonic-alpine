export GO_VERSION := 1.23.4
export GO_LOCAL := $(CURDIR)/go_dist
export CONFIGURED_ARCH ?= amd64

all: pkt-handler

pkt-handler:
	@if [ ! -f $(GO_LOCAL)/bin/go ]; then \
		echo "Downloading Go $(GO_VERSION)..."; \
		mkdir -p $(GO_LOCAL); \
		curl -L https://go.dev/dl/go$(GO_VERSION).linux-$(CONFIGURED_ARCH).tar.gz | tar -C $(GO_LOCAL) --strip-components=1 -xz; \
	fi

	$(GO_LOCAL)/bin/go version
	$(GO_LOCAL)/bin/go build -buildvcs=false -o pkt-handler

install:
	install -D ./pkt-handler $(DESTDIR)/usr/bin/pkt-handler
	install -m 644 -D ./lucius-pkthandler.service $(DESTDIR)/lib/systemd/system/lucius-pkthandler.service

clean:
	rm -rf pkt-handler

.PHONY:
	clean install
