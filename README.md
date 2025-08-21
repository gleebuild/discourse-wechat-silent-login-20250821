# Discourse WeChat Silent Login (20250821-p5)

- Removes Ember admin page to avoid client API differences across Discourse versions.
- Adds **server-rendered admin page** at `/wechat/admin/logs` (with refresh/clear).
- JSON endpoint unchanged: `/wechat/admin/logs.json`.

How to open logs: visit `/wechat/admin/logs` as an admin.
