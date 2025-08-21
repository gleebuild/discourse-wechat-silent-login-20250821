# frozen_string_literal: true
# name: discourse-wechat-silent-login-20250821
# about: Silent auto-login in WeChat in-app browser using openid (snsapi_base)
# version: 1.0.0
# authors: GleeBuild + ChatGPT
# url: https://lebanx.com
# required_version: 3.0.0

enabled_site_setting :wechat_silent_login_enabled

after_initialize do
  module ::WechatSilentLogin
    PLUGIN_NAME ||= "discourse-wechat-silent-login-20250821"
  end

  require_relative "lib/wechat_silent_login/engine"

  # Add a global before_action that only runs for WeChat UA and HTML GET requests.
  add_to_class(:application_controller, :maybe_trigger_wechat_silent_login) do
    def maybe_trigger_wechat_silent_login
      return unless SiteSetting.wechat_silent_login_enabled
      # Only in WeChat's in-app browser unless admin turns it off (setting exists but defaults to true).
      only_wechat = SiteSetting.wechat_only_wechat_ua
      ua = request.user_agent.to_s
      is_wechat = ua.include?("MicroMessenger")
      return if only_wechat && !is_wechat

      # Already logged in -> do nothing
      return if current_user.present?
      # Skip for non-HTML or XHR or non-GET
      return unless request.get?
      return if request.xhr?
      # Skip admin and rails paths and our own endpoints
      path = request.path.to_s
      return if path.start_with?("/admin") || path.start_with?("/rails") || path.start_with?("/wx/")
      # Avoid loops if we've already tried very recently
      return if cookies.signed[:wx_checked] == "1"

      # Only proceed if we have app_id/secret set
      return if SiteSetting.wechat_app_id.blank? || SiteSetting.wechat_app_secret.blank?

      return_to = request.original_url
      redirect_to ::WechatSilentLogin::Engine.routes.url_helpers.silent_wechat_path(return_to: return_to)
    end
  end

  ApplicationController.prepend_before_action :maybe_trigger_wechat_silent_login
end
