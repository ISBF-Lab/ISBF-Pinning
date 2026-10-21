# frozen_string_literal: true

# name: isbf-pinning
# about: Native ISBF home pins with a collapsible bar and developer appearance settings.
# version: 0.2.1
# authors: ISBF Lab
# url: https://github.com/ISBF-Lab/ISBF-Pinning
# required_version: 3.4.0

require_relative "lib/isbf_pinning/bar_appearance_validator"
require_relative "lib/isbf_pinning/bar_background_validator"

register_svg_icon "thumbtack"
register_svg_icon "chevron-down"
register_asset "stylesheets/common/pinned-bar.scss"
register_asset "stylesheets/admin/pinned-bar-editor.scss", :admin

enabled_site_setting :isbf_pinning_enabled

after_initialize do
  require_relative "lib/isbf_pinning"
  require_relative "lib/isbf_pinning/native_queries"
  require_relative "lib/isbf_pinning/native_mutations"
  require_relative "lib/isbf_pinning/bar_topics"
  require_relative "lib/isbf_pinning/bar_upload"
  require_relative "lib/isbf_pinning/bar_serializers"

  module ::IsbfPinning
    class Engine < ::Rails::Engine
      engine_name "isbf-pinning"
      isolate_namespace IsbfPinning
    end

    class BarTopicsController < ::ApplicationController
      requires_plugin "isbf-pinning"

      def index
        raise Discourse::NotFound unless SiteSetting.isbf_pinning_enabled
        response.headers["Cache-Control"] = "no-store"
        render_serialized(
          IsbfPinning::BarTopics.list(current_user),
          IsbfPinning::BarListSerializer,
          root: "topic_list",
        )
      end
    end
  end

  IsbfPinning::Engine.routes.draw { get "/topics" => "bar_topics#index" }
  Discourse::Application.routes.append { mount ::IsbfPinning::Engine, at: "/isbf/pinning" }
  UploadCreator.prepend(IsbfPinning::BarUpload)
  UploadsController.prepend(IsbfPinning::BarUploadController)
  Admin::SiteSettingsController.prepend(IsbfPinning::BarSettingsController)

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
