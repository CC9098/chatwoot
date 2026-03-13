class Api::V1::Accounts::TodosController < Api::V1::Accounts::BaseController
  TODO_LINE_PATTERN = '(^|\n)\s*(?:[-*+]|\d+\.)\s+\[( |x|X)\]\s+'.freeze

  def index
    render json: {
      payload: todo_notes_payload,
      meta: {
        total_notes: todo_notes.size
      }
    }
  end

  private

  def todo_notes
    @todo_notes ||= Message.where(
      account: Current.account,
      private: true,
      content_type: :text,
      conversation_id: accessible_conversations.select(:id)
    ).where.not(content: [nil, ''])
     .where('content ~* ?', TODO_LINE_PATTERN)
     .includes(
       :sender,
       conversation: [
         :team,
         :inbox,
         { contact: { avatar_attachment: [:blob] } },
         { assignee: { avatar_attachment: [:blob] } }
       ]
     )
     .reorder(updated_at: :desc)
  end

  def accessible_conversations
    @accessible_conversations ||= Conversations::PermissionFilterService.new(
      Current.account.conversations,
      Current.user,
      Current.account
    ).perform
  end

  def todo_notes_payload
    todo_notes.map do |note|
      {
        id: note.id,
        content: note.content,
        created_at: note.created_at.to_i,
        updated_at: note.updated_at.to_i,
        sender: serialized_actor(note.sender, note.inbox),
        conversation: serialized_conversation(note.conversation)
      }
    end
  end

  def serialized_conversation(conversation)
    assigned_entity = conversation.assigned_entity

    {
      id: conversation.display_id,
      status: conversation.status,
      inbox_id: conversation.inbox_id,
      inbox: {
        id: conversation.inbox.id,
        name: conversation.inbox.name,
        channel_type: conversation.inbox.channel_type
      },
      meta: {
        sender: conversation.contact.push_event_data,
        assignee: serialized_actor(assigned_entity, conversation.inbox),
        assignee_type: assigned_entity&.class&.name,
        team: conversation.team&.push_event_data
      },
      updated_at: conversation.updated_at.to_i
    }
  end

  def serialized_actor(actor, inbox)
    return if actor.blank?

    return actor.push_event_data(inbox) if actor.is_a?(AgentBot)

    actor.push_event_data
  end
end
