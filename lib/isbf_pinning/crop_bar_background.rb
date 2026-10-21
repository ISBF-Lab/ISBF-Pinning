# frozen_string_literal: true

module IsbfPinning
  class CropBarBackground
    include Service::Base

    policy :can_edit_background

    params do
      attribute :upload_url, :string
      attribute :setting_name, :string
      attribute :crop_left, :float
      attribute :crop_width, :float

      validates :upload_url, presence: true, length: { maximum: 2048 }
      validates :setting_name, inclusion: { in: BarBackgroundValidator::SETTINGS }
      validates :crop_left, numericality: { greater_than_or_equal_to: -4, less_than: 1 }
      validates :crop_width, numericality: { greater_than: 0, less_than_or_equal_to: 4 }
      validate :visible_image

      def visible_image
        return unless crop_left&.finite? && crop_width&.finite?
        errors.add(:crop_width, :invalid) if crop_left + crop_width <= 0
      end
    end

    model :source_upload
    policy :valid_background
    model :cropped_upload, :create_cropped_upload

    private

    def can_edit_background(guardian:)
      guardian.is_admin?
    end

    def fetch_source_upload(params:)
      Upload.get_from_url(params.upload_url)
    end

    def valid_background(source_upload:)
      BarBackgroundValidator.new.valid_value?(source_upload.id.to_s)
    end

    def create_cropped_upload(params:, source_upload:, guardian:)
      BarImageCrop.create(
        source_upload:,
        crop_left: params.crop_left,
        crop_width: params.crop_width,
        user: guardian.user,
        setting_name: params.setting_name,
      )
    end
  end
end
