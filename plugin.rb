
# frozen_string_literal: true
# name: discourse-wechat-silent-login-20250821
# about: Silent login in WeChat for Discourse homepage, mirroring WP username/email generation and logging each step
# version: 1.0.0
# authors: GleeBuild + ChatGPT
# required_version: 3.0.0
# url: https://lebanx.com

enabled_site_setting :wechat_silent_login_enabled

after_initialize do
  require 'net/http'
  require 'uri'
  require 'json'
  require 'securerandom'
  require 'fileutils'
  require_dependency 'application_controller'

  # ---- Verified logger block (copied as requested) ----
  module ::DiscourseWechatHomeLogger
    LOG_DIR = "/var/www/discourse/public"
    LOG_FILE = File.join(LOG_DIR, "wechat.txt")
    HOMEPATHS = ['/', '/latest', '/categories', '/top', '/new', '/hot'].freeze

    def self.log!(message)
      begin
        FileUtils.mkdir_p(LOG_DIR) unless Dir.exist?(LOG_DIR)
        timestamp = Time.now.strftime("%Y-%m-%d %H:%M:%S %z")
        File.open(LOG_FILE, "a") { |f| f.puts("#{timestamp} | #{message}") }
      rescue => e
        Rails.logger.warn("[wechat-home-logger] write error: #{e.class}: #{e.message}")
      end
    end
  end

  # ---- Helpers for silent login ----
  module ::DiscourseWechatSilent
    COOKIE_NAME = 'lebanx_openid'

    def self.enabled?
      SiteSetting.wechat_silent_login_enabled
    end

    def self.wechat_browser?(request)
      ua = request.user_agent.to_s
      ua.include?('MicroMessenger')
    end

    def self.home_like_path?(path)
      ::DiscourseWechatHomeLogger::HOMEPATHS.include?(path)
    end

    def self.log(msg)
      ::DiscourseWechatHomeLogger.log!(msg)
    end

    def self.app_id
      SiteSetting.wechat_app_id.to_s.strip
    end

    def self.app_secret
      SiteSetting.wechat_app_secret.to_s.strip
    end

    def self.cookie_domain
      d = SiteSetting.wechat_cookie_domain.to_s.strip
      d.empty? ? nil : d
    end

    def self.scope
      s = SiteSetting.wechat_scope.to_s.strip
      s.empty? ? "snsapi_base" : s
    end

    def self.build_auth_url(request, redirect_url, state)
      uri = URI("https://open.weixin.qq.com/connect/oauth2/authorize")
      params = {
        appid: app_id,
        redirect_uri: redirect_url,
        response_type: "code",
        scope: scope,
        state: state
      }
      query = URI.encode_www_form(params)
      "#{uri}?#{query}#wechat_redirect"
    end

    def self.exchange_openid(code)
      url = URI("https://api.weixin.qq.com/sns/oauth2/access_token")
      url.query = URI.encode_www_form({
        appid: app_id,
        secret: app_secret,
        code: code,
        grant_type: "authorization_code"
      })
      http = Net::HTTP.new(url.host, url.port)
      http.use_ssl = true
      http.read_timeout = 6
      http.open_timeout = 6
      res = http.get(url.request_uri)
      body = res.body.to_s
      data = JSON.parse(body) rescue {}
      [data["openid"], body]
    rescue => e
      [nil, "exception: #{e.class}: #{e.message}"]
    end

    def self.ensure_user_for_openid(openid)
      # Find by user custom field first
      ucf = UserCustomField.find_by(name: "lebanx_wechat_openid", value: openid)
      user = ucf&.user
      return user if user

      # Build username & email per WP logic
      base = "wx_" + Digest::MD5.hexdigest(openid)[0,8]
      username = base
      # ensure unique username
      idx = 0
      while User.where("lower(username) = ?", username.downcase).exists?
        idx += 1
        username = "wx_" + SecureRandom.hex(4)
        break if idx > 3
      end
      email = "#{username}@lebanx.com"
      # ensure unique email
      if User.where("lower(email) = ?", email.downcase).exists?
        email = "#{username}+#{SecureRandom.hex(2)}@lebanx.com"
      end

      # Random password to mirror WP's wp_generate_password() behavior.
      password = SecureRandom.base64(24)

      user = User.new(
        username: username,
        name: username,
        email: email,
        password: password,
        active: true,
        approved: true
      )
      # Skip email/username validations (best-effort); Discourse will still enforce basics
      user.save!
      # bind custom field
      UserCustomField.create!(user_id: user.id, name: "lebanx_wechat_openid", value: openid)
      user
    end

    def self.log_in!(controller, user)
      controller.send(:log_on_user, user)
      controller.request.env[:jwt_token] = nil # avoid confusing frontend cache
    end
  end

  class ::ApplicationController
    before_action :wechat_silent_login_hook

    private

    def wechat_silent_login_hook
      return unless ::DiscourseWechatSilent.enabled?

      # Only act on homepage-like HTML GET requests
      return unless request.get?
      is_html = false
      begin
        is_html ||= request.format&.html?
      rescue
      end
      begin
        is_html ||= response&.content_type.to_s.include?('text/html')
      rescue
      end
      return unless is_html
      path = request.path
      return unless ::DiscourseWechatSilent.home_like_path?(path)

      ::DiscourseWechatSilent.log("enter hook path=#{path} logged_in=#{current_user.present?}")

      # WeChat UA only
      unless ::DiscourseWechatSilent.wechat_browser?(request)
        ::DiscourseWechatSilent.log("skip: not wechat ua: #{request.user_agent.to_s[0,80]}")
        return
      end

      # If already logged in, but ensure cookie exists
      if current_user
        if cookies[::DiscourseWechatSilent::COOKIE_NAME].present?
          ::DiscourseWechatSilent.log("already logged in and cookie present; noop")
          return
        else
          ucf = current_user.custom_fields["lebanx_wechat_openid"]
          if ucf.present?
            cookies[::DiscourseWechatSilent::COOKIE_NAME] = {
              value: ucf,
              path: "/",
              domain: ::DiscourseWechatSilent.cookie_domain,
              secure: request.ssl?,
              same_site: :lax,
              httponly: false
            }
            ::DiscourseWechatSilent.log("cookie set from user custom field")
            return
          end
        end
      end

      # If cookie already has openid -> try login/create without calling WeChat
      openid_cookie = cookies[::DiscourseWechatSilent::COOKIE_NAME]
      if openid_cookie.present?
        ::DiscourseWechatSilent.log("openid cookie detected, attempting local login")
        begin
          user = ::DiscourseWechatSilent.ensure_user_for_openid(openid_cookie)
          ::DiscourseWechatSilent.log_in!(self, user)
          ::DiscourseWechatSilent.log("login success via cookie user_id=#{user.id}")
        rescue => e
          ::DiscourseWechatSilent.log("login via cookie failed: #{e.class}: #{e.message}")
        end
        return
      end

      # If we have an OAuth code -> exchange
      if params[:code].present?
        if params[:state].present? && session[:wechat_state].present? && params[:state].to_s == session[:wechat_state].to_s
          ::DiscourseWechatSilent.log("callback with code; state ok")
        else
          ::DiscourseWechatSilent.log("callback with code; state mismatch exp=#{session[:wechat_state]} got=#{params[:state]}")
          return
        end

        openid, raw = ::DiscourseWechatSilent.exchange_openid(params[:code])
        if openid.blank?
          ::DiscourseWechatSilent.log("exchange openid failed body=#{raw}")
          return
        end
        ::DiscourseWechatSilent.log("openid obtained=#{openid}")

        # set cookie
        cookies[::DiscourseWechatSilent::COOKIE_NAME] = {
          value: openid,
          path: "/",
          domain: ::DiscourseWechatSilent.cookie_domain,
          secure: request.ssl?,
          same_site: :lax,
          httponly: false
        }

        # ensure user & login
        begin
          user = ::DiscourseWechatSilent.ensure_user_for_openid(openid)
          ::DiscourseWechatSilent.log_in!(self, user)
          ::DiscourseWechatSilent.log("login success via exchange user_id=#{user.id}")
        rescue => e
          ::DiscourseWechatSilent.log("ensure/login failed: #{e.class}: #{e.message}")
        end

        # clean URL (remove code/state)
        clean = request.original_fullpath.dup
        begin
          clean = URI.parse(request.original_url)
          params_hash = Rack::Utils.parse_nested_query(clean.query || "")
          params_hash.delete("code")
          params_hash.delete("state")
          clean.query = params_hash.empty? ? nil : URI.encode_www_form(params_hash)
          clean = clean.to_s
        rescue
          clean = request.path
        end
        ::DiscourseWechatSilent.log("redirect clean #{clean}")
        redirect_to clean and return
      end

      # Otherwise, initiate OAuth if not logged in
      if ::DiscourseWechatSilent.app_id.blank? || ::DiscourseWechatSilent.app_secret.blank?
        ::DiscourseWechatSilent.log("missing app id/secret; abort")
        return
      end

      session[:wechat_origin] = request.original_url
      state = SecureRandom.hex(8)
      session[:wechat_state] = state
      # redirect_uri: current url; WeChat requires URL-encoded full URL under registered domain
      redirect_uri = request.original_url
      auth_url = ::DiscourseWechatSilent.build_auth_url(request, redirect_uri, state)
      ::DiscourseWechatSilent.log("redirect to wechat auth auth_url=#{auth_url[0,120]}...")
      redirect_to auth_url and return
    rescue => e
      ::DiscourseWechatSilent.log("hook error: #{e.class}: #{e.message}")
    end

    # Preserve the verified page-load after_action logger exactly as given
    after_action :wechat_home_logger_track
    def wechat_home_logger_track
      return unless request.get?
      html = false
      begin
        html ||= request.format&.html?
      rescue
      end
      begin
        html ||= response&.content_type.to_s.include?('text/html')
      rescue
      end
      path = request.path
      return unless ::DiscourseWechatHomeLogger::HOMEPATHS.include?(path)
      ::DiscourseWechatHomeLogger.log!("page load")
    rescue => e
      Rails.logger.warn("[wechat-home-logger] filter error: #{e.class}: #{e.message}")
    end
  end
end
