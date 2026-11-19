PREFIX ?= /usr/local
BINDIR  = $(DESTDIR)$(PREFIX)/bin
LISTDIR = $(DESTDIR)$(PREFIX)/share/lockin/lists

.PHONY: install uninstall test lint

install:
	install -d $(BINDIR) $(LISTDIR)
	install -m 755 bin/lockin $(BINDIR)/lockin
	install -m 644 lists/*.txt $(LISTDIR)/

uninstall:
	rm -f $(BINDIR)/lockin
	rm -rf $(DESTDIR)$(PREFIX)/share/lockin

test:
	bats test

lint:
	shellcheck bin/lockin
