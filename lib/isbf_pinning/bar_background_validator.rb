# frozen_string_literal: true

require "validators/upload_setting_validator"

module IsbfPinning
  class BarBackgroundValidator < UploadSettingValidator
    MAX_BYTES = 5.megabytes
    MAX_EDGE = 8192
    MAX_PIXELS = 16_000_000
    SETTINGS =
      %w[light dark]
        .product(%w[desktop mobile])
        .map { |mode, device| "isbf_pinning_bar_#{mode}_#{device}_image" }
        .freeze

    def valid_value?(value)
      return false unless super
      return true if value.blank?
      upload = Upload.find_by(id: value.to_i)
      upload && !upload.secure? &&
        %w[.png .webp .jpg .jpeg].include?(File.extname(upload.original_filename).downcase) &&
        upload.filesize <= MAX_BYTES && self.class.valid_size?(upload.width, upload.height)
    end

    def self.valid_size?(width, height)
      width.is_a?(Numeric) && height.is_a?(Numeric) && width.positive? && height.positive? &&
        width <= MAX_EDGE && height <= MAX_EDGE && width * height <= MAX_PIXELS
    end

    def error_message
      I18n.t("isbf_pinning.invalid_background")
    end
  end
end
