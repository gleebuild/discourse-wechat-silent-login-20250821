# Discourse WeChat Silent Login (v1.1.0, p9)

- **Silent only**: always requests `snsapi_base`.
- **No interstitial**: direct redirect to WeChat authorize URL; callback handled by `omniauth-wechat-oauth2` at `/auth/wechat/callback`.
- **Callback host override**: set `wechat_callback_host` (e.g. `m.lebanx.com`) if your WeChat "网页授权域名" is different; reverse-proxy that path back to Discourse.
- **Username/Email** aligned with your WordPress plugin:
  - `username = "wx_" + md5(openid)[0,8]`
  - `email = "<username>@lebanx.com"`

Install: place this folder under `/var/discourse/plugins/`, then `./launcher rebuild app`.
