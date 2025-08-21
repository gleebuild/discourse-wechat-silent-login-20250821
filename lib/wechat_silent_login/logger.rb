# frozen_string_literal: true

require "json"
require "time"

module WeChatSilentLogin
  class Logger
    KEY = "wechat_login:events"

    def self.push(msg)
      return unless SiteSetting.wechat_log_enabled
      payload = { ts: Time.now.utc.iso8601, msg: msg }.to_json
      max = SiteSetting.wechat_log_buffer_size.to_i
      max = 400 if max <= 0
      Discourse.redis.pipelined do |p|
        p.lpush(KEY, payload)
        p.ltrim(KEY, 0, max - 1)
      end
    rescue => e
      Rails.logger.warn("[WeChatLogin] REDIS_LOG_ERR #{e.class}: #{e.message}")
    end

    def self.list(limit = 200, offset = 0)
      limit = 1 if limit <= 0
      limit = 1000 if limit > 1000
      arr = Discourse.redis.lrange(KEY, offset, offset + limit - 1) || []
      arr.map do |row|
        JSON.parse(row) rescue { ts: nil, msg: row.to_s }
      end
    end

    def self.clear
      Discourse.redis.del(KEY)
    end
  end
end
