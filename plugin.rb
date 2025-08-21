# frozen_string_literal: true
# name: discourse-wechat-silent-login-20250821
# about: WeChat in-app silent login for Discourse; direct authorize redirect; hardcoded snsapi_base; optional callback host
# version: 1.1.0
# authors: GleeBuild + ChatGPT
# required_version: 3.0.0

enabled_site_setting :wechat_login_enabled

# Use OmniAuth WeChat for callback and user provisioning
gem 'omniauth-wechat-oauth2', '0.2.2'

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
                        # Keep strategy scope explicit; we always request snsapi_base from our redirect
                        s.options[:scope] = "snsapi_base"
                      }
  end

  def after_authenticate(auth_token, existing_account: nil)
    # openid should be the uid
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
  require "uri"

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

      appid = SiteSetting.wechat_appid.presence
      secret = SiteSetting.wechat_appsecret.presence
      return if appid.blank? || secret.blank?

      if SiteSetting.wechat_only_wechat_ua
        ua = request.user_agent.to_s
        return unless ua.include?("MicroMessenger")
      end

      # Build direct authorize URL (no OmniAuth interstitial)
      state = SecureRandom.hex(16)
      # Ensure OmniAuth's CSRF state check passes when callback happens
      session["omniauth.state"] = state
      session[:destination_url] = request.original_fullpath

      base = URI(Discourse.base_url)
      callback_host = SiteSetting.wechat_callback_host.presence || base.host
      scheme = base.scheme || "https"
      redirect_uri = CGI.escape("#{scheme}://#{callback_host}/auth/wechat/callback")

      scope = "snsapi_base" # silent login only
      url = "https://open.weixin.qq.com/connect/oauth2/authorize?appid=#{appid}&redirect_uri=#{redirect_uri}&response_type=code&scope=#{scope}&state=#{state}#wechat_redirect"
      redirect_to url
    end
  end
end
