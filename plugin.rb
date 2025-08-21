# frozen_string_literal: true
# name: discourse-wechat-silent-login-20250821
# about: WeChat in-app silent login for Discourse using omniauth-wechat-oauth2; manual authorize redirect (no confirm page)
# version: 1.0.7
# authors: GleeBuild + ChatGPT
# required_version: 3.0.0

enabled_site_setting :wechat_login_enabled

gem 'omniauth-wechat-oauth2', '0.2.2'

# --- ManagedAuthenticator ---
class ::Auth::WeChatAuthenticator < ::Auth::ManagedAuthenticator
  def name
    "wechat"
  end

  def enabled?
    SiteSetting.wechat_login_enabled
  end

  def register_middleware(omniauth)
    omniauth.provider :wechat,
                      setup: lambda { |env|
                        s = env["omniauth.strategy"]
                        s.options[:client_id] = SiteSetting.wechat_appid
                        s.options[:client_secret] = SiteSetting.wechat_appsecret
                        s.options[:scope] = (SiteSetting.wechat_scope.presence || "snsapi_base")
                      }
  end

  def after_authenticate(auth_token, existing_account: nil)
    openid = auth_token[:uid] || auth_token.dig(:extra, :raw_info, :openid)
    raise Discourse::InvalidAccess.new("Missing openid") if openid.blank?

    uname = "wx_" + Digest::MD5.hexdigest(openid)[0, 8]
    email = "#{uname}@lebanx.com"

    auth_token[:info] ||= {}
    auth_token[:info][:email] ||= email
    auth_token[:info][:name] ||= uname
    auth_token[:info][:nickname] ||= uname

    result = super
    result.username ||= uname
    result.name ||= uname
    result.email ||= email
    result.email_valid = true
    result.extra_data ||= {}
    result.extra_data[:openid] = openid
    result
  end
end

auth_provider authenticator: ::Auth::WeChatAuthenticator.new,
              icon: "fab-weixin"


after_initialize do
  require "securerandom"
  require "cgi"

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

      # require credentials
      appid = SiteSetting.wechat_appid.presence
      secret = SiteSetting.wechat_appsecret.presence
      return if appid.blank? || secret.blank?

      if SiteSetting.wechat_only_wechat_ua
        ua = request.user_agent.to_s
        return unless ua.include?("MicroMessenger")
      end

      # Build WeChat authorize URL directly to avoid OmniAuth interstitial
      state = SecureRandom.hex(16)
      session[:wechat_auto_state] = state
      session[:destination_url] = request.original_fullpath

      redirect_uri = CGI.escape("#{Discourse.base_url}/auth/wechat/callback")
      scope = (SiteSetting.wechat_scope.presence || "snsapi_base")
      url = "https://open.weixin.qq.com/connect/oauth2/authorize?appid=#{appid}&redirect_uri=#{redirect_uri}&response_type=code&scope=#{scope}&state=#{state}#wechat_redirect"
      redirect_to url
    end
  end
end
