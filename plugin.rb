# frozen_string_literal: true

# name: isbf-pinning
# about: Developer-only timed pins scoped to native ISBF home feeds.
# version: 0.1.0
# authors: ISBF Lab
# url: https://github.com/ISBF-Lab/ISBF-Pinning
# required_version: 3.4.0

register_svg_icon "thumbtack"

enabled_site_setting :isbf_pinning_enabled

after_initialize do
  require_relative "lib/isbf_pinning"
  require_relative "lib/isbf_pinning/native_queries"
  require_relative "lib/isbf_pinning/native_mutations"

  register_topic_custom_field_type(IsbfPinning::HOME_FIELD, :boolean)
  add_preloaded_topic_list_custom_field(IsbfPinning::HOME_FIELD)
  add_preloaded_topic_list_custom_field("isbf_marketplace_home")
  add_preloaded_topic_list_custom_field("isbf_teamup_home")

  add_to_serializer(:site, :isbf_pinning) do
    {
      version: 1,
      enabled: SiteSetting.isbf_pinning_enabled,
      home_actions_enabled: SiteSetting.isbf_pinning_home_actions_enabled,
      official_category_id: IsbfPinning.official_category_id,
    }
  end
  %i[topic_list_item topic_view].each do |serializer|
    add_to_serializer(serializer, :isbf_home_pinning) do
      topic = object.respond_to?(:topic) ? object.topic : object
      IsbfPinning.metadata(topic, scope)
    end
  end

  Guardian.prepend(IsbfPinning::PinGuardian)
  TopicsController.prepend(IsbfPinning::StatusController)
  PostsController.prepend(IsbfPinning::PostController)
  TopicStatusUpdater.prepend(IsbfPinning::StatusMutation)
  TopicsBulkAction.prepend(IsbfPinning::BulkMutation)
  TopicCreator.prepend(IsbfPinning::TopicCreation)
  PostRevisor.prepend(IsbfPinning::PostRevision)
  Topic.prepend(IsbfPinning::NativePinCleanup)
  Jobs::UnpinTopic.prepend(IsbfPinning::Expiry)
  TopicQuery.prepend(IsbfPinning::NativeQueries)
  TopicList.prepend(IsbfPinning::HomeList)
  add_to_serializer(:topic_list, :isbf_home_pinning_scope) do
    object.isbf_home_pinning_scope == true
  end

  register_modifier(:topic_query_create_list_topics) do |topics, options, query|
    if query.isbf_home_pin_query?
      IsbfPinning.ordered_home_scope(topics, query, options)
    else
      topics
    end
  end
end
