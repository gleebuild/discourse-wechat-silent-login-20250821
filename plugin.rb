# frozen_string_literal: true
# name: discourse-wechat-silent-login-20250821
# about: WeChat in-app (MicroMessenger) silent login for Discourse; mirrors WP Lebanx plugin's username/email logic
# version: 1.0.0
# authors: GleeBuild + ChatGPT
# required_version: 3.0.0
# url: https://lebanx.com

enabled_site_setting :wechat_login_enabled

after_initialize do
  module ::WeChatSilentLogin
    PLUGIN_NAME = "discourse-wechat-silent-login-20250821"
  end

  require_relative "lib/wechat_silent_login/engine"

  # Auto-trigger before_action on HTML GET requests when conditions match
  class ::ApplicationController
    before_action :wechat_silent_login_if_needed

    private

    def wechat_silent_login_if_needed
      return unless SiteSetting.wechat_login_enabled
      return if current_user.present?
      return unless request.get?
      return unless request.format&.html?
      return if request.xhr?

      # skip admin, assets, and plugin's own routes
      path = request.fullpath
      return if path.start_with?("/admin") || path.start_with?("/assets") || path.start_with?("/logs")
      return if path.start_with?("/user-api-key") || path.start_with?("/auth") || path.start_with?("/session")
      return if path.start_with?("/u/") || path.start_with?("/users/")
      return if path.start_with?("/wechat/") # avoid recursion
      return if (request.env["DISCOURSE_IS_API"] rescue false)

      # Only in WeChat built-in browser if setting enforces it
      if SiteSetting.wechat_only_wechat_ua
        ua = request.user_agent.to_s
        return unless ua.include?("MicroMessenger")
      end

      # If already have openid in session, try login quickly (handles server restarts gracefully)
      if session[:lebanx_openid].present?
        ::WeChatSilentLogin::LoginHelper.new(self).auto_login_with_openid(session[:lebanx_openid])
        return
      end

      # Prepare OAuth redirect
      origin = request.original_fullpath
      session[:wechat_origin] = origin

      state = SecureRandom.hex(16)
      session[:wechat_oauth_state] = state

      redirect_to ::WeChatSilentLogin::LoginHelper.new(self).authorize_url(state)
    end
  end
end
