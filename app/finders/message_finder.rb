class MessageFinder
  CURSOR_ORDER_ASC = { created_at: :asc, id: :asc }.freeze
  CURSOR_ORDER_DESC = { created_at: :desc, id: :desc }.freeze

  def initialize(conversation, params)
    @conversation = conversation
    @params = params
  end

  def perform
    current_messages
  end

  private

  def conversation_messages
    @conversation.messages.includes(:attachments, :sender, sender: { avatar_attachment: [:blob] })
  end

  def messages
    return conversation_messages if @params[:filter_internal_messages].blank?

    conversation_messages.where.not('private = ? OR message_type = ?', true, 2)
  end

  def current_messages
    if @params[:after].present? && @params[:before].present?
      messages_between(@params[:after].to_i, @params[:before].to_i)
    elsif @params[:before].present?
      messages_before(@params[:before].to_i)
    elsif @params[:after].present?
      messages_after(@params[:after].to_i)
    else
      messages_latest
    end
  end

  def messages_after(after_id)
    cursor = cursor_message(after_id)
    return messages.none if cursor.blank?

    apply_after_cursor(messages.reorder(CURSOR_ORDER_ASC), cursor).limit(100)
  end

  def messages_before(before_id)
    cursor = cursor_message(before_id)
    return messages.none if cursor.blank?

    apply_before_cursor(messages.reorder(CURSOR_ORDER_DESC), cursor).limit(20).reverse
  end

  def messages_between(after_id, before_id)
    after_cursor = cursor_message(after_id)
    before_cursor = cursor_message(before_id)
    return messages.none if after_cursor.blank? || before_cursor.blank?

    messages.reorder(CURSOR_ORDER_ASC)
            .yield_self { |scope| apply_after_cursor(scope, after_cursor, inclusive: true) }
            .yield_self { |scope| apply_before_cursor(scope, before_cursor) }
            .limit(1000)
  end

  def messages_latest
    messages.reorder(CURSOR_ORDER_DESC).limit(20).reverse
  end

  def cursor_message(message_id)
    messages.find_by(id: message_id)
  end

  def apply_after_cursor(scope, cursor, inclusive: false)
    operator = inclusive ? '>=' : '>'

    scope.where(
      "messages.created_at > :created_at OR (messages.created_at = :created_at AND messages.id #{operator} :id)",
      created_at: cursor.created_at,
      id: cursor.id
    )
  end

  def apply_before_cursor(scope, cursor)
    scope.where(
      'messages.created_at < :created_at OR (messages.created_at = :created_at AND messages.id < :id)',
      created_at: cursor.created_at,
      id: cursor.id
    )
  end
end
