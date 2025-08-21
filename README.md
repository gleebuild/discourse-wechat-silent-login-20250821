# Discourse WeChat Silent Login (p7)

- Uses `omniauth-wechat-oauth2` for the callback/user creation pipeline.
- Bypasses OmniAuth interstitial by **directly redirecting to WeChat authorize URL**
  with callback `/auth/wechat/callback` and scope from setting (default `snsapi_base`).
- Username/email rule matches WordPress plugin.

If you still see "Scope 参数错误或没有 Scope 权限", confirm:
1) Account is a **Service Account**, not Subscription.
2) OAuth domain matches the forum domain (no scheme/path).
3) Scope set to `snsapi_base` (silent) or `snsapi_userinfo` (will prompt).
