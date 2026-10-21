# frozen_string_literal: true

require "rails_helper"

RSpec.describe IsbfPinning::BarBackgroundCropsController do
  describe "#create" do
    subject(:perform_request) { post "/isbf/pinning/backgrounds/crop.json", params: }

    fab!(:actor, :admin)
    fab!(:source_upload) { Fabricate(:image_upload, width: 8, height: 4, color: "blue").reload }

    let(:params) do
      {
        upload_url: source_upload.url,
        setting_name: "isbf_pinning_bar_dark_desktop_image",
        crop_left: 0.25,
        crop_width: 0.5,
      }
    end

    before do
      SiteSetting.isbf_pinning_enabled = true
      sign_in(actor) if actor
    end

    it "returns the created upload resource and leaves site settings pending" do
      original_background = SiteSetting.isbf_pinning_bar_dark_desktop_image
      original_appearance = SiteSetting.isbf_pinning_bar_appearance

      expect { perform_request }.to change(Upload, :count).by(1)

      expect(response.status).to eq(201)
      resource = response.parsed_body
      cropped_upload = Upload.find(resource.fetch("id"))
      expect(resource).to include(
        "id" => cropped_upload.id,
        "url" => cropped_upload.url,
        "width" => 4,
        "height" => 4,
        "extension" => "png",
      )
      expect(cropped_upload.id).not_to eq(source_upload.id)
      expect(cropped_upload.user_id).to eq(actor.id)
      expect(File.file?(Discourse.store.path_for(cropped_upload))).to eq(true)
      expect(SiteSetting.isbf_pinning_bar_dark_desktop_image).to eq(original_background)
      expect(SiteSetting.isbf_pinning_bar_appearance).to eq(original_appearance)
    end

    context "without a signed-in user" do
      fab!(:actor) { nil }

      it "requires authentication without creating an upload" do
        expect { perform_request }.not_to change(Upload, :count)
        expect(response.status).to eq(403)
      end
    end

    context "when the caller is a member" do
      fab!(:actor, :user)

      it "returns forbidden without creating an upload" do
        expect { perform_request }.not_to change(Upload, :count)
        expect(response.status).to eq(403)
      end
    end

    context "when the caller is a moderator" do
      fab!(:actor, :moderator)

      it "returns forbidden without creating an upload" do
        expect { perform_request }.not_to change(Upload, :count)
        expect(response.status).to eq(403)
      end
    end

    context "with invalid crop geometry" do
      let(:params) { super().merge(crop_width: 0) }

      it "returns bad request without creating an upload" do
        expect { perform_request }.not_to change(Upload, :count)
        expect(response.status).to eq(400)
      end
    end

    context "with a setting outside the pinned backgrounds" do
      let(:params) { super().merge(setting_name: "logo") }

      it "returns bad request without creating an upload" do
        expect { perform_request }.not_to change(Upload, :count)
        expect(response.status).to eq(400)
      end
    end

    context "when the source upload is missing" do
      let(:params) do
        super().merge(upload_url: "/uploads/default/original/1X/#{SecureRandom.hex(20)}.png")
      end

      it "returns not found without creating an upload" do
        expect { perform_request }.not_to change(Upload, :count)
        expect(response.status).to eq(404)
      end
    end

    context "with an external image URL" do
      let(:params) { super().merge(upload_url: "https://untrusted.example/background.png") }

      it "returns not found without downloading or creating an upload" do
        expect { perform_request }.not_to change(Upload, :count)
        expect(response.status).to eq(404)
      end
    end

    context "with a private source image" do
      before { source_upload.update!(secure: true) }

      it "returns an image error without creating a public copy" do
        expect { perform_request }.not_to change(Upload, :count)
        expect(response.status).to eq(422)
        expect(response.parsed_body.fetch("errors")).to be_present
      end
    end

    context "with a non-image source upload" do
      fab!(:source_upload) do
        upload = Fabricate(:upload)
        upload.update_columns(
          original_filename: "notes.txt",
          extension: "txt",
          width: nil,
          height: nil,
        )
        upload
      end

      it "returns an image error without creating an upload" do
        expect { perform_request }.not_to change(Upload, :count)
        expect(response.status).to eq(422)
        expect(response.parsed_body.fetch("errors")).to be_present
      end
    end

    context "when the source exceeds the background byte limit" do
      before { source_upload.update!(filesize: 6.megabytes) }

      it "returns an image error without creating an upload" do
        expect { perform_request }.not_to change(Upload, :count)
        expect(response.status).to eq(422)
        expect(response.parsed_body.fetch("errors")).to be_present
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

      it "returns a processing error without creating an upload or changing settings" do
        original_background = SiteSetting.isbf_pinning_bar_dark_desktop_image

        expect { perform_request }.not_to change(Upload, :count)
        expect(response.status).to eq(422)
        expect(response.parsed_body.fetch("errors")).to be_present
        expect(SiteSetting.isbf_pinning_bar_dark_desktop_image).to eq(original_background)
      end
    end
  end
end
