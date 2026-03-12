# frozen_string_literal: true

module CustomExceptions::Whatsapp
  class TemplateSyncError < CustomExceptions::Base
    def message
      @data.is_a?(String) ? @data : @data[:message]
    end
  end
end
