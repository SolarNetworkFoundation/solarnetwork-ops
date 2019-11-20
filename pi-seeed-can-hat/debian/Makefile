DIST = buster
VERSION = 1.0.0-1$(if $(DIST),+$(DIST),)
NAME = sn-pi-seeed-can-hat
PATHS = boot etc lib

deb : prep
	fpm -s dir -t deb \
	-n $(NAME) \
	-v $(VERSION) \
	--description 'Raspberry Pi Seeed Studio CAN HAT support' \
	--license 'Apache License 2.0' \
	-m 'packaging@solarnetwork.org.nz' \
	--vendor 'SolarNetwork Foundation' \
	-a armhf \
	--force \
	-d 'systemd (>= 232)' \
	-d 'raspberrypi-kernel (= 1.20190925+1-1)' \
	--before-install $(NAME).preinst \
	--after-install $(NAME).postinst \
	--before-remove $(NAME).prerm \
	--after-remove $(NAME).postrm \
	--deb-no-default-config-files \
	$(PATHS)

prep : 
	find $(PATHS) -type f -name .DS_Store -delete

clean : 
	rm $(NAME)_$(VERSION)_all.deb
