# Discourse WeChat Silent Login (20250821-p1)

Changes vs v1.0.0:
- Guard: if `wechat_appid/appsecret` not configured, do **nothing** (prevents 500).
- Added `require 'cgi'` in controller.
- Kept username/email logic aligned with your WP plugin.
- Password mode: `random` (default) or `derive_from_openid` with salt.

See Admin → Settings → Plugins → WeChat for configuration.
