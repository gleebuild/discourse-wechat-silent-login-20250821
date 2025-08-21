# Discourse WeChat Silent Login (p6, minimal)

This version uses the **official OmniAuth WeChat strategy** and Discourse's **ManagedAuthenticator**,
following the core docs on adding a new auth provider. No custom controllers, no logs, no Ember.

## Requirements
- WeChat **Service Account** (not subscription) with Web OAuth enabled
- OAuth domain must match your forum domain (no scheme/path)

## Install
1. Copy this folder into `/var/discourse/plugins/discourse-wechat-silent-login-20250821`.
2. `cd /var/discourse && ./launcher rebuild app`

## Configure (Admin → Settings → Plugins)
- `wechat_login_enabled = true`
- `wechat_appid`, `wechat_appsecret`
- `wechat_scope = snsapi_base` for silent login
- optional `wechat_only_wechat_ua = true`

## Use
- WeChat in-app browser will auto-redirect to `/auth/wechat` once for silent login.
- Desktop/mobile browsers: users can click "Log in with WeChat" button.

## Username/Email rule (kept same as WP plugin)
- username: `wx_` + `md5(openid)` first 8 chars
- email: `<username>@lebanx.com`

