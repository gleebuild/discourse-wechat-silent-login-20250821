# frozen_string_literal: true
class LebanxWechatOpenid < ActiveRecord::Base
  self.table_name = "lebanx_wechat_openid"

  belongs_to :user

  validates :openid, presence: true, uniqueness: true
end
