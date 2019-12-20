NAME = sn-solarpkg
DIST = 
VERSION = 1.0.3-2$(if $(DIST),+$(DIST),)

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
	-d 'apt (>= 1.0)' \
	-d 'dpkg (>= 1.17)' \
	-d 'psmisc (>= 22.21)' \
	-d 'sudo (>= 1.8.10)' \
	--deb-no-default-config-files \
	etc usr var

clean : 
	rm $(NAME)_$(VERSION)_all.deb
