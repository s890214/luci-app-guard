-- SPDX-License-Identifier: MIT
-- luci-app-guard 数据接口：走 LuCI 登录态，不再暴露独立 /cgi-bin/guard

module("luci.controller.guard", package.seeall)

function index()
	local api = entry({ "admin", "services", "guard", "api" }, call("data"))
	api.leaf = true
	api.sysauth = "root"
	-- 只接受已有 LuCI 会话，不在这里解析登录表单；未登录直接 403
	api.sysauth_authenticator = false
end

local function shquote(s)
	return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

function data()
	local qs = luci.http.getenv("QUERY_STRING") or ""
	local out = luci.sys.exec("QUERY_STRING=" .. shquote(qs) ..
		" /usr/lib/guard/guard-cgi 2>/dev/null") or ""

	luci.http.header("Cache-Control", "no-store")
	luci.http.prepare_content("application/json")
	luci.http.write(out)
end
