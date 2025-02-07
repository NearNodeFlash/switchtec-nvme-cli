CFLAGS ?= -O2 -g -Wall -Werror
override CFLAGS += -std=gnu99 -I.
override CPPFLAGS += -D_GNU_SOURCE -D__CHECK_ENDIAN__
LIBUUID = $(shell $(LD) -o /dev/null -luuid >/dev/null 2>&1; echo $$?)

NVME = switchtec-nvme
LIBHUGETLBFS = $(shell $(LD) -o /dev/null -lhugetlbfs >/dev/null 2>&1; echo $$?)
HAVE_SYSTEMD = $(shell pkg-config --exists libsystemd  --atleast-version=232; echo $$?)
INSTALL ?= install
DESTDIR =
DESTDIROLD = /usr/local/sbin
PREFIX ?= /usr
SYSCONFDIR = /etc
SBINDIR = $(PREFIX)/sbin
LIBDIR ?= $(PREFIX)/lib
SYSTEMDDIR ?= $(LIBDIR)/systemd
UDEVDIR ?= $(SYSCONFDIR)/udev
UDEVRULESDIR ?= $(UDEVDIR)/rules.d
DRACUTDIR ?= $(LIBDIR)/dracut
LIB_DEPENDS =

ifeq ($(LIBUUID),0)
	override LDFLAGS += -luuid
	override CFLAGS += -DLIBUUID
	override LIB_DEPENDS += uuid
endif

ifeq ($(LIBHUGETLBFS),0)
	override LDFLAGS += -lhugetlbfs
	override CFLAGS += -DLIBHUGETLBFS
	override LIB_DEPENDS += hugetlbfs
endif

INC=-Iutil -Iplugins/microchip 

ifeq ($(HAVE_SYSTEMD),0)
	override LDFLAGS += -lsystemd
	override CFLAGS += -DHAVE_SYSTEMD
endif

override LDFLAGS += -lswitchtec -lcrypto

RPMBUILD = rpmbuild
TAR = tar
RM = rm -f

AUTHOR=Keith Busch <kbusch@kernel.org>

ifneq ($(findstring $(MAKEFLAGS),s),s)
ifndef V
	QUIET_CC	= @echo '   ' CC $@;
endif
endif

QUIET_CC=

default: $(NVME)

NVME-VERSION-FILE:
	@$(SHELL_PATH) ./NVME-VERSION-GEN
-include NVME-VERSION-FILE
override CFLAGS += -DNVME_VERSION='"$(NVME_VERSION)"'

NVME_DPKG_VERSION=1~`lsb_release -sc`


OBJS := nvme-print.o nvme-ioctl.o \
	nvme-lightnvm.o fabrics.o nvme-models.o plugin.o \
	nvme-status.o nvme-filters.o nvme-topology.o

UTIL_OBJS := util/argconfig.o util/suffix.o util/json.o util/parser.o

PLUGIN_OBJS :=					\
	plugins/intel/intel-nvme.o		\
	plugins/lnvm/lnvm-nvme.o		\
	plugins/memblaze/memblaze-nvme.o	\
	plugins/wdc/wdc-nvme.o			\
	plugins/wdc/wdc-utils.o			\
	plugins/huawei/huawei-nvme.o		\
	plugins/netapp/netapp-nvme.o		\
	plugins/toshiba/toshiba-nvme.o		\
	plugins/micron/micron-nvme.o		\
	plugins/seagate/seagate-nvme.o 		\
	plugins/virtium/virtium-nvme.o		\
	plugins/shannon/shannon-nvme.o		\
	plugins/dera/dera-nvme.o            \
    plugins/transcend/transcend-nvme.o		\
	plugins/microchip/switchtec-nvme.o	\
	plugins/microchip/switchtec-nvme-device.o\
	plugins/microchip/rc-nvme-device.o

$(NVME): nvme.c nvme.h $(OBJS) $(PLUGIN_OBJS) $(UTIL_OBJS) NVME-VERSION-FILE
	$(QUIET_CC)$(CC) $(CPPFLAGS) $(CFLAGS) $(INC) $< -o $(NVME) $(OBJS) $(PLUGIN_OBJS) $(UTIL_OBJS) $(LDFLAGS)

verify-no-dep: nvme.c nvme.h $(OBJS) NVME-VERSION-FILE
	$(QUIET_CC)$(CC) $(CPPFLAGS) $(CFLAGS) $< -o $@ $(OBJS) $(LDFLAGS)

