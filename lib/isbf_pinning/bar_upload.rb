# frozen_string_literal: true

module IsbfPinning
  module BarUploadController
    def create
      if params[:for_site_setting].to_s == "true" &&
           BarBackgroundValidator::SETTINGS.include?(params[:site_setting_name].to_s)
        IsbfPinning.ensure_developer!(current_user)
      end
      super
    end
  end

  module BarSettingsController
    def update
      names =
        (
          if params[:id].to_s == "bulk_update" && params[:settings].respond_to?(:keys)
            params[:settings].keys
          else
            [params[:id]]
          end
        )
      if names.any? { |name| name.to_s.start_with?("isbf_pinning_bar_") }
        IsbfPinning.ensure_developer!(current_user)
      end
      super
    end
  end

  module BarUpload
    def create_for(user_id)
      if @opts[:for_site_setting] &&
           BarBackgroundValidator::SETTINGS.include?(@opts[:site_setting_name].to_s)
        IsbfPinning.ensure_developer!(User.find_by(id: user_id))
        image = FastImage.new(@file)
        valid =
          filesize <= BarBackgroundValidator::MAX_BYTES && %i[png webp jpeg].include?(image.type) &&
            BarBackgroundValidator.valid_size?(*(image.size || [0, 0]))
        @file.rewind
        unless valid
          @upload.errors.add(:base, I18n.t("isbf_pinning.invalid_background"))
          return @upload
        end
      end
      super
    end
  end
end
