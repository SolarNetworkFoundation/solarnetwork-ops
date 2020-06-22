DIST = 
VERSION = 1.1.0-0$(if $(DIST),+$(DIST),)
PATHS = etc lib usr

deb : prep
	fpm -s dir -t deb \
	-n sn-wifi \
	-v $(VERSION) \
	-a all \
	-m 'packaging@solarnetwork.org.nz' \
	--vendor 'SolarNetwork Foundation' \
	--description 'WiFi management service' \
	--license 'Apache License 2.0' \
	-f \
	-d 'wpasupplicant' \
	-d 'systemd (>= 215)' \
	-d 'sn-system (>= 1.2.0)' \
	--after-install sn-wifi.postinst \
	--after-remove sn-wifi.postrm \
	--deb-config sn-wifi.config \
	--deb-templates sn-wifi.templates \
	--deb-no-default-config-files \
	$(PATHS)

# Note the --deb-systemd switch causes the postinst script to be broken
# https://github.com/jordansissel/fpm/issues/1272

prep : 
	find $(PATHS) -type f -name .DS_Store -delete

clean : 
	rm sn-wifi_$(VERSION)_all.deb