nvme.o: nvme.c nvme.h nvme-print.h nvme-ioctl.h util/argconfig.h util/suffix.h nvme-lightnvm.h fabrics.h
	$(QUIET_CC)$(CC) $(CPPFLAGS) $(CFLAGS) $(INC) -c $<

%.o: %.c %.h nvme.h linux/nvme.h linux/nvme_ioctl.h nvme-ioctl.h nvme-print.h util/argconfig.h
	$(QUIET_CC)$(CC) $(CPPFLAGS) $(CFLAGS) $(INC) -o $@ -c $<

%.o: %.c nvme.h linux/nvme.h linux/nvme_ioctl.h nvme-ioctl.h nvme-print.h util/argconfig.h
	$(QUIET_CC)$(CC) $(CPPFLAGS) $(CFLAGS) $(INC) -o $@ -c $<

doc: $(NVME)
	$(MAKE) -C Documentation

test:
	$(MAKE) -C tests/ run

all: doc

clean:
	$(RM) $(NVME) $(OBJS) $(PLUGIN_OBJS) $(UTIL_OBJS) *~ a.out NVME-VERSION-FILE *.tar* nvme.spec version control nvme-*.deb 70-nvmf-autoconnect.conf
	$(MAKE) -C Documentation clean
	$(RM) tests/*.pyc
	$(RM) verify-no-dep

clobber: clean
	$(MAKE) -C Documentation clobber

install-man:
	$(MAKE) -C Documentation install-no-build

install-bin: default
	$(RM) $(DESTDIROLD)/$(NVME)
	$(INSTALL) -d $(DESTDIR)$(SBINDIR)
	$(INSTALL) -m 755 $(NVME) $(DESTDIR)$(SBINDIR)

install-bash-completion:
	$(INSTALL) -d $(DESTDIR)$(PREFIX)/share/bash-completion/completions
	$(INSTALL) -m 644 -T ./completions/bash-nvme-completion.sh $(DESTDIR)$(PREFIX)/share/bash-completion/completions/$(NVME)

install-systemd:
	$(INSTALL) -d $(DESTDIR)$(SYSTEMDDIR)/system
	$(INSTALL) -m 644 ./nvmf-autoconnect/systemd/* $(DESTDIR)$(SYSTEMDDIR)/system

install-udev:
	$(INSTALL) -d $(DESTDIR)$(UDEVRULESDIR)
	$(INSTALL) -m 644 ./nvmf-autoconnect/udev-rules/* $(DESTDIR)$(UDEVRULESDIR)

install-dracut: 70-nvmf-autoconnect.conf
	$(INSTALL) -d $(DESTDIR)$(DRACUTDIR)/dracut.conf.d
	$(INSTALL) -m 644 $< $(DESTDIR)$(DRACUTDIR)/dracut.conf.d

install-zsh-completion:
	$(INSTALL) -d $(DESTDIR)$(PREFIX)/share/zsh/site-functions
	$(INSTALL) -m 644 -T ./completions/_nvme $(DESTDIR)$(PREFIX)/share/zsh/site-functions/_$(NVME)

install-hostparams: install-etc
	if [[ $(DESTDIR)$(SYSCONFIGDIR) != *BUILDROOT* ]]; then \
		if [[ ! -s $(DESTDIR)$(SYSCONFDIR)/$(NVME)/hostnqn ]]; then \
			echo `$(DESTDIR)$(SBINDIR)/$(NVME) gen-hostnqn` > $(DESTDIR)$(SYSCONFDIR)/$(NVME)/hostnqn; \
		fi; \
		if [[ ! -s $(DESTDIR)$(SYSCONFDIR)/$(NVME)/hostid ]]; then \
			uuidgen > $(DESTDIR)$(SYSCONFDIR)/$(NVME)/hostid; \
		fi \
	fi

install-etc:
	$(INSTALL) -d $(DESTDIR)$(SYSCONFDIR)/$(NVME)
	touch $(DESTDIR)$(SYSCONFDIR)/$(NVME)/hostnqn
	touch $(DESTDIR)$(SYSCONFDIR)/$(NVME)/hostid
	if [ ! -f $(DESTDIR)$(SYSCONFDIR)/$(NVME)/discovery.conf ]; then \
		$(INSTALL) -m 644 -T ./etc/discovery.conf.in $(DESTDIR)$(SYSCONFDIR)/$(NVME)/discovery.conf; \
	fi

install-spec: install-bin install-man install-bash-completion install-zsh-completion install-etc install-systemd install-udev install-dracut
install: install-spec install-hostparams

$(NVME).spec: nvme.spec.in NVME-VERSION-FILE
	sed -e 's/@@VERSION@@/$(NVME_VERSION)/g' < $< | sed -e 's/@@RELEASE@@/$(SPEC_RELEASE)/g' > $@+
	mv $@+ $@

70-nvmf-autoconnect.conf: nvmf-autoconnect/dracut-conf/70-nvmf-autoconnect.conf.in
	sed -e 's#@@UDEVRULESDIR@@#$(UDEVRULESDIR)#g' < $< > $@+
	mv $@+ $@

PKG=$(NVME)-$(NVME_VERSION)-$(SPEC_RELEASE)
dist: $(NVME).spec
	git archive --format=tar --prefix=$(PKG)/ HEAD > $(PKG).tar
	@echo $(NVME_VERSION) > version
	$(TAR) -rf  $(PKG).tar --xform="s%^%$(PKG)/%" $(NVME).spec version
	gzip -f -9 $(PKG).tar

control: nvme.control.in NVME-VERSION-FILE
	sed -e 's/@@VERSION@@/$(NVME_VERSION)/g' < $< > $@+
	mv $@+ $@
	sed -e 's/@@DEPENDS@@/$(LIB_DEPENDS)/g' < $@ > $@+
	mv $@+ $@

pkg: control nvme.control.in
	mkdir -p $(PKG)$(SBINDIR)
	mkdir -p $(PKG)$(PREFIX)/share/man/man1
	mkdir -p $(PKG)/DEBIAN/
	cp Documentation/*.1 $(PKG)$(PREFIX)/share/man/man1
	cp $(NVME) $(PKG)$(SBINDIR)
	cp control $(PKG)/DEBIAN/

# Make a reproducible tar.gz in the super-directory. Uses
# git-restore-mtime if available to adjust timestamps.
../nvme-cli_$(NVME_VERSION).orig.tar.gz:
	find . -type f -perm -u+rwx -exec chmod 0755 '{}' +
	find . -type f -perm -u+rw '!' -perm -u+x -exec chmod 0644 '{}' +
	if which git-restore-mtime >/dev/null; then git-restore-mtime; fi
	git ls-files | tar cf ../nvme-cli_$(NVME_VERSION).orig.tar \
	  --owner=root --group=root \
	  --transform='s#^#nvme-cli-$(NVME_VERSION)/#' --files-from -
	touch -d "`git log --format=%ci -1`" ../nvme-cli_$(NVME_VERSION).orig.tar
	gzip -f -9 ../nvme-cli_$(NVME_VERSION).orig.tar

dist-orig: ../nvme-cli_$(NVME_VERSION).orig.tar.gz

# Create a throw-away changelog, which dpkg-buildpackage uses to
# determine the package version.
deb-changelog:
	printf '%s\n\n  * Auto-release.\n\n %s\n' \
          "nvme-cli ($(NVME_VERSION)-$(NVME_DPKG_VERSION)) `lsb_release -sc`; urgency=low" \
          "-- $(AUTHOR)  `git log -1 --format=%cD`" \
	  > debian/changelog

deb: deb-changelog dist-orig
	dpkg-buildpackage -uc -us -sa

# After this target is build you need to do a debsign and dput on the
# ../<name>.changes file to upload onto the relevant PPA. For example:
#
#  > make AUTHOR='First Last <first.last@company.com>' \
#        NVME_DPKG_VERSION='0ubuntu1' deb-ppa
#  > debsign <name>.changes
#  > dput ppa:<lid>/ppa <name>.changes
#
# where lid is your launchpad.net ID.
deb-ppa: deb-changelog dist-orig
	debuild -uc -us -S

deb-light: $(NVME) pkg nvme.control.in
	dpkg-deb --build $(PKG)

rpm: dist
	$(RPMBUILD) --define '_libdir ${LIBDIR}' -ta $(PKG).tar.gz

.PHONY: default doc all clean clobber install-man install-bin install
.PHONY: dist pkg dist-orig deb deb-light rpm test
