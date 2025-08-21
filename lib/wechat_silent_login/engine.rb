# frozen_string_literal: true
module WechatSilentLogin
  class Engine < ::Rails::Engine
    engine_name WechatSilentLogin::PLUGIN_NAME
    isolate_namespace WechatSilentLogin
  end
end

WechatSilentLogin::Engine.routes.draw do
  get "/silent" => "wechat#silent", as: :silent_wechat
  get "/callback" => "wechat#callback", as: :callback_wechat
end

Discourse::Application.routes.append do
  mount ::WechatSilentLogin::Engine, at: "/wx"
end
