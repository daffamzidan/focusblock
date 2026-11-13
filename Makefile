PREFIX ?= /usr/local
BINDIR  = $(DESTDIR)$(PREFIX)/bin
LISTDIR = $(DESTDIR)$(PREFIX)/share/focusblock/lists

.PHONY: install uninstall test lint

install:
	install -d $(BINDIR) $(LISTDIR)
	install -m 755 bin/focusblock $(BINDIR)/focusblock
	install -m 644 lists/*.txt $(LISTDIR)/

uninstall:
	rm -f $(BINDIR)/focusblock
	rm -rf $(DESTDIR)$(PREFIX)/share/focusblock

test:
	bats test

lint:
	shellcheck bin/focusblock
