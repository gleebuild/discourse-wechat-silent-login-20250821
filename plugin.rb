# frozen_string_literal: true
# name: discourse-wechat-silent-login-20250821
# about: WeChat in-app (MicroMessenger) silent login for Discourse; mirrors WP Lebanx plugin's username/email logic + admin log viewer
# version: 1.0.3
# authors: GleeBuild + ChatGPT
# required_version: 3.0.0

enabled_site_setting :wechat_login_enabled

register_asset 'javascripts/discourse/initializers/wechat-admin-route.js'
register_asset 'javascripts/discourse/routes/admin-plugins-wechat-logs.js'
register_asset 'javascripts/discourse/controllers/admin-plugins-wechat-logs.js'
register_asset 'javascripts/discourse/templates/admin/plugins-wechat-logs.hbs'

after_initialize do
  require "securerandom"
  require "cgi"

  module ::WeChatSilentLogin
    PLUGIN_NAME = "discourse-wechat-silent-login-20250821"
  end

  require_relative "lib/wechat_silent_login/engine"
  require_relative "lib/wechat_silent_login/logger"

  class ::ApplicationController
    before_action :wechat_silent_login_if_needed

    private

    def wechat_silent_login_if_needed
      return unless SiteSetting.wechat_login_enabled
      return if current_user.present?
      return unless request.get?
      fmt = request.format
      return unless fmt && fmt.html?
      return if request.xhr?
      path = request.fullpath
      return if path.start_with?("/admin") || path.start_with?("/assets") || path.start_with?("/logs")
      return if path.start_with?("/user-api-key") || path.start_with?("/auth") || path.start_with?("/session")
      return if path.start_with?("/u/") || path.start_with?("/users/")
      return if path.start_with?("/letter")
      return if path.start_with?("/wechat/")

      # require APPID/SECRET configured, otherwise do nothing (prevents 500)
      if SiteSetting.wechat_appid.blank? || SiteSetting.wechat_appsecret.blank?
        return
      end

      if SiteSetting.wechat_only_wechat_ua
        ua = request.user_agent.to_s
        return unless ua.include?("MicroMessenger")
      end

      if session[:lebanx_openid].present?
        begin
          ::WeChatSilentLogin::LoginHelper.new(self).auto_login_with_openid(session[:lebanx_openid])
        rescue => e
          Rails.logger.warn("[WeChatLogin] AUTO_LOGIN_ERR #{e.class}: #{e.message}")
          ::WeChatSilentLogin::Logger.push("AUTO_LOGIN_ERR #{e.class}: #{e.message}")
        end
        return
      end

      origin = request.original_fullpath
      session[:wechat_origin] = origin
      state = SecureRandom.hex(16)
      session[:wechat_oauth_state] = state

      begin
        url = ::WeChatSilentLogin::LoginHelper.new(self).authorize_url(state)
        redirect_to url
      rescue => e
        Rails.logger.warn("[WeChatLogin] AUTH_URL_ERR #{e.class}: #{e.message}")
        ::WeChatSilentLogin::Logger.push("AUTH_URL_ERR #{e.class}: #{e.message}")
      end
    end
  end
end
