# frozen_string_literal: true

require "rails_helper"

RSpec.describe IsbfPinning::BarBackgroundValidator do
  describe "#valid_value?" do
    it "accepts a public image and clearing the image" do
      upload =
        Fabricate(
          :upload,
          original_filename: "decoration.png",
          width: 1600,
          height: 400,
          filesize: 1024,
          secure: false,
        )
      validator = described_class.new(name: :isbf_pinning_bar_light_desktop_image)
      expect(validator.valid_value?(upload.id)).to eq(true)
      expect(validator.valid_value?("")).to eq(true)
    end

    it "rejects private images, SVG, excessive dimensions and large files" do
      upload =
        Fabricate(
          :upload,
          original_filename: "decoration.png",
          width: 1600,
          height: 400,
          filesize: 1024,
          secure: false,
        )
      validator = described_class.new(name: :isbf_pinning_bar_light_desktop_image)
      [
        { secure: true },
        { original_filename: "decoration.svg" },
        { width: 9000 },
        { width: 8000, height: 4000 },
        { filesize: 6.megabytes },
      ].each do |attributes|
        upload.update_columns(
          {
            secure: false,
            original_filename: "decoration.png",
            width: 1600,
            height: 400,
            filesize: 1024,
          }.merge(attributes),
        )
        expect(validator.valid_value?(upload.id)).to eq(false)
      end
    end
  end
end
