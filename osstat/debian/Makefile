NAME = sn-osstat
VERSION = 1.0.0-1

deb : 
	fpm -s dir -t deb \
	-n $(NAME) \
	-v $(VERSION) \
	-a all \
	-m 'packaging@solarnetwork.org.nz' \
	--vendor 'SolarNetwork Foundation' \
	--description 'SolarNode OS statistics support' \
	--license 'Apache License 2.0' \
	-f \
	-d 'procps (>= 2:3.3.12)' \
	usr

clean : 
	rm $(NAME)_$(VERSION)_all.deb
