# Discourse WeChat Silent Login (20250821-p3)

- Adds **Admin → Plugins → WeChat 登录日志** page.
- Server keeps a Redis ring buffer (`wechat_login:events`) with last N events (default 400).
- Buttons to refresh / clear logs.

Endpoints:
- `GET /wechat/admin/logs.json?limit=200`
- `DELETE /wechat/admin/logs.json`
