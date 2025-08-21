# discourse-wechat-silent-login-20250821

Silent auto-login for visitors using WeChat in-app browser. Uses `snsapi_base` to fetch `openid`, creates a Discourse user if missing, and logs them in without prompts. **Only active in WeChat UA by default.**

## Install

1. SSH to the host and place this folder under `/var/discourse/plugins/` (or clone/unzip there).
2. Set site settings in **Admin → Settings → Plugins**:
   - `wechat_silent_login_enabled` = **enabled**
   - `wechat_app_id` / `wechat_app_secret` = your WeChat MP credentials
3. Rebuild: `cd /var/discourse && ./launcher rebuild app`

## How it works

- On HTML GET requests inside WeChat UA (`MicroMessenger`), if user is not logged in, the plugin redirects to `/wx/silent` which sends the user to WeChat OAuth (scope `snsapi_base`).  
- WeChat redirects back to `/wx/callback?code=...`, the plugin exchanges code → `openid`, then:
  - If `openid` exists in table `lebanx_wechat_openid`, it logs in the mapped user.
  - If not, it creates username `wx_<md5(openid)[0,8]>`, email `<username>@lebanx.com`, random password, stores the mapping, and logs in.
- All actions are silent; if already logged in, nothing happens.

## Table

- Name: `lebanx_wechat_openid`
- Columns: `openid` (unique), `user_id`, `username`, timestamps.

## Notes

- Make sure your WeChat OAuth callback domain exactly matches Discourse base URL and is whitelisted in WeChat MP settings.
- To limit scope to WeChat only, keep `wechat_only_wechat_ua` enabled (default).