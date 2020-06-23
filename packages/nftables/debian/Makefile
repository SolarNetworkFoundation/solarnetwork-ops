DIST = buster
VERSION = 1.1.0-1$(if $(DIST),+$(DIST),)
NAME = sn-nftables
PATHS = etc usr var

deb : prep
	fpm -s dir -t deb \
	-n $(NAME) \
	-v $(VERSION) \
	--description 'nftables firewall management service' \
	--license 'Apache License 2.0' \
	-m 'packaging@solarnetwork.org.nz' \
	--vendor 'SolarNetwork Foundation' \
	-a all \
	--force \
	-d 'cron (>= 3.0)' \
	-d 'nftables (>= 0.9.0)' \
	-d 'sudo (>= 1.8.10)' \
	-d 'systemd (>= 232)' \
	-d 'busybox-syslogd (>= 1:1.30.1)' \
	--conflicts 'sn-iptables' \
	--replaces 'sn-iptables' \
	--provides 'solarnode-firewall' \
	--after-install $(NAME).postinst \
	--before-remove $(NAME).prerm \
	--after-remove $(NAME).postrm \
	--deb-no-default-config-files \
	$(PATHS)

prep : 
	find $(PATHS) -type f -name .DS_Store -delete

clean : 
	rm $(NAME)_$(VERSION)_all.deb
