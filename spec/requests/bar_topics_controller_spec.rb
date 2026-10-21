# frozen_string_literal: true

require "rails_helper"

RSpec.describe IsbfPinning::BarTopicsController do
  fab!(:author, :user)
  fab!(:category)
  fab!(:topic) { Fabricate(:topic_with_op, category: category, user: author) }

  before do
    SiteSetting.isbf_pinning_enabled = true
    topic.update_pinned(true, true, 1.day.from_now.iso8601)
    topic.custom_fields[IsbfPinning::HOME_FIELD] = true
    topic.save_custom_fields
  end

  describe "#index" do
    it "returns real authors and native excerpts without changing pins or ordinary feed membership" do
      get "/isbf/pinning/topics.json"

      expect(response.status).to eq(200)
      result = response.parsed_body.fetch("topic_list").fetch("topics")
      expect(result.map { |entry| entry.fetch("id") }).to eq([topic.id])
      expect(result.first.fetch("isbf_pin_author")).to include(
        "id" => author.id,
        "username" => author.username,
      )
      expect(result.first.fetch("excerpt")).to be_present
      expect(topic.reload.pinned_globally).to eq(true)
      get "/latest.json"
      expect(
        response.parsed_body.fetch("topic_list").fetch("topics").map { |entry| entry.fetch("id") },
      ).to include(topic.id)
    end

    it "excludes expired, hidden and deleted posts, and private categories for visitors" do
      private_category = Fabricate(:private_category, group: Fabricate(:group))
      private_topic = Fabricate(:topic_with_op, category: private_category)
      private_topic.update_pinned(true, true, 1.day.from_now.iso8601)
      SiteSetting.isbf_pinning_bar_default_topic_id = private_topic.id
      topic.update_column(:pinned_until, 1.minute.ago)

      get "/isbf/pinning/topics.json"
      expect(response.parsed_body.fetch("topic_list").fetch("topics")).to eq([])
      expect(response.parsed_body.fetch("topic_list").fetch("default_topic_id")).to eq(0)

      topic.update_column(:pinned_until, 1.day.from_now)
      topic.first_post.update_column(:hidden, true)
      get "/isbf/pinning/topics.json"
      expect(response.parsed_body.fetch("topic_list").fetch("topics")).to eq([])
    end

    it "keeps scoped pins after personal clearing and preserves native legacy clearing" do
      sign_in(author)
      TopicUser.change(author.id, topic.id, cleared_pinned_at: 1.minute.from_now)
      legacy = Fabricate(:topic_with_op)
      legacy.update_pinned(true, true, 1.day.from_now.iso8601)
      TopicUser.change(author.id, legacy.id, cleared_pinned_at: 1.minute.from_now)

      get "/isbf/pinning/topics.json"
      expect(
        response.parsed_body.fetch("topic_list").fetch("topics").map { |entry| entry.fetch("id") },
      ).to eq([topic.id])
    end

    it "includes pins beyond the normal first page in the original pin order" do
      stub_const(TopicQuery, "DEFAULT_PER_PAGE_COUNT", 2) do
        others = 3.times.map { Fabricate(:topic_with_op) }
        others.each_with_index do |record, index|
          record.update_pinned(true, true, 1.day.from_now.iso8601)
          record.update_column(:pinned_at, (index + 1).hours.from_now)
        end

        get "/isbf/pinning/topics.json"
        expect(
          response
            .parsed_body
            .fetch("topic_list")
            .fetch("topics")
            .map { |entry| entry.fetch("id") },
        ).to eq(others.reverse.map(&:id) + [topic.id])
      end
    end
  end
end
