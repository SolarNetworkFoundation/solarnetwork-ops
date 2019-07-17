DIST = buster
VERSION = 1.0.0-1$(if $(DIST),+$(DIST),)
NAME = sn-nftables
PATHS = etc lib usr

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
	-d 'systemd (>= 232)' \
	--conflicts 'sn-iptables' \
	--replaces 'sn-iptables' \
	--after-install $(NAME).postinst \
	--after-remove $(NAME).postrm \
	--deb-no-default-config-files \
	$(PATHS)

prep : 
	find $(PATHS) -type f -name .DS_Store -delete

clean : 
	rm $(NAME)_$(VERSION)_all.deb
