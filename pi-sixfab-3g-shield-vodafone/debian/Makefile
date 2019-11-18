DIST = 
VERSION = 1.0.0-1$(if $(DIST),+$(DIST),)
NAME = sn-pi-sixfab-3g-shield-vodafone
PATHS = etc lib usr

deb : prep
	fpm -s dir -t deb \
	-n $(NAME) \
	-v $(VERSION) \
	--description 'Raspberry Pi Sixfab 3G Shield with Quectel modem/GPS support - Vodafone' \
	--license 'Apache License 2.0' \
	-m 'packaging@solarnetwork.org.nz' \
	--vendor 'SolarNetwork Foundation' \
	-a all \
	--force \
	-d 'systemd (>= 232)' \
	-d 'ppp (>= 2.4.7)' \
	--after-install $(NAME).postinst \
	--provides 'solarnode-gps' \
	--provides 'solarnode-modem' \
	--deb-no-default-config-files \
	$(PATHS)

prep : 
	find $(PATHS) -type f -name .DS_Store -delete

clean : 
	rm $(NAME)_$(VERSION)_all.deb
