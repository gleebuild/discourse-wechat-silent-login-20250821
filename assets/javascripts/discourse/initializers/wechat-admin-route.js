import { withPluginApi } from "discourse/lib/plugin-api";

export default {
  name: "wechat-admin-route",
  initialize() {
    withPluginApi("1.14.0", (api) => {
      api.addAdminRoute("WeChat 登录日志", "plugins/wechat-logs");
    });
  },
};
