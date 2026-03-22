class AddAutoReplyDisabledContactPhoneNumbersToInboxes < ActiveRecord::Migration[7.0]
  def change
    add_column :inboxes, :auto_reply_disabled_contact_phone_numbers, :text
  end
end
