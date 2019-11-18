NAME = sn-socketcand
DIST = 
VERSION = 0.6.2dev-1$(if $(DIST),+$(DIST),)
SOCKETCAND_INSTALL_DIR = socketcand/local
PATHS = etc usr

deb :
	fpm -s dir -t deb \
	-n $(NAME) \
	-v $(VERSION) \
	-m 'SolarNetwork Packaging <packaging@solarnetwork.org.nz>' \
	--vendor 'SolarNetwork Foundation' \
	--description 'socketcand server.' \
	--url https://github.com/linux-can/socketcand \
	--license 'Apache License 2.0' \
	-C $(SOCKETCAND_INSTALL_DIR) \
	--force \
	$(PATHS)

clean : 
	rm $(NAME)_$(VERSION)_all.deb
