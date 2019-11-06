NAME = sn-system
DIST = 
VERSION = 1.1.0-1$(if $(DIST),+$(DIST),)

deb : 
	fpm -s dir -t deb \
	-n $(NAME) \
	-v $(VERSION) \
	-a all \
	-m 'packaging@solarnetwork.org.nz' \
	--vendor 'SolarNetwork Foundation' \
	--description 'SolarNode system support' \
	--license 'Apache License 2.0' \
	-f \
	-d 'bash (>= 4.4)' \
	-d 'systemd (>= 230)' \
	--conflicts 'ifupdown' \
	--replaces 'ifupdown' \
	--after-install $(NAME).postinst \
	--deb-no-default-config-files \
	etc lib usr

clean : 
	rm $(NAME)_$(VERSION)_all.deb
