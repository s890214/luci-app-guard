include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-guard
PKG_VERSION:=1.0.0
PKG_RELEASE:=1
PKG_LICENSE:=MIT
PKG_MAINTAINER:=s890214

include $(INCLUDE_DIR)/package.mk

define Package/luci-app-guard
  SECTION:=luci
  CATEGORY:=LuCI
  SUBMENU:=3. Applications
  TITLE:=External access monitor (conntrack based)
  DEPENDS:=+luci-base
  PKGARCH:=all
endef

define Package/luci-app-guard/description
  Lightweight inbound-connection monitor for OpenWrt. Samples conntrack,
  records external sources, writes scan/rate alerts, keeps 30 days of daily
  aggregates. Read-only: never blocks traffic.
endef

define Build/Compile
endef

define Package/luci-app-guard/install
	$(INSTALL_DIR) $(1)/etc/config $(1)/etc/init.d $(1)/etc/guard/daily
	$(INSTALL_DIR) $(1)/www/guard $(1)/www/cgi-bin
	$(INSTALL_DIR) $(1)/www/luci-static/resources/view/guard
	$(INSTALL_DIR) $(1)/usr/share/luci/menu.d
	$(INSTALL_CONF) ./root/etc/config/guard $(1)/etc/config/guard
	$(INSTALL_BIN) ./root/etc/init.d/guard $(1)/etc/init.d/guard
	$(INSTALL_BIN) ./root/etc/guard/guard.sh $(1)/etc/guard/guard.sh
	$(INSTALL_BIN) ./root/www/cgi-bin/guard $(1)/www/cgi-bin/guard
	$(INSTALL_DATA) ./root/www/guard/index.html $(1)/www/guard/index.html
	$(INSTALL_DATA) ./root/www/luci-static/resources/view/guard/overview.js $(1)/www/luci-static/resources/view/guard/overview.js
	$(INSTALL_DATA) ./root/usr/share/luci/menu.d/luci-app-guard.json $(1)/usr/share/luci/menu.d/luci-app-guard.json
endef

define Package/luci-app-guard/postinst
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] || {
	/etc/init.d/guard enable
	/etc/init.d/guard restart
}
endef

$(eval $(call BuildPackage,luci-app-guard))
