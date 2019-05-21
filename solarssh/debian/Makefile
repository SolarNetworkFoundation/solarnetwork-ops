NAME = sn-solarssh
VERSION = 1.0.0-1

deb : 
	fpm -s dir -t deb \
	-n $(NAME) \
	-v $(VERSION) \
	-a all \
	-m 'packaging@solarnetwork.org.nz' \
	--vendor 'SolarNetwork Foundation' \
	--description 'SolarSSH support' \
	--license 'Apache License 2.0' \
	-f \
	-d 'systemd (>= 232)' \
	--after-install $(NAME).postinst \
	--after-remove $(NAME).postrm \
	--deb-no-default-config-files \
	etc lib usr

clean : 
	rm $(NAME)_$(VERSION)_all.deb
