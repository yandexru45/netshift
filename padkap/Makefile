include $(TOPDIR)/rules.mk

PKG_NAME:=padkap

PKG_VERSION := $(if $(PADKAP_VERSION),$(PADKAP_VERSION),0.$(shell date +%d%m%Y))

PKG_RELEASE:=1

PKG_MAINTAINER:=spgsroot <67481268+spgsroot@users.noreply.github.com>
PKG_LICENSE:=GPL-2.0-or-later

include $(INCLUDE_DIR)/package.mk

define Package/padkap
	SECTION:=net
	CATEGORY:=Network
	DEPENDS:=+sing-box +curl +jq +kmod-nft-tproxy +coreutils-base64 +bind-dig
	CONFLICTS:=https-dns-proxy nextdns luci-app-passwall luci-app-passwall2
	TITLE:=Domain routing app
	URL:=https://github.com/spgsroot/padkap-evolution
	PKGARCH:=all
endef

define Package/padkap/description
	Domain routing. Use of VLESS, Shadowsocks technologies
endef

define Build/Configure
endef

define Build/Compile
endef

define Package/padkap/prerm
#!/bin/sh

grep -q "105 padkap" /etc/iproute2/rt_tables && sed -i "/105 padkap/d" /etc/iproute2/rt_tables

/etc/init.d/padkap stop

exit 0
endef

define Package/padkap/conffiles
/etc/config/padkap
endef

define Package/padkap/install
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./files/etc/init.d/padkap $(1)/etc/init.d/padkap

	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) ./files/etc/config/padkap $(1)/etc/config/padkap

	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) ./files/usr/bin/padkap $(1)/usr/bin/padkap

	$(INSTALL_DIR) $(1)/usr/lib/padkap
	$(CP) ./files/usr/lib/* $(1)/usr/lib/padkap/

	sed -i -e 's/__COMPILED_VERSION_VARIABLE__/$(PKG_VERSION)/g' $(1)/usr/lib/padkap/constants.sh
endef

$(eval $(call BuildPackage,padkap))
