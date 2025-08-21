
# discourse-wechat-silent-login-20250821

在 **微信内置浏览器** 访问 Discourse 首页时，插件将静默完成登录：
- 如果已有 `lebanx_openid` Cookie：直接用它在本地创建/登录用户（不再请求微信）。
- 如无 Cookie：发起 `snsapi_base` 网页授权，回调带 `code` 后换取 `openid`，生成与 WordPress 插件一致的 **用户名/邮箱**：
  - 用户名：`wx_` + `md5(openid)` 前 8 位（冲突时随机补位）
  - 邮箱：`{username}@lebanx.com`
  - 密码：**随机**（与 WP 的 `wp_generate_password()` 行为一致）
- 每一步都会写日志到 **/var/www/discourse/public/wechat.txt**（已内置你提供的可用写法）。

> ⚠️ 说明：由于你现有的 WP 插件使用 `wp_generate_password()` 生成 **随机** 密码，Discourse 端无法“得知”那个随机值，因此**无法保证两端密码相同**。如果你确实需要“同密码”，需要同步改造 WP 插件为“可复现的口令算法”或通过服务端接口下发密码哈希。

## 安装

1. 登录服务器，把插件放到：`/var/discourse/plugins/discourse-wechat-silent-login-20250821`
2. 重建容器：`cd /var/discourse && ./launcher rebuild app`
3. 进入 Discourse 后台 → **设置**：
   - 启用：`wechat_silent_login_enabled`
   - 填写：`wechat_app_id`、`wechat_app_secret`
   - 可选：`wechat_cookie_domain`（例如 `.lebanx.com` 便于子域共享）
4. 在微信公众平台配置 **网页授权回调域名** 为你的站点域名（如 `lebanx.com`）。

## 行为说明

- 仅对 **首页类路径** 生效：`/`、`/latest`、`/categories`、`/top`、`/new`、`/hot`
- 仅在 **WeChat UA** 下触发（`MicroMessenger`）。
- 获取到 `openid` 后：
  - 先查 `UserCustomField(name=lebanx_wechat_openid, value=openid)` 找用户；
  - 找不到则新建用户（随机密码、active= true、approved= true）；
  - 登录并把 URL 里的 `code/state` 清理后重定向；
  - 设置 `lebanx_openid` Cookie（`SameSite=Lax`，按需设置 `domain`、`secure`）。
- 日志文件：`/var/www/discourse/public/wechat.txt`。

## 兼容 & 安全建议
- 若要完全“同用户名/同邮箱/同密码”，请调整 WP 插件密码逻辑为**可确定**（例如 `sha256(openid + 固定盐)`），或在 WP 提供一个安全接口，把**密码哈希**同步给 Discourse。
- 可以把 `wechat_scope` 改为 `snsapi_userinfo` 以便拿头像昵称（将出现授权页）。
- 如需扩大触发范围到非首页，扩展 `HOMEPATHS` 或改写 `home_like_path?`。

## 故障排查
- 看 `public/wechat.txt`：会打印“enter hook / state / exchange 结果 / login 成功与否 / clean redirect”等。
- 若出现反复跳转：检查公众平台回调域名、`appid/appsecret` 是否正确，以及服务器能否访问 `api.weixin.qq.com`。
- 如果两个子域共享 Cookie，配置 `wechat_cookie_domain = .lebanx.com`。
