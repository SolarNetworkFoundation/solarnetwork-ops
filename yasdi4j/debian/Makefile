NAME = yasdi4j
DIST = 
VERSION = 0.2.1-1$(if $(DIST),+$(DIST),)
YASDI4J_DIR = yasdi4j
PKG_ROOT = $(YASDI4J_DIR)/dist

deb : prep pkg
	fpm -s dir -t deb \
	-n $(NAME) \
	-v $(VERSION) \
	-m 'SolarNetwork Packaging <packaging@solarnetwork.org.nz>' \
	--vendor 'SolarNetwork Foundation' \
	--description 'Java integration with libyasdi for communicating with SMA inverters.' \
	--url 'https://github.com/SolarNetwork/yasdi4j' \
	--license 'General Public License 2.1' \
	--force \
	-C $(PKG_ROOT) \
	-d 'libyasdi (>= 1.8.1)' \
	usr

prep : 
	find $(YASDI4J_DIR) -type f -name .DS_Store -delete

pkg : $(PKG_ROOT)/usr/lib/jni/libyasdi4j.so $(PKG_ROOT)/usr/share/java/yasdi4j.jar

$(PKG_ROOT)/usr/lib/jni/libyasdi4j.so : 
	mkdir -p $(PKG_ROOT)/usr/lib/jni
	mv $(PKG_ROOT)/libyasdi4j.so $(PKG_ROOT)/usr/lib/jni/

$(PKG_ROOT)/usr/share/java/yasdi4j.jar : 
	mkdir -p $(PKG_ROOT)/usr/share/java
	mv $(PKG_ROOT)/yasdi4j.jar $(PKG_ROOT)/usr/share/java/

clean : 
	rm -rf $(PKG_ROOT)/usr
	rm -f lib$(NAME)_$(VERSION)*.deb
	rm -f $(NAME)shell_$(VERSION)*.deb
