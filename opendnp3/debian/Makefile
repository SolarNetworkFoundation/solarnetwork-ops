NAME = opendnp3
VERSION = 2.2.0-1
DNP3_INSTALL_DIR = dnp3/build/native/local

all : deb deb-dev

deb :
	fpm -s dir -t deb \
	-n $(NAME) \
	-v $(VERSION) \
	-m 'SolarNetwork Packaging <packaging@solarnetwork.org.nz>' \
	--vendor 'SolarNetwork Foundation' \
	--description 'Shared library for Modbus communication.' \
	--license 'Apache License 2.0' \
	--url 'https://github.com/automatak/dnp3' \
	-C $(DNP3_INSTALL_DIR) \
	--force \
	-d 'libssl1.0.2' \
	--deb-activate noawait \
	--after-install opendnp3.postinst \
	--before-remove opendnp3.prerm \
	--after-remove opendnp3.postrm \
	--deb-config opendnp3.config \
	--deb-templates opendnp3.templates \
	usr/lib

deb-dev :	
	fpm -s dir -t deb \
	-n $(NAME)-dev \
	-v $(VERSION) \
	-m 'SolarNetwork Packaging <packaging@solarnetwork.org.nz>' \
	--vendor 'SolarNetwork Foundation' \
	--description 'Development headers for OpenDNP3' \
	--license 'Apache License 2.0' \
	--url 'https://github.com/automatak/dnp3' \
	-C $(DNP3_INSTALL_DIR) \
	--force \
	-d 'libssl1.0-dev' \
	usr/include

clean : 
	rm -f $(NAME)_$(VERSION)*.deb
