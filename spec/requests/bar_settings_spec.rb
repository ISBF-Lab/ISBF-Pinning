# frozen_string_literal: true

require "rails_helper"

RSpec.describe Admin::SiteSettingsController do
  fab!(:admin)

  describe "#update" do
    it "persists independent modes through the existing bulk settings API" do
      sign_in(admin)
      appearance = JSON.parse(SiteSetting.isbf_pinning_bar_appearance)
      appearance["light"]["fill"] = "#ffffff00"
      appearance["dark"]["border_width"] = 0.5

      put "/admin/site_settings/bulk_update.json",
          params: {
            settings: {
              isbf_pinning_bar_appearance: {
                value: appearance.to_json,
              },
              isbf_pinning_bar_default_topic_id: {
                value: 42,
              },
            },
          }

      expect(response.status).to eq(204)
      expect(JSON.parse(SiteSetting.isbf_pinning_bar_appearance)).to eq(appearance)
      expect(SiteSetting.isbf_pinning_bar_default_topic_id).to eq(42)
    end

    it "rejects member and moderator direct writes" do
      [Fabricate(:user), Fabricate(:moderator)].each do |actor|
        sign_in(actor)
        put "/admin/site_settings/isbf_pinning_bar_default_topic_id.json",
            params: {
              isbf_pinning_bar_default_topic_id: 42,
            }
        expect(response.status).to be_in([403, 404])
        expect(SiteSetting.isbf_pinning_bar_default_topic_id).to eq(0)
      end
    end

    it "rejects CSS injection, invalid numeric values and editor-only flags" do
      sign_in(admin)
      initial = SiteSetting.isbf_pinning_bar_appearance
      [
        { "fill" => "red;position:fixed" },
        { "border_width" => 4.5 },
        { "guides" => true },
      ].each do |changes|
        config = JSON.parse(initial)
        config["dark"].merge!(changes)
        put "/admin/site_settings/isbf_pinning_bar_appearance.json",
            params: {
              isbf_pinning_bar_appearance: config.to_json,
            }
        expect(response.status).to eq(422)
        expect(SiteSetting.isbf_pinning_bar_appearance).to eq(initial)
      end
    end
  end
end
