NAME = libmodbus
VERSION = 3.1.4-1

all : deb deb-dev

deb :
	fpm -s dir -t deb \
	-n $(NAME) \
	-v $(VERSION) \
	-m 'SolarNetwork Packaging <packaging@solarnetwork.org.nz>' \
	--vendor 'SolarNetwork Foundation' \
	--description 'Shared library for Modbus communication.' \
	--url 'https://github.com/stephane/libmodbus' \
	--license 'Lesser General Public License 2.1' \
	--force \
	-C libmodbus/local \
	--deb-activate noawait \
	usr/lib usr/share

deb-dev :	
	fpm -s dir -t deb \
	-n $(NAME)-dev \
	-v $(VERSION) \
	-m 'SolarNetwork Packaging <packaging@solarnetwork.org.nz>' \
	--vendor 'SolarNetwork Foundation' \
	--description 'Shared library for Modbus communication development headers.' \
	--url 'https://github.com/stephane/libmodbus' \
	--license 'Lesser General Public License 2.1' \
	--force \
	-C libmodbus/local \
	usr/include

clean : 
	rm -f $(NAME)_$(VERSION)*.deb
