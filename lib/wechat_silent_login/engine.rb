# frozen_string_literal: true
module WeChatSilentLogin
  class Engine < ::Rails::Engine
    engine_name WeChatSilentLogin::PLUGIN_NAME
    isolate_namespace WeChatSilentLogin
  end
end

WeChatSilentLogin::Engine.routes.draw do
  get "/start" => "login#start"
  get "/callback" => "login#callback"
end

Discourse::Application.routes.append do
  mount ::WeChatSilentLogin::Engine, at: "/wechat"
end
