import Controller from "@ember/controller";
import { action } from "@ember/object";
import { ajax } from "discourse/lib/ajax";

export default class AdminPluginsWeChatLogsController extends Controller {
  @action
  async refresh() {
    this.set("model", await ajax(`/wechat/admin/logs.json?limit=200&_=${Date.now()}`));
  }

  @action
  async clear() {
    await ajax("/wechat/admin/logs.json", { type: "DELETE" });
    await this.refresh();
  }
}
