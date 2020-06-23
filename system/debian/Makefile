NAME = sn-system
DIST = 
VERSION = 1.2.0-1$(if $(DIST),+$(DIST),)
PATHS = etc lib usr var

deb : prep
	fpm -s dir -t deb \
	-n $(NAME) \
	-v $(VERSION) \
	-a all \
	-m 'packaging@solarnetwork.org.nz' \
	--vendor 'SolarNetwork Foundation' \
	--description 'SolarNode system support' \
	--license 'Apache License 2.0' \
	-f \
	-d 'sudo (>= 1.8.10)' \
	-d 'systemd (>= 215)' \
	--conflicts 'ifupdown' \
	--replaces 'ifupdown' \
	--after-install $(NAME).postinst \
	--deb-no-default-config-files \
	$(PATHS)

prep : 
	find $(PATHS) -type f -name .DS_Store -delete

clean : 
	rm $(NAME)_$(VERSION)_all.deb
