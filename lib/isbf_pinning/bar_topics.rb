# frozen_string_literal: true

module IsbfPinning
  class BarTopics
    def self.list(user)
      query = TopicQuery.new(user, limit: false)
      topics = query.latest_results(limit: false).includes(:user, :first_post)
      topics = topics.where("#{IsbfPinning.active_sql} OR #{IsbfPinning.legacy_sql(query, {})}")
      topics = topics.where("topics.pinned_until IS NULL OR topics.pinned_until > ?", Time.current)
      topics = topics.where(visible: true, archetype: Archetype.default)
      topics = topics.where(<<~SQL.squish)
        NOT EXISTS (SELECT 1 FROM categories WHERE categories.topic_id = topics.id)
        AND EXISTS (SELECT 1 FROM posts WHERE posts.topic_id = topics.id AND posts.post_number = 1
          AND posts.deleted_at IS NULL AND NOT posts.hidden AND NOT posts.user_deleted)
      SQL
      query.create_list(:latest, { limit: false, isbf_pinning_bar: true }, topics)
    end
  end
end
