# frozen_string_literal: true

require "net/http"
require "json"
require "securerandom"
require "digest"

module WeChatSilentLogin
  class LoginController < ::ApplicationController
    skip_before_action :check_xhr, :verify_authenticity_token
    layout false

    def start
      state = SecureRandom.hex(16)
      session[:wechat_oauth_state] = state
      session[:wechat_origin] ||= params[:return_to].presence || "/"
      redirect_to helper.authorize_url(state)
    end

    def callback
      code = params[:code]
      state = params[:state]

      if state.blank? || state != session.delete(:wechat_oauth_state)
        helper.log("STATE_MISMATCH state=#{state} session=nil_or_diff")
        return redirect_back_with_error("state_mismatch")
      end

      if code.blank?
        helper.log("NO_CODE params=#{params.to_unsafe_h.inspect}")
        return redirect_back_with_error("no_code")
      end

      openid = helper.fetch_openid(code)
      if openid.blank?
        helper.log("OPENID_EXCHANGE_FAILED code=#{code}")
        return redirect_back_with_error("openid_exchange_failed")
      end

      session[:lebanx_openid] = openid
      helper.log("OPENID_OK #{openid}")

      # Login or create user and then redirect back
      helper.auto_login_with_openid(openid)

      origin = session.delete(:wechat_origin) || "/"
      origin = "/" if origin.to_s.start_with?("/wechat/")
      redirect_to origin
    end

    private

    def helper
      @helper ||= ::WeChatSilentLogin::LoginHelper.new(self)
    end

    def redirect_back_with_error(code)
      origin = session.delete(:wechat_origin) || "/"
      origin = "/" if origin.to_s.start_with?("/wechat/")
      origin = origin.sub(/[?&](code|state)=[^&]+/, "")
      redirect_to origin
    end
  end

  class LoginHelper
    def initialize(controller)
      @controller = controller
    end

    def base_url
      Discourse.base_url
    end

    def appid
      SiteSetting.wechat_appid.presence
    end

    def appsecret
      SiteSetting.wechat_appsecret.presence
    end

    def scope
      SiteSetting.wechat_scope
    end

    def callback_url
      "#{base_url}/wechat/callback"
    end

    def authorize_url(state)
      raise Discourse::InvalidAccess.new("WeChat AppID/Secret not configured") if appid.blank? || appsecret.blank?
      redirect_uri = CGI.escape(callback_url)
      "https://open.weixin.qq.com/connect/oauth2/authorize?appid=#{appid}&redirect_uri=#{redirect_uri}&response_type=code&scope=#{scope}&state=#{state}#wechat_redirect"
    end

    def fetch_openid(code)
      return nil if appid.blank? || appsecret.blank?
      uri = URI("https://api.weixin.qq.com/sns/oauth2/access_token?appid=#{appid}&secret=#{appsecret}&code=#{CGI.escape(code)}&grant_type=authorization_code")
      res = Net::HTTP.start(uri.host, uri.port, use_ssl: true, read_timeout: 8, open_timeout: 5) do |http|
        http.get(uri.request_uri)
      end
      json = JSON.parse(res.body) rescue {}
      if json["errcode"]
        log("WECHAT_ERR errcode=#{json["errcode"]} errmsg=#{json["errmsg"]}")
        return nil
      end
      json["openid"]
    rescue => e
      log("HTTP_ERR #{e.class}: #{e.message}")
      nil
    end

    # Mirrors WP username/email logic; password supports two modes
    def ensure_user_for_openid(openid)
      # 1) by custom field
      u = find_by_openid(openid)
      return u if u

      # derive username/email
      uname = "wx_" + Digest::MD5.hexdigest(openid)[0, 8]
      email = "#{uname}@lebanx.com"

      # 2) by username or email (to align with prior WP-created accounts)
      u = User.find_by(username_lower: uname.downcase) || User.find_by(email: email)
      if u
        set_openid_custom_field(u, openid)
        return u
      end

      # 3) create
      pwd = generate_password(openid)
      # Make sure username/email unique in Discourse
      candidate = uname
      i = 0
      while User.where(username_lower: candidate.downcase).exists?
        i += 1
        candidate = "wx_" + SecureRandom.hex(4)
        break if i > 3
      end
      uname = candidate
      email_candidate = email
      j = 0
      while User.where(email: email_candidate).exists?
        j += 1
        email_candidate = "#{uname}+#{j}@lebanx.com"
        break if j > 3
      end

      user = User.new(
        username: uname,
        email: email_candidate,
        password: pwd,
        active: true,
        approved: true
      )
      user.save!
      set_openid_custom_field(user, openid)
      log("USER_CREATED id=#{user.id} uname=#{user.username} email=#{user.email}")
      user
    end

    def auto_login_with_openid(openid)
      user = ensure_user_for_openid(openid)
      provider = Auth::DefaultCurrentUserProvider.new(@controller.request.env)
      provider.log_on_user(user, @controller.session, @controller.cookies, {})
      user
    end

    def generate_password(openid)
      mode = SiteSetting.wechat_password_mode
      if mode == "derive_from_openid"
        salt = SiteSetting.wechat_password_salt.to_s
        Digest::SHA256.hexdigest("#{openid}#{salt}")[0, 32]
      else
        # random: mirrors WP random behavior (not equal across apps)
        SecureRandom.hex(12)
      end
    end

    def find_by_openid(openid)
      field_name = "lebanx_wechat_openid"
      UserCustomField
        .where(name: field_name, value: openid)
        .joins("JOIN users ON users.id = user_custom_fields.user_id")
        .select("users.*").first
    end

    def set_openid_custom_field(user, openid)
      user.custom_fields["lebanx_wechat_openid"] = openid
      user.save_custom_fields
    end

    def log(msg)
      return unless SiteSetting.wechat_log_enabled
      Rails.logger.warn("[WeChatLogin] #{msg}")
    end
  end
end
