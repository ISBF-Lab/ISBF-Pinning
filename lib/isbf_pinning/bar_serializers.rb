# frozen_string_literal: true

module IsbfPinning
  class BarTopicSerializer < ::TopicListItemSerializer
    attributes :isbf_home_pinning
    has_one :isbf_pin_author, serializer: BasicUserSerializer, embed: :objects

    def isbf_home_pinning
      IsbfPinning.metadata(object, scope)
    end

    def include_excerpt?
      true
    end

    def excerpt
      super.presence ||
        PrettyText.excerpt(
          object.first_post&.cooked,
          SiteSetting.topic_excerpt_maxlength,
          strip_links: true,
          strip_images: true,
        )
    end

    def isbf_pin_author
      object.user
    end
  end

  class BarListSerializer < ::TopicListSerializer
    attributes :default_topic_id
    has_many :topics, serializer: BarTopicSerializer, embed: :objects

    def default_topic_id
      configured = SiteSetting.isbf_pinning_bar_default_topic_id
      object.topics.any? { |topic| topic.id == configured } ? configured : 0
    end
  end
end
