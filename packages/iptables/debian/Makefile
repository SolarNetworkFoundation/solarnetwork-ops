VERSION = 1.0.0-1
NAME = sn-iptables

deb : 
	fpm -s dir -t deb \
	-n $(NAME) \
	-v $(VERSION) \
	-m 'packaging@solarnetwork.org.nz' \
	--vendor 'SolarNetwork Foundation' \
	-a all \
	--description 'iptables firewall management service' \
	--license 'Apache License 2.0' \
	-f \
	-d 'cron (>= 3.0)' \
	-d 'iptables (>= 1.6.0)' \
	-d 'systemd (>= 232)' \
	--after-install $(NAME).postinst \
	--after-remove $(NAME).postrm \
	etc lib usr

clean : 
	rm $(NAME)_$(VERSION)_all.deb
