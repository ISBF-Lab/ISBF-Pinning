# frozen_string_literal: true

module IsbfPinning
  class BarImageCrop
    def self.create(source_upload:, crop_left:, crop_width:, user:, setting_name:)
      width = [(source_upload.width * crop_width).round, 1].max
      height = source_upload.height
      return unless BarBackgroundValidator.valid_size?(width, height)

      downloaded = nil
      source_path = Discourse.store.path_for(source_upload)
      unless source_path && File.file?(source_path)
        downloaded =
          Discourse.store.download(
            source_upload,
            max_file_size_kb: BarBackgroundValidator::MAX_BYTES,
          )
        source_path = downloaded&.path
      end
      return unless source_path && File.size(source_path) <= BarBackgroundValidator::MAX_BYTES

      image = FastImage.new(source_path)
      unless %i[png jpeg webp].include?(image.type) && image.size == [source_upload.width, height]
        return
      end

      Tempfile.create(%w[isbf-pinning-crop .png]) do |output|
        ImageMagick.magick(
          "-size",
          "#{width}x#{height}",
          "xc:none",
          "#{source_path}[0]",
          "-geometry",
          format("%+d+0", -(source_upload.width * crop_left).round),
          "-compose",
          "Over",
          "-composite",
          "-strip",
          "PNG:#{output.path}",
          operation: :isbf_pinning_background_crop,
          read: [source_path],
          write: [output.path],
          timeout: 15,
        )
        next if File.size(output.path) > BarBackgroundValidator::MAX_BYTES

        output.rewind
        UploadCreator.new(
          output,
          "pinned-bar-background.png",
          for_site_setting: true,
          site_setting_name: setting_name,
        ).create_for(user.id)
      end
    ensure
      downloaded&.close
    end
  end
end
