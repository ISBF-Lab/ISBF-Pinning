# frozen_string_literal: true

module IsbfPinning
  def self.scope_sql
    <<~SQL.squish
      EXISTS (SELECT 1 FROM topic_custom_fields AS home_pin
        WHERE home_pin.topic_id = topics.id AND home_pin.name = '#{HOME_FIELD}'
          AND home_pin.value = 't')
    SQL
  end

  def self.active_sql
    <<~SQL.squish
      (#{scope_sql} AND topics.pinned_globally AND topics.pinned_at IS NOT NULL
        AND topics.pinned_until > #{Topic.connection.quote(Time.current)} AND topics.visible
        AND NOT EXISTS (SELECT 1 FROM categories AS home_pin_category
          WHERE home_pin_category.topic_id = topics.id)
        AND EXISTS (SELECT 1 FROM posts AS home_pin_post
          WHERE home_pin_post.topic_id = topics.id AND home_pin_post.post_number = 1
            AND home_pin_post.deleted_at IS NULL AND NOT home_pin_post.hidden
            AND NOT home_pin_post.user_deleted))
    SQL
  end

  def self.legacy_sql(query, options)
    category_id = query.options[:category_id] || options[:category_id]
    category = category_id ? "topics.category_id = #{category_id.to_i}" : "topics.pinned_globally"
    clear = query.user ? "AND (topics.pinned_at > tu.cleared_pinned_at OR tu.cleared_pinned_at IS NULL)" : ""
    "(NOT (#{scope_sql}) AND #{category} AND topics.pinned_at IS NOT NULL #{clear})"
  end

  def self.ordered_home_scope(topics, query, options)
    return topics unless topics.is_a?(ActiveRecord::Relation)
    active = active_sql
    legacy = legacy_sql(query, options)
    if defined?(IsbfMarketplace) && IsbfMarketplace.respond_to?(:home_scope)
      topics = IsbfMarketplace.home_scope(topics)
    end
    topics = IsbfTeamup.home_scope(topics) if defined?(IsbfTeamup)
    topics.reorder(Arel.sql(<<~SQL.squish))
      CASE WHEN #{active} OR #{legacy} THEN 0 ELSE 1 END,
      CASE WHEN #{active} OR #{legacy} THEN topics.pinned_at END DESC,
      topics.created_at DESC, topics.id DESC
    SQL
  end

  module HomeList
    attr_accessor :isbf_home_pinning_scope
  end

  module NativeQueries
    def isbf_home_pin_query?
      @isbf_home_pin_query == true
    end

    def create_list(filter, options = {}, topics = nil, &block)
      previous = @isbf_home_pin_query
      merged = options.merge(@options)
      category_id = get_category_id(merged[:category]) || merged[:category_id]
      category_id = category_id.to_i if category_id
      official_id = IsbfPinning.official_category_id
      query_orders = merged[:q].to_s.scan(/(?:\A|\s)order:([^\s]+)/).flatten
      native_order = merged[:order].blank? || %w[activity default].include?(merged[:order])
      native_order &&= query_orders.all? { |order| %w[activity default].include?(order) }
      ordinary = native_order && merged[:ascending].to_s != "true" &&
        merged[:tags].blank? && merged[:filtered_to_user].blank?
      @isbf_home_pin_query = ordinary && (
        (filter == :latest && merged[:q].blank? &&
          (category_id.nil? || (official_id && category_id == official_id))) ||
        (filter == :filter && official_id &&
          merged[:q].to_s.match?(/(?:\A|\s)isbf-official:#{official_id}(?=\s|\z)/))
      )
      result = super
      result.isbf_home_pinning_scope = isbf_home_pin_query?
      result
    ensure
      @isbf_home_pin_query = previous
    end

    def list_category_topic_ids(category)
      query = default_results(category: category.id)
      clause = "topics.category_id = #{category.id.to_i} AND topics.pinned_at IS NOT NULL AND NOT (#{IsbfPinning.scope_sql})"
      pinned = query.where(clause).limit(nil).reorder(pinned_at: :desc).pluck(:id)
      ordinary = query.where("NOT (#{clause})").pluck(:id)
      pinned + ordinary
    end

    def prioritize_pinned_topics(topics, options)
      return topics if isbf_home_pin_query?
      pinned_clause = IsbfPinning.legacy_sql(self, options)
      unpinned_topics = topics.where("NOT (#{pinned_clause})")
      pinned_topics = topics.dup.offset(nil).where(pinned_clause).reorder(pinned_at: :desc)
      per_page = options[:per_page]&.to_i || per_page_setting
      limit = per_page unless options[:limit] == false
      page = options[:page].to_i
      if page == 0
        limit ? (pinned_topics + unpinned_topics)[0...limit] : pinned_topics + unpinned_topics
      else
        offset = [page * per_page - pinned_topics.length, 0].max
        unpinned_topics.offset(offset).to_a
      end
    end
  end
end
