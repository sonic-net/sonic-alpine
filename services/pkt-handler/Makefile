export GO_VERSION := 1.23.4
export GO_ROOT := /usr/lib/go-1.23

all: pkt-handler

pkt-handler:
	/usr/local/go/bin/go version

	echo "Installing Go $(GO_VERSION)...";
	cd /tmp
	sudo wget https://go.dev/dl/go$(GO_VERSION).linux-$(CONFIGURED_ARCH).tar.gz
	sudo tar -C /usr/lib -xzf go$(GO_VERSION).linux-${CONFIGURED_ARCH}.tar.gz
	sudo mv -f -T /usr/lib/go $(GO_ROOT)
	rm go$(GO_VERSION).linux-*.tar.gz;

	$(GO_ROOT)/bin/go build -o pkt-handler

install:
	install -D ./pkt-handler $(DESTDIR)/usr/bin/pkt-handler
	install -m 644 -D ./lucius-pkthandler.service $(DESTDIR)/lib/systemd/system/lucius-pkthandler.service

clean:
	rm -rf pkt-handler

.PHONY:
	clean install
