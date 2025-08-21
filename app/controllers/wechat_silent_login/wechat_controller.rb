# frozen_string_literal: true
require_dependency "application_controller"
require "net/http"
require "uri"
require "json"
require "digest/md5"
require "securerandom"

module WechatSilentLogin
  class WechatController < ::ApplicationController
    skip_before_action :check_xhr, only: [:silent, :callback]
    skip_before_action :verify_authenticity_token, only: [:callback]

    def silent
      raise Discourse::NotFound unless SiteSetting.wechat_silent_login_enabled

      if SiteSetting.wechat_only_wechat_ua && !wechat_ua?
        cookies.signed[:wx_checked] = { value: "1", path: "/", secure: request.ssl?, httponly: true, expires: 30.minutes.from_now }
        return redirect_back_or_root
      end

      # If already logged in, mark checked and return
      if current_user
        cookies.signed[:wx_checked] = { value: "1", path: "/", secure: request.ssl?, httponly: true, expires: 30.minutes.from_now }
        return redirect_back_or_root
      end

      app_id = SiteSetting.wechat_app_id
      app_secret = SiteSetting.wechat_app_secret
      if app_id.blank? || app_secret.blank?
        cookies.signed[:wx_checked] = { value: "1", path: "/", secure: request.ssl?, httponly: true, expires: 30.minutes.from_now }
        return redirect_back_or_root
      end

      return_to = safe_return_to(params[:return_to])
      state = SecureRandom.hex(8)
      cookies.signed[:wx_state] = { value: state, path: "/", secure: request.ssl?, httponly: true, expires: 10.minutes.from_now }
      callback_url = callback_url_with_return_to(return_to)

      auth_url = "https://open.weixin.qq.com/connect/oauth2/authorize" \
                 "?appid=#{CGI.escape(app_id)}" \
                 "&redirect_uri=#{CGI.escape(callback_url)}" \
                 "&response_type=code" \
                 "&scope=snsapi_base" \
                 "&state=#{CGI.escape(state)}#wechat_redirect"

      redirect_to auth_url
    end

    def callback
      raise Discourse::NotFound unless SiteSetting.wechat_silent_login_enabled

      unless wechat_ua? || !SiteSetting.wechat_only_wechat_ua
        cookies.signed[:wx_checked] = { value: "1", path: "/", secure: request.ssl?, httponly: true, expires: 30.minutes.from_now }
        return redirect_back_or_root
      end

      app_id = SiteSetting.wechat_app_id
      app_secret = SiteSetting.wechat_app_secret
      if app_id.blank? || app_secret.blank?
        cookies.signed[:wx_checked] = { value: "1", path: "/", secure: request.ssl?, httponly: true, expires: 30.minutes.from_now }
        return redirect_back_or_root
      end

      state = params[:state].to_s
      if state.blank? || cookies.signed[:wx_state] != state
        # State mismatch: avoid loop and bail
        cookies.signed[:wx_checked] = { value: "1", path: "/", secure: request.ssl?, httponly: true, expires: 30.minutes.from_now }
        return redirect_back_or_root
      end

      code = params[:code].to_s
      if code.blank?
        cookies.signed[:wx_checked] = { value: "1", path: "/", secure: request.ssl?, httponly: true, expires: 30.minutes.from_now }
        return redirect_back_or_root
      end

      openid = fetch_openid(app_id, app_secret, code)
      if openid.blank?
        cookies.signed[:wx_checked] = { value: "1", path: "/", secure: request.ssl?, httponly: true, expires: 30.minutes.from_now }
        return redirect_back_or_root
      end

      # If already logged in, do nothing
      if current_user
        cookies.signed[:wx_checked] = { value: "1", path: "/", secure: request.ssl?, httponly: true, expires: 30.minutes.from_now }
        return redirect_back_or_root
      end

      user = ensure_user_for_openid!(openid)

      # Log the user in silently
      begin
        if respond_to?(:log_on_user)
          log_on_user(user)
        else
          # Fallback (normally log_on_user exists on ApplicationController)
          session[:current_user_id] = user.id
        end
      rescue => e
        Rails.logger.warn("[wechat_silent_login] log_on_user failed: #{e.class}: #{e.message}")
      end

      cookies.signed[:wx_checked] = { value: "1", path: "/", secure: request.ssl?, httponly: true, expires: 12.hours.from_now }

      redirect_back_or_root
    end

    private

    def wechat_ua?
      request.user_agent.to_s.include?("MicroMessenger")
    end

    def redirect_back_or_root
      return_to = safe_return_to(params[:return_to])
      if return_to
        redirect_to return_to
      else
        redirect_to "/"
      end
    end

    def safe_return_to(rt)
      return nil if rt.blank?
      begin
        uri = URI(rt)
        # Only allow same host
        if uri.host.nil? || uri.host == request.host
          return rt
        end
      rescue
      end
      nil
    end

    def callback_url_with_return_to(return_to)
      base = "#{request.base_url}/wx/callback"
      return_to.present? ? "#{base}?return_to=#{CGI.escape(return_to)}" : base
    end

    def fetch_openid(app_id, app_secret, code)
      url = URI("https://api.weixin.qq.com/sns/oauth2/access_token?appid=#{CGI.escape(app_id)}&secret=#{CGI.escape(app_secret)}&code=#{CGI.escape(code)}&grant_type=authorization_code")
      http = Net::HTTP.new(url.host, url.port)
      http.use_ssl = true
      http.read_timeout = 6
      req = Net::HTTP::Get.new(url)
      resp = http.request(req)
      data = JSON.parse(resp.body) rescue {}
      data["openid"]
    rescue => e
      Rails.logger.warn("[wechat_silent_login] fetch_openid error: #{e.class}: #{e.message}")
      nil
    end

    def ensure_user_for_openid!(openid)
      mapping = ::LebanxWechatOpenid.find_by(openid: openid)
      if mapping && mapping.user_id
        user = User.find_by(id: mapping.user_id)
        return user if user
        # Orphaned mapping -> delete and recreate
        mapping.destroy
      end

      # Not found -> create
      username = build_username_from_openid(openid)
      email = "#{username}@lebanx.com"
      password = SecureRandom.hex(16)

      user = User.find_by_username(username)
      if user.blank?
        user = User.create!(
          username: username,
          email: email,
          password: password,
          active: true,
          approved: true
        )
      end

      ::LebanxWechatOpenid.create!(
        openid: openid,
        user_id: user.id,
        username: username
      )

      user
    end

    def build_username_from_openid(openid)
      base = "wx_#{Digest::MD5.hexdigest(openid)[0,8]}"
      uname = base
      suffix = 0
      while User.username_exists?(uname)
        suffix += 1
        uname = "#{base}#{suffix}"
      end
      uname
    end
  end
end
