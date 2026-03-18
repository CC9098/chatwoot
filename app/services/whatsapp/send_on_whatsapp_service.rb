class Whatsapp::SendOnWhatsappService < Base::SendOnChannelService
  TEMPLATE_NOT_FOUND_ERROR = 'Template not found or invalid template name'.freeze
  TEMPLATE_TRANSLATION_NOT_FOUND_ERROR =
    'Template translation not found for this inbox. Refresh WhatsApp templates and choose an approved language.'.freeze

  private

  def channel_class
    Channel::Whatsapp
  end

  def perform_reply
    should_send_template_message = template_params.present? || !message.conversation.can_reply?
    if should_send_template_message
      send_template_message
    else
      send_session_message
    end
  end

  def send_template_message
    name, namespace, lang_code, processed_parameters = build_template_payload

    if name.blank?
      message.update!(status: :failed, external_error: TEMPLATE_NOT_FOUND_ERROR)
      return
    end

    if processed_parameters.nil?
      retry_template_send_after_sync
      return
    end

    message_id = deliver_template_message(name, namespace, lang_code, processed_parameters)
    retry_template_send_after_sync if message_id.blank? && template_translation_missing_error?
  end

  def send_session_message
    message_id = channel.send_message(message.conversation.contact_inbox.source_id, message)
    message.update!(source_id: message_id) if message_id.present?
  end

  def template_params
    message.additional_attributes && message.additional_attributes['template_params']
  end

  def build_template_payload
    processor = Whatsapp::TemplateProcessorService.new(
      channel: channel,
      template_params: template_params,
      message: message
    )

    processor.call
  end

  def retry_template_send_after_sync
    sync_templates_for_template_refresh

    name, namespace, lang_code, processed_parameters = build_template_payload
    if name.blank?
      message.update!(status: :failed, external_error: TEMPLATE_NOT_FOUND_ERROR)
      return
    end

    if processed_parameters.nil?
      message.update!(status: :failed, external_error: TEMPLATE_TRANSLATION_NOT_FOUND_ERROR)
      return
    end

    message_id = deliver_template_message(name, namespace, lang_code, processed_parameters)
    if message_id.blank? && template_translation_missing_error?
      message.update!(status: :failed, external_error: TEMPLATE_TRANSLATION_NOT_FOUND_ERROR)
    end
  end

  def deliver_template_message(name, namespace, lang_code, processed_parameters)
    message_id = channel.send_template(message.conversation.contact_inbox.source_id, {
                                         name: name,
                                         namespace: namespace,
                                         lang_code: lang_code,
                                         parameters: processed_parameters
                                       }, message)
    message.update!(source_id: message_id, status: :sent, external_error: nil) if message_id.present?
    message_id
  end

  def sync_templates_for_template_refresh
    result = channel.sync_templates
    return unless result == false

    Rails.logger.warn("[WHATSAPP TEMPLATE SEND] Template sync returned false for inbox #{inbox.id}")
  rescue StandardError => e
    Rails.logger.error("[WHATSAPP TEMPLATE SEND] Failed to sync templates for inbox #{inbox.id}: #{e.message}")
  end

  def template_translation_missing_error?
    message.reload.external_error.to_s.downcase.include?('does not exist in the translation')
  end
end
