NAME = mbpoll
VERSION = 1.4.11-1
MBPOLL_INSTALL_DIR = mbpoll/build/native/local

deb :
	fpm -s dir -t deb \
	-n $(NAME) \
	-v $(VERSION) \
	-m 'SolarNetwork Packaging <packaging@solarnetwork.org.nz>' \
	--vendor 'SolarNetwork Foundation' \
	--description 'Command line utility to communicate with ModBus devices.' \
	--url https://github.com/epsilonrt/mbpoll \
	--license 'General Public License 3.0' \
	-C $(MBPOLL_INSTALL_DIR) \
	--force \
	-d 'libmodbus (>= 3.1.0)' \
	usr

clean : 
	rm $(NAME)_$(VERSION)_all.deb
