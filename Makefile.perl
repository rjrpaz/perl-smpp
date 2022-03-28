PERL=/usr/bin/perl -wc

# Directorio donde se ubicaran los modulos de perl.
# perl -e 'print "@INC \n";'
#PMDIR=/usr/local/lib/site_perl/i386-linux
#PMDIR=/usr/lib/perl5/site_perl/5.005
PMDIR=/usr/local/lib/perl5/site_perl

# Directorio donde se ubicaran los archivos binarios.
BINDIR=/usr/sbin

all: #crypt
	/usr/bin/clear
	@echo
	$(PERL) BelMon.pm
	@echo
	$(PERL) BelMonIn.pl
	@echo

#crypt: crypt.c
#	cc -o crypt crypt.c -lcrypt

install:
#	tar cvfz BelMon.tgz Makefile BelMonIn.pl BelMon.pm
	install -m 700 BelMon.pm $(PMDIR)/BelMon.pm
	install -m 700 BelMonIn.pl $(BINDIR)/BelMonIn

