# Discourse WeChat Silent Login (20250821)

This plugin enables **silent login inside WeChat (MicroMessenger)** on Discourse, mirroring your WordPress `lebanx-wechat-login` plugin’s logic for **username/email**:

- **username**: `wx_` + first 8 chars of `md5(openid)`
- **email**: `<username>@lebanx.com`
- **password**:
  - default **`random`** (mirrors WordPress `wp_generate_password()`'s randomness – not equal across apps)
  - optional **`derive_from_openid`** to produce a deterministic value (set the same in both apps if you require exact cross-app equality)

## Routes
- `GET /wechat/start` — manual start
- `GET /wechat/callback` — OAuth callback (WeChat must whitelist your Discourse domain)

The plugin also **auto-triggers** on normal HTML page views in WeChat if user isn’t logged in, redirecting to WeChat authorization with `snsapi_base` by default.

## Settings (Admin → Settings → Plugins)
- `wechat_login_enabled` (default: true)
- `wechat_appid`, `wechat_appsecret`
- `wechat_scope` (`snsapi_base` | `snsapi_userinfo`)
- `wechat_only_wechat_ua` (default: true)
- `wechat_password_mode` (`random` | `derive_from_openid`)
- `wechat_password_salt` (used only when `derive_from_openid`)
- `wechat_log_enabled`

## Notes
- To guarantee the **same password** in WordPress and Discourse, switch both implementations to `derive_from_openid` (same salt).
- Existing users created by WordPress earlier will be matched by **username/email** then bound to the same `openid`.
