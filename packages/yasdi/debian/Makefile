NAME = yasdi
DIST = 
VERSION = 1.8.1-Build9$(if $(DIST),+$(DIST),)

all : deb deb-lib deb-dev

deb :
	fpm -s dir -t deb \
	-n $(NAME)shell \
	-v $(VERSION) \
	-m 'SolarNetwork Packaging <packaging@solarnetwork.org.nz>' \
	--vendor 'SolarNetwork Foundation' \
	--description 'Interactive shell for SMA inverters using libyasdi.' \
	--url 'https://www.sma.de/en/products/monitoring-control/yasdi.html' \
	--license 'General Public License 2.1' \
	--force \
	-C yasdi/projects/generic-cmake/build/native/local \
	-d 'libyasdi (>= 1.8.1)' \
	usr/bin

deb-lib :	
	fpm -s dir -t deb \
	-n lib$(NAME) \
	-v $(VERSION) \
	-m 'SolarNetwork Packaging <packaging@solarnetwork.org.nz>' \
	--vendor 'SolarNetwork Foundation' \
	--description 'Shared libraries for SMA yasdi.' \
	--url 'https://www.sma.de/en/products/monitoring-control/yasdi.html' \
	--license 'General Public License 2.1' \
	--force \
	-C yasdi/projects/generic-cmake/build/native/local \
	--deb-activate noawait \
	usr/lib

deb-dev : 
	fpm -s dir -t deb \
	-n lib$(NAME)-dev \
	-v $(VERSION) \
	-m 'SolarNetwork Packaging <packaging@solarnetwork.org.nz>' \
	--vendor 'SolarNetwork Foundation' \
	--description 'Shared libraries for SMA yasdi development headers.' \
	--license 'Lesser General Public License 2.1' \
	--force \
	-C yasdi/projects/generic-cmake/build/native/local \
	usr/include

clean : 
	rm -f lib$(NAME)_$(VERSION)*.deb
	rm -f lib$(NAME)_$(VERSION)-dev*.deb
	rm -f $(NAME)shell_$(VERSION)*.deb
