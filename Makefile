# Makefile

PROGS   	= podalyzer podfeeder runlogs.sh
PUBDOCS    	= docs/podalyzer.html docs/podfeeder.html
ARCDOCS    	= docs/podalyzer.txt docs/podfeeder.txt INSTALL.html INSTALL
TARGET  	= podalyzer

GPLSTUFF	= AUTHORS COPYING Changes README THANKS
DOCS		= $(PUBDOCS) $(ARCDOCS)
RELEASE		= $(PROGS) $(DOCS) $(GPLSTUFF)
REMDIR		= /usr/local/apache-php/home/hexten.net/htdocs
REMHOST 	= root@ferrous.hexten.net
DESTDIR		= rsync:$(REMHOST):$(REMDIR)/downloads
DOCDIR		= $(REMHOST):$(REMDIR)/docs/$(TARGET)
DESTURL		= http://hexten.net/downloads
TEMPLATE	= release.template
MAILTO		= andy@hexten.net
RSYNC		= rsync -avz -e ssh

default: INSTALL

INSTALL.html: docs/header.html docs/body.html docs/footer.html
	cat docs/header.html docs/body.html docs/footer.html > $@

INSTALL: INSTALL.html
	lynx --dump --width=72 $< > $@

# TODO: Find out how to make this generic
docs/podalyzer.html: podalyzer
	pod2html $< > $@

docs/podfeeder.html: podfeeder
	pod2html $< > $@

docs/podalyzer.txt: podalyzer
	pod2text $< > $@

docs/podfeeder.txt: podfeeder
	pod2text $< > $@

release: $(RELEASE)
	./release.pl --target=$(TARGET) --destdir=$(DESTDIR) \
		--desturl=$(DESTURL) --template=$(TEMPLATE) \
		--mailto=$(MAILTO) $(RELEASE)
	$(RSYNC) $(PUBDOCS) $(DOCDIR)

update: $(PROGS)
	$(RSYNC) $(PROGS) root@ferrous.hexten.net:/root/bin
	$(RSYNC) $(PROGS) root@ls244.burtondns.org:/root/bin
