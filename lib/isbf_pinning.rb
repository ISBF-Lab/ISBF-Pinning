# frozen_string_literal: true

module IsbfPinning
  HOME_FIELD = "isbf_home_pin"
  REQUEST_KEY = :isbf_home_pin_request
  PIN_FIELDS = %w[pinned pinned_at pinned_globally pinned_until isbf_home_pin].freeze
  DEFAULT_DURATION = 72.hours

  def self.developer?(user)
    user && user[:admin] == true
  end

  def self.official_category_id
    id = if SiteSetting.respond_to?(:academy_official_category)
      SiteSetting.academy_official_category.to_i
    else
      SiteSetting.isbf_pinning_official_category_id.to_i
    end
    id if id.positive?
  end

  def self.new_actions?
    SiteSetting.isbf_pinning_enabled && SiteSetting.isbf_pinning_home_actions_enabled
  end

  def self.scoped?(topic)
    topic && topic.pinned_at.present? && topic.custom_fields[HOME_FIELD] == true
  end

  def self.active?(topic, now: Time.current)
    scoped?(topic) && topic.pinned_globally && topic.pinned_until.present? &&
      topic.pinned_until > now && published?(topic)
  end

  def self.home_visible?(topic)
    if defined?(IsbfMarketplace) && topic.category_id == IsbfMarketplace.category_id
      return false unless topic.custom_fields[IsbfMarketplace::HOME_FIELD] == true
    end
    %w[isbf_marketplace_home isbf_teamup_home].none? do |field|
      [false, "f", "false"].include?(topic.custom_fields[field])
    end
  end

  def self.published?(topic)
    return false unless topic && !topic.private_message? && topic.visible && topic.deleted_at.nil?
    return false unless home_visible?(topic)
    return false if topic.category&.topic_id == topic.id
    first = topic.first_post
    first && first.deleted_at.nil? && !first.user_deleted && !first.hidden
  end

  def self.eligible?(topic, guardian)
    published?(topic) && guardian.can_see?(topic)
  end

  def self.can_manage?(topic, guardian)
    developer?(guardian&.user) && new_actions? && eligible?(topic, guardian)
  end

  def self.metadata(topic, guardian)
    {
      can_manage: !!can_manage?(topic, guardian),
      scoped: !!scoped?(topic),
      active: !!active?(topic),
      pinned_at: topic.pinned_at&.iso8601,
      pinned_until: topic.pinned_until&.iso8601,
    }
  end

  def self.ensure_developer!(user)
    raise Discourse::InvalidAccess unless developer?(user)
  end

  def self.bool(value)
    return true if value == true || value == "true"
    return false if value == false || value == "false"
    raise Discourse::InvalidParameters.new(I18n.t("isbf_pinning.invalid"))
  end

  def self.deadline(value, now: Time.current)
    return now + DEFAULT_DURATION if value.nil?
    iso = value.is_a?(String) && value.match?(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(?::\d{2}(?:\.\d+)?)?(?:Z|[+-]\d{2}:\d{2})\z/)
    native = value.is_a?(String) && value.match?(/\A\d{4}-\d{2}-\d{2} \d{2}:\d{2} ?[+-]\d{2}:\d{2}\z/)
    unless (iso || native) && Date.valid_date?(*value[0, 10].split("-").map(&:to_i))
      raise Discourse::InvalidParameters.new(I18n.t("isbf_pinning.future_required"))
    end
    begin
      result = iso ? Time.iso8601(value) : Time.strptime(value.sub(/ (?=[+-]\d{2}:\d{2}\z)/, ""), "%Y-%m-%d %H:%M%z")
    rescue ArgumentError
      raise Discourse::InvalidParameters.new(I18n.t("isbf_pinning.future_required"))
    end
    raise Discourse::InvalidParameters.new(I18n.t("isbf_pinning.future_required")) unless result > now
    result
  end

  def self.pin_fields?(fields)
    return false unless fields.respond_to?(:key?)
    fields = fields.with_indifferent_access
    PIN_FIELDS.any? { |name| fields.key?(name) } ||
      %w[custom_fields topic_custom_fields meta_data].any? do |container|
        fields[container].respond_to?(:key?) && fields[container].key?(HOME_FIELD)
      end || pin_fields?(fields[:topic_opts])
  end

  def self.reject_side_channel!(fields, user)
    return unless pin_fields?(fields)
    return if user && user.id == Discourse.system_user.id
    ensure_developer!(user)
    raise Discourse::InvalidParameters.new(I18n.t("isbf_pinning.invalid"))
  end
end
