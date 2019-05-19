NAME = sn-system
VERSION = 1.0.0-1

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
	etc

clean : 
	rm $(NAME)_$(VERSION)_all.deb
