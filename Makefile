include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-guard
PKG_VERSION:=2.1.0
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
  Lightweight exposed-service monitor for OpenWrt. Samples conntrack and
  records only inbound connections to exposed services (lucky/dstnat/firewall
  rules) and UPnP mappings. P2P/fullcone callbacks and rejected probes are
  deliberately dropped. Keeps 24h detail in RAM with an hourly flash snapshot,
  and 30 days of daily aggregates. Data API is a LuCI controller behind the
  LuCI login. Read-only: never blocks traffic.
endef

define Build/Compile
endef

define Package/luci-app-guard/install
	$(INSTALL_DIR) $(1)/etc/config $(1)/etc/init.d $(1)/etc/guard/daily $(1)/etc/guard/detail
	$(INSTALL_DIR) $(1)/usr/lib/guard
	$(INSTALL_DIR) $(1)/usr/lib/lua/luci/controller
	$(INSTALL_DIR) $(1)/www/luci-static/resources/view/guard
	$(INSTALL_DIR) $(1)/usr/share/luci/menu.d
	$(INSTALL_CONF) ./root/etc/config/guard $(1)/etc/config/guard
	$(INSTALL_BIN) ./root/etc/init.d/guard $(1)/etc/init.d/guard
	$(INSTALL_BIN) ./root/etc/guard/guard.sh $(1)/etc/guard/guard.sh
	$(INSTALL_DATA) ./root/usr/lib/guard/class.awk $(1)/usr/lib/guard/class.awk
	$(INSTALL_BIN) ./root/usr/lib/guard/guard-cgi $(1)/usr/lib/guard/guard-cgi
	$(INSTALL_DATA) ./root/usr/lib/lua/luci/controller/guard.lua $(1)/usr/lib/lua/luci/controller/guard.lua
	$(INSTALL_DATA) ./root/www/luci-static/resources/view/guard/overview.js $(1)/www/luci-static/resources/view/guard/overview.js
	$(INSTALL_DATA) ./root/usr/share/luci/menu.d/luci-app-guard.json $(1)/usr/share/luci/menu.d/luci-app-guard.json
endef

define Package/luci-app-guard/postinst
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] || {
	rm -f /www/cgi-bin/guard
	rm -rf /www/guard
	/etc/init.d/guard enable
	/etc/init.d/guard restart
}
endef

$(eval $(call BuildPackage,luci-app-guard))
