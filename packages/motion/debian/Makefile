NAME = sn-motion
DIST = 
VERSION = 1.0.0-1$(if $(DIST),+$(DIST),)

all : deb deb-dev

deb : 
	fpm -s dir -t deb \
	-n $(NAME) \
	-v $(VERSION) \
	-m 'SolarNetwork Packaging <packaging@solarnetwork.org.nz>' \
	--vendor 'SolarNetwork Foundation' \
	--description 'SolarNode motion support.' \
	--license 'Apache License 2.0' \
	--force \
	-d 'sn-system (>= 1.1)' \
	-d 'motion (>= 4.0)' \
	-d 'systemd (>= 230)' \
	--deb-activate noawait \
	--after-install motion.postinst \
	etc lib

clean : 
	rm $(NAME)_$(VERSION)_all.deb
