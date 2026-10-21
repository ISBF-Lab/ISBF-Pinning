# frozen_string_literal: true

require "rails_helper"

RSpec.describe UploadsController do
  describe "#create" do
    it "uses native storage for developer background uploads" do
      sign_in(Fabricate(:admin))
      post "/uploads.json",
           params: {
             file: Rack::Test::UploadedFile.new(file_from_fixtures("logo.png")),
             upload_type: "site_setting",
             for_site_setting: true,
             site_setting_name: "isbf_pinning_bar_dark_desktop_image",
           }
      expect(response.status).to eq(200)
      expect(Upload.find(response.parsed_body.fetch("id")).width).to be_positive
    end

    it "rejects member and moderator upload requests before processing the file" do
      [Fabricate(:user), Fabricate(:moderator)].each do |actor|
        sign_in(actor)
        expect do
          post "/uploads.json",
               params: {
                 file: Rack::Test::UploadedFile.new(file_from_fixtures("logo.png")),
                 upload_type: "site_setting",
                 for_site_setting: true,
                 site_setting_name: "isbf_pinning_bar_dark_desktop_image",
               }
        end.not_to change(Upload, :count)
        expect(response.status).to eq(403)
      end
    end
  end
end
