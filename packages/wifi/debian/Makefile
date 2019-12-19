DIST = 
VERSION = 1.0.0-3$(if $(DIST),+$(DIST),)

deb : 
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
	-d 'sn-system (>= 1.0.0)' \
	--after-install sn-wifi.postinst \
	--after-remove sn-wifi.postrm \
	--deb-config sn-wifi.config \
	--deb-templates sn-wifi.templates \
	--deb-no-default-config-files \
	etc lib usr

# Note the --deb-systemd switch causes the postinst script to be broken
# https://github.com/jordansissel/fpm/issues/1272

clean : 
	rm sn-wifi_$(VERSION)_all.deb
