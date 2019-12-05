NAME = sn-solarpkg
DIST = 
VERSION = 1.0.3-1$(if $(DIST),+$(DIST),)

deb : 
	fpm -s dir -t deb \
	-n $(NAME) \
	-v $(VERSION) \
	-a all \
	-m 'packaging@solarnetwork.org.nz' \
	--vendor 'SolarNetwork Foundation' \
	--description 'SolarNode package management support' \
	--license 'Apache License 2.0' \
	-f \
	-d 'apt (>= 1.4.9)' \
	-d 'dpkg (>= 1.18.25)' \
	-d 'psmisc (>= 22.21)' \
	-d 'sudo (>= 1.8.19)' \
	--deb-no-default-config-files \
	etc usr var

clean : 
	rm $(NAME)_$(VERSION)_all.deb
