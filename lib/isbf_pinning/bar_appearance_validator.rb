# frozen_string_literal: true

module IsbfPinning
  class BarAppearanceValidator
    KEYS = %w[fill border border_width opacity x y fit overflow].freeze

    def initialize(opts = {})
    end

    def valid_value?(value)
      return false unless value.is_a?(String) && value.bytesize <= 2048
      config = JSON.parse(value)
      return false unless config.is_a?(Hash) && config.keys.sort == %w[dark light]
      config.values.all? do |mode|
        mode.is_a?(Hash) && mode.keys.sort == KEYS.sort &&
          %w[fill border].all? do |key|
            mode[key].is_a?(String) && mode[key].match?(/\A#[\da-f]{8}\z/i)
          end && number_in?(mode["border_width"], 0, 4) && (mode["border_width"] * 2) % 1 == 0 &&
          number_in?(mode["opacity"], 0, 1) && number_in?(mode["x"], 0, 100) &&
          number_in?(mode["y"], -500, 500) && %w[contain cover].include?(mode["fit"]) &&
          [true, false].include?(mode["overflow"])
      end
    rescue JSON::ParserError
      false
    end

    def error_message
      I18n.t("isbf_pinning.invalid_appearance")
    end

    private

    def number_in?(value, minimum, maximum)
      value.is_a?(Numeric) && value.finite? && value.between?(minimum, maximum)
    end
  end
end
