# frozen_string_literal: true
class CreateLebanxWechatOpenid < ActiveRecord::Migration[7.0]
  def up
    return if ActiveRecord::Base.connection.table_exists?(:lebanx_wechat_openid)

    create_table :lebanx_wechat_openid do |t|
      t.string  :openid, null: false
      t.bigint  :user_id, null: false
      t.string  :username, null: false
      t.timestamps null: false
    end

    add_index :lebanx_wechat_openid, :openid, unique: true
    add_index :lebanx_wechat_openid, :user_id
  end

  def down
    drop_table :lebanx_wechat_openid if ActiveRecord::Base.connection.table_exists?(:lebanx_wechat_openid)
  end
end
