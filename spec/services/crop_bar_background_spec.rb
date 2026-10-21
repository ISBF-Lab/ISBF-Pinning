# frozen_string_literal: true

require "rails_helper"
require "chunky_png"

RSpec.describe IsbfPinning::CropBarBackground do
  describe described_class::Contract, type: :model do
    subject(:contract) do
      described_class.new(
        upload_url: "/uploads/default/original/1X/background.png",
        setting_name: "isbf_pinning_bar_dark_desktop_image",
        crop_left: 0,
        crop_width: 1,
      )
    end

    it { is_expected.to validate_presence_of(:upload_url) }
    it { is_expected.to validate_length_of(:upload_url).is_at_most(2048) }

    it do
      is_expected.to validate_inclusion_of(:setting_name).in_array(
        IsbfPinning::BarBackgroundValidator::SETTINGS,
      )
    end

    it "allows image positions that intersect the crop window" do
      contract.crop_width = 4

      expect(contract).to allow_values(-3.99, -0.5, 0, 0.99).for(:crop_left)
    end

    it do
      is_expected.not_to allow_values(nil, -4.01, 1, Float::INFINITY, Float::NAN).for(:crop_left)
    end

    it { is_expected.to allow_values(0.01, 0.25, 1, 4).for(:crop_width) }

    it do
      is_expected.not_to allow_values(nil, 0, -0.01, 4.01, Float::INFINITY, Float::NAN).for(
        :crop_width,
      )
    end

    it "requires the crop window to include part of the original image" do
      contract.crop_left = -0.5

      expect(contract).not_to allow_values(0.1, 0.5).for(:crop_width)
      expect(contract).to allow_values(0.51, 1, 4).for(:crop_width)
    end
  end

  describe ".call" do
    subject(:result) { described_class.call(params:, **dependencies) }

    fab!(:acting_user, :admin)
    fab!(:source_upload) do
      Tempfile.create(%w[pinning-background-source .png]) do |file|
        image = ChunkyPNG::Image.new(8, 4, ChunkyPNG::Color.rgb(255, 0, 0))
        4.upto(7) do |column|
          4.times { |row| image[column, row] = ChunkyPNG::Color.rgb(0, 0, 255) }
        end
        image.save(file.path)

        upload =
          Fabricate(
            :upload,
            user: acting_user,
            original_filename: "pinning-background-source.png",
            width: 8,
            height: 4,
            filesize: File.size(file.path),
            sha1: Upload.generate_digest(file.path),
          )
        upload.update!(url: Discourse.store.store_upload(file, upload))
        upload
      end
    end

    let(:params) do
      { upload_url:, setting_name: "isbf_pinning_bar_dark_desktop_image", crop_left:, crop_width: }
    end
    let(:dependencies) { { guardian: acting_user&.guardian || Guardian.new } }
    let(:upload_url) { source_upload.url }
    let(:crop_left) { 0.25 }
    let(:crop_width) { 0.5 }

    before { SiteSetting.isbf_pinning_enabled = true }

    context "without a signed-in user" do
      fab!(:acting_user) { nil }

      it "rejects the caller without creating an upload" do
        expect { result }.not_to change(Upload, :count)
        expect(result).to fail_a_policy(:can_edit_background)
      end
    end

    context "when the caller is a member with invalid crop parameters" do
      fab!(:acting_user, :user)
      let(:crop_width) { 0 }

      it "enforces administrator access before validating the crop" do
        expect { result }.not_to change(Upload, :count)
        expect(result).to fail_a_policy(:can_edit_background)
      end
    end

    context "when the caller is a moderator" do
      fab!(:acting_user, :moderator)

      it "rejects the caller without creating an upload" do
        expect { result }.not_to change(Upload, :count)
        expect(result).to fail_a_policy(:can_edit_background)
      end
    end

    context "with invalid crop parameters" do
      let(:crop_width) { 0 }

      it "halts at the contract without creating an upload" do
        expect { result }.not_to change(Upload, :count)
        expect(result).to fail_a_contract
      end
    end

    context "when the source upload is missing" do
      let(:upload_url) { "/uploads/default/original/1X/#{SecureRandom.hex(20)}.png" }

      it "returns a missing source without creating an upload" do
        expect { result }.not_to change(Upload, :count)
        expect(result).to fail_to_find_a_model(:source_upload)
      end
    end

    context "with a private source upload" do
      before { source_upload.update!(secure: true) }

      it "rejects the private background without creating a public copy" do
        expect { result }.not_to change(Upload, :count)
        expect(result).to fail_a_policy(:valid_background)
      end
    end

    context "when the crop exceeds the maximum edge length" do
      fab!(:source_upload) { Fabricate(:image_upload, width: 3000, height: 2).reload }
      let(:crop_left) { 0 }
      let(:crop_width) { 3 }

      it "rejects the output without creating an upload" do
        expect { result }.not_to change(Upload, :count)
        expect(result).to fail_to_find_a_model(:cropped_upload)
      end
    end

    context "when the crop exceeds the maximum pixel count" do
      fab!(:source_upload) { Fabricate(:image_upload, width: 2048, height: 2048).reload }
      let(:crop_left) { 0 }
      let(:crop_width) { 4 }

      it "rejects the output without creating an upload" do
        expect { result }.not_to change(Upload, :count)
        expect(result).to fail_to_find_a_model(:cropped_upload)
      end
    end

    context "when the rendered PNG exceeds the background byte limit" do
      fab!(:source_upload) do
        file = file_from_fixtures("logo.jpg")
        width, height = FastImage.size(file.path)
        upload =
          Fabricate(
            :upload,
            user: acting_user,
            original_filename: "logo.jpg",
            extension: "jpg",
            width:,
            height:,
            filesize: file.size,
            sha1: Upload.generate_digest(file.path),
          )
        upload.update!(url: Discourse.store.store_upload(file, upload))
        upload
      end
      let(:crop_left) { 0 }
      let(:crop_width) { 1 }

      it "rejects the encoded output while accepting the smaller source JPEG" do
        stub_const(IsbfPinning::BarBackgroundValidator, :MAX_BYTES, source_upload.filesize) do
          expect { result }.not_to change(Upload, :count)
          expect(result).to fail_to_find_a_model(:cropped_upload)
        end
      end
    end

    context "when the image data is truncated after its valid header" do
      around do |example|
        path = Discourse.store.path_for(source_upload)
        original = File.binread(path)
        File.binwrite(path, original.byteslice(0, 33))
        example.run
      ensure
        File.binwrite(path, original) if path && original
      end

      it "returns the processing failure without creating an upload" do
        expect { result }.not_to change(Upload, :count)
        expect(result).to fail_to_find_a_model(:cropped_upload)
      end
    end

    context "when the source image and crop are valid" do
      it "creates a native upload containing only the selected horizontal pixels" do
        original_path = Discourse.store.path_for(source_upload)
        original_bytes = File.binread(original_path)
        original_image = ChunkyPNG::Image.from_file(original_path)
        original_attributes = source_upload.attributes
        original_setting = SiteSetting.isbf_pinning_bar_dark_desktop_image

        expect { result }.to change(Upload, :count).by(1)
        expect(result).to run_successfully

        cropped_upload = result.cropped_upload
        expect(cropped_upload).to be_persisted
        expect(cropped_upload).to have_attributes(
          width: 4,
          height: 4,
          extension: "png",
          user_id: acting_user.id,
        )
        image = ChunkyPNG::Image.from_file(Discourse.store.path_for(cropped_upload))
        expect(image.pixels).to eq(original_image.crop(2, 0, 4, 4).pixels)
        expect(source_upload.reload.attributes).to eq(original_attributes)
        expect(File.binread(original_path)).to eq(original_bytes)
        expect(SiteSetting.isbf_pinning_bar_dark_desktop_image).to eq(original_setting)
      end
    end

    context "when the crop window extends past the left image edge" do
      let(:crop_left) { -0.25 }
      let(:crop_width) { 1 }

      it "adds transparent pixels on the left and discards the right overflow" do
        expect(result).to run_successfully

        image = ChunkyPNG::Image.from_file(Discourse.store.path_for(result.cropped_upload))
        expect([image.width, image.height]).to eq([8, 4])
        expect([image[2, 0], image[5, 0], image[6, 0], image[7, 0]]).to eq(
          [
            ChunkyPNG::Color.rgb(255, 0, 0),
            ChunkyPNG::Color.rgb(255, 0, 0),
            ChunkyPNG::Color.rgb(0, 0, 255),
            ChunkyPNG::Color.rgb(0, 0, 255),
          ],
        )
        expect([image[0, 0], image[1, 3]].map { |pixel| ChunkyPNG::Color.a(pixel) }).to eq([0, 0])
      end
    end

    context "when the crop window extends past the right image edge" do
      let(:crop_left) { 0.75 }
      let(:crop_width) { 0.5 }

      it "keeps the intersecting pixels and fills the remaining width with transparency" do
        expect(result).to run_successfully

        image = ChunkyPNG::Image.from_file(Discourse.store.path_for(result.cropped_upload))
        expect([image.width, image.height]).to eq([4, 4])
        expect([image[0, 0], image[1, 3]]).to eq(
          [ChunkyPNG::Color.rgb(0, 0, 255), ChunkyPNG::Color.rgb(0, 0, 255)],
        )
        expect([image[2, 0], image[3, 3]].map { |pixel| ChunkyPNG::Color.a(pixel) }).to eq([0, 0])
      end
    end

    context "when a narrow crop rounds to a single pixel" do
      let(:crop_width) { 0.01 }

      it "preserves the source height and the selected column" do
        expect(result).to run_successfully

        image = ChunkyPNG::Image.from_file(Discourse.store.path_for(result.cropped_upload))
        expect([image.width, image.height]).to eq([1, 4])
        expect(image.pixels).to eq([ChunkyPNG::Color.rgb(255, 0, 0)] * 4)
      end
    end
  end
end
