all: pkt-handler

pkt-handler:
	/usr/local/go/bin/go version
	/usr/local/go/bin/go build -o pkt-handler

install:
	install -D ./pkt-handler $(DESTDIR)/usr/bin/pkt-handler
	install -m 644 -D ./lucius-pkthandler.service $(DESTDIR)/lib/systemd/system/lucius-pkthandler.service

clean:
	rm -rf pkt-handler

.PHONY:
	clean install
