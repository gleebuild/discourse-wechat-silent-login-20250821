import Route from "@ember/routing/route";
import { ajax } from "discourse/lib/ajax";

export default class AdminPluginsWeChatLogsRoute extends Route {
  model() {
    return ajax("/wechat/admin/logs.json?limit=200");
  }
}
