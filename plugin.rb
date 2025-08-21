# frozen_string_literal: true
# name: discourse-wechat-silent-login-20250821
# about: WeChat in-app silent login for Discourse using omniauth-wechat-oauth2; minimal, no logs
# version: 1.0.6
# authors: GleeBuild + ChatGPT
# required_version: 3.0.0
# url: https://meta.discourse.org/t/adding-a-new-managed-authentication-method-to-discourse/106695

enabled_site_setting :wechat_login_enabled

# Use official OmniAuth strategy for WeChat OAuth2
# https://github.com/NeverMin/omniauth-wechat-oauth2
gem 'omniauth-wechat-oauth2', '0.2.2'

after_initialize do
  require "securerandom"
  require "cgi"
end

# ---- Authenticator ----
class ::Auth::WeChatAuthenticator < ::Auth::ManagedAuthenticator
  def name
    "wechat"
  end

  def enabled?
    SiteSetting.wechat_login_enabled
  end

  # Supply appid/secret/scope at runtime (multisite friendly)
  def register_middleware(omniauth)
    omniauth.provider :wechat,
                      setup: lambda { |env|
                        strategy = env["omniauth.strategy"]
                        strategy.options[:client_id] = SiteSetting.wechat_appid
                        strategy.options[:client_secret] = SiteSetting.wechat_appsecret
                        strategy.options[:authorize_params] ||= {}
                        strategy.options[:authorize_params][:scope] = SiteSetting.wechat_scope
                      }
  end

  # Force our username/email rules to mirror WordPress plugin
  def after_authenticate(auth_token, existing_account: nil)
    # openid is uid from omniauth-wechat-oauth2
    openid = auth_token[:uid] || auth_token.dig(:extra, :raw_info, :openid)
    raise Discourse::InvalidAccess.new("Missing openid") if openid.blank?

    uname = "wx_" + Digest::MD5.hexdigest(openid)[0, 8]
    email = "#{uname}@lebanx.com"

    # ensure info struct has nickname/email
    auth_token[:info] ||= {}
    auth_token[:info][:email] ||= email
    auth_token[:info][:name] ||= uname
    auth_token[:info][:nickname] ||= uname

    # let ManagedAuthenticator link/store into user_associated_accounts etc.
    result = super

    # If Discourse is about to create a user, inject our defaults
    result.username ||= uname
    result.name ||= uname
    result.email ||= email
    result.email_valid = true

    # Store openid so we can look up later if needed
    result.extra_data ||= {}
    result.extra_data[:openid] = openid
    result
  end
end

# ---- Register provider (must be top-level, not inside after_initialize) ----
auth_provider authenticator: ::Auth::WeChatAuthenticator.new,
              icon: "fab-weixin"


# ---- Optional: light-weight silent login for in-app WeChat ----
after_initialize do
  class ::ApplicationController
    before_action :wechat_silent_auto_login

    private

    def wechat_silent_auto_login
      return unless SiteSetting.wechat_login_enabled
      return if current_user.present?
      return unless request.get?
      return unless request.format&.html?
      return if request.xhr?

      path = request.fullpath
      return if path.start_with?("/admin") || path.start_with?("/assets") || path.start_with?("/logs")
      return if path.start_with?("/user-api-key") || path.start_with?("/auth") || path.start_with?("/session")
      return if path.start_with?("/letter")

      # require creds
      return if SiteSetting.wechat_appid.blank? || SiteSetting.wechat_appsecret.blank?

      # Only trigger inside WeChat UA (can be disabled)
      if SiteSetting.wechat_only_wechat_ua
        ua = request.user_agent.to_s
        return unless ua.include?("MicroMessenger")
      end

      # Use OmniAuth entrypoint
      origin = request.original_fullpath
      session[:destination_url] = origin
      redirect_to "/auth/wechat"
    end
  end
end
