NAME = sn-solarpkg
VERSION = 1.0.0-1

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
	--deb-no-default-config-files \
	etc usr var

clean : 
	rm $(NAME)_$(VERSION)_all.deb
