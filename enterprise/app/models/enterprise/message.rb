module Enterprise::Message
  CAPTAIN_NEW_ROUND_INACTIVITY_WINDOW = 72.hours

  private

  def reopen_conversation
    super
    reopen_pending_captain_conversation_for_recent_contact_reply
  end

  def mark_pending_conversation_as_open_for_human_response
    return unless captain_pending_conversation?
    return unless human_response?
    return if private?

    previous_user = Current.user
    previous_executed_by = Current.executed_by
    Current.user = nil
    Current.executed_by = nil

    begin
      conversation.open!
      return unless conversation.saved_change_to_status?

      create_captain_auto_open_activity_message
    ensure
      Current.user = previous_user
      Current.executed_by = previous_executed_by
    end
  end

  def captain_pending_conversation?
    return false unless conversation.pending?

    ::CaptainInbox.exists?(inbox_id: conversation.inbox_id)
  end

  def reopen_pending_captain_conversation_for_recent_contact_reply
    return unless captain_pending_conversation?
    return unless incoming?
    return if private?
    return if conversation.campaign.present?
    return if captain_new_round?

    previous_user = Current.user
    previous_executed_by = Current.executed_by
    Current.user = nil
    Current.executed_by = sender if sender.instance_of?(::Contact)

    begin
      conversation.open!
    ensure
      Current.user = previous_user
      Current.executed_by = previous_executed_by
    end
  end

  def captain_new_round?
    previous_public_message_at.blank? || previous_public_message_at <= created_at - CAPTAIN_NEW_ROUND_INACTIVITY_WINDOW
  end

  def previous_public_message_at
    @previous_public_message_at ||= ::Message
      .joins(:conversation)
      .where(account_id: conversation.account_id, inbox_id: conversation.inbox_id)
      .where(conversations: { contact_inbox_id: conversation.contact_inbox_id })
      .where(message_type: %i[incoming outgoing], private: false)
      .where.not(id: id)
      .order(created_at: :desc, id: :desc)
      .pick(:created_at)
  end

  def create_captain_auto_open_activity_message
    ::Conversations::ActivityMessageJob.perform_later(
      conversation,
      account_id: conversation.account_id,
      inbox_id: conversation.inbox_id,
      message_type: :activity,
      content: I18n.t('conversations.activity.captain.auto_opened_after_agent_reply', locale: conversation.account.locale)
    )
  end
end
