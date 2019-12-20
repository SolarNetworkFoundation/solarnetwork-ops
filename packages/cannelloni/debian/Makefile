NAME = cannelloni
DIST = 
VERSION = 0.7.0+dev-1$(if $(DIST),+$(DIST),)
CANNELLONI_INSTALL_DIR = cannelloni/build/native/local
PATHS = usr

deb :
	fpm -s dir -t deb \
	-n $(NAME) \
	-v $(VERSION) \
	-m 'SolarNetwork Packaging <packaging@solarnetwork.org.nz>' \
	--vendor 'SolarNetwork Foundation' \
	--description 'SocketCAN over Ethernet tunnel.' \
	--url https://github.com/mguentner/cannelloni \
	--license 'General Public License 2.0' \
	-C $(CANNELLONI_INSTALL_DIR) \
	--force \
	$(PATHS)

clean : 
	rm $(NAME)_$(VERSION)_all.deb
