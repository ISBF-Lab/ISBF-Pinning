# frozen_string_literal: true

module IsbfPinning
  module PinGuardian
    def can_pin_unpin_topic?(topic)
      IsbfPinning.developer?(user) && super
    end
  end

  module StatusController
    def status
      pinning = %w[pinned pinned_globally].include?(params[:status].to_s)
      if pinning
        IsbfPinning.ensure_developer!(current_user)
        enabled = IsbfPinning.bool(params[:enabled])
        IsbfPinning.deadline(params[:until]) if enabled && params.key?(:until)
      end
      return super unless params.key?(IsbfPinning::HOME_FIELD)
      unless pinning && IsbfPinning.bool(params[IsbfPinning::HOME_FIELD])
        raise Discourse::InvalidParameters.new(IsbfPinning::HOME_FIELD)
      end
      previous = RequestStore.store[IsbfPinning::REQUEST_KEY]
      RequestStore.store[IsbfPinning::REQUEST_KEY] = { topic_id: params[:topic_id].to_i }
      super
      if response.status == 200 && @topic
        body = JSON.parse(response.body)
        body["isbf_home_pinning"] = IsbfPinning.metadata(@topic.reload, guardian)
        self.response_body = body.to_json
      end
    ensure
      RequestStore.store[IsbfPinning::REQUEST_KEY] = previous if params.key?(IsbfPinning::HOME_FIELD)
    end

    def update
      IsbfPinning.reject_side_channel!(params.to_unsafe_h, current_user)
      super
    end
  end

  module PostController
    def create
      IsbfPinning.reject_side_channel!(params.to_unsafe_h, current_user)
      super
    end

    def update
      IsbfPinning.reject_side_channel!(params.to_unsafe_h, current_user)
      IsbfPinning.reject_side_channel!(params[:post]&.to_unsafe_h, current_user)
      super
    end
  end

  module StatusMutation
    def update!(status, enabled, opts = {})
      return super unless %w[pinned pinned_globally].include?(status.to_s)
      IsbfPinning.ensure_developer!(user)
      raise Discourse::NotFound unless topic
      enabled = IsbfPinning.bool(enabled)
      options = opts.dup
      topic.with_lock do
        request = RequestStore.store[IsbfPinning::REQUEST_KEY]
        home = options[IsbfPinning::HOME_FIELD.to_sym] == true ||
          request&.fetch(:topic_id, nil) == topic.id || IsbfPinning.scoped?(topic)
        if home
          unless IsbfPinning.new_actions? && (!enabled || IsbfPinning.eligible?(topic, Guardian.new(user)))
            raise Discourse::InvalidAccess
          end
        end
        options[:until] = enabled ? IsbfPinning.deadline(options[:until]).iso8601 : nil
        if home && enabled
          topic.custom_fields[IsbfPinning::HOME_FIELD] = true
          topic.save_custom_fields
        end
        result = super(home ? "pinned_globally" : status, enabled, options)
        result
      end
    end
  end

  module BulkMutation
    def perform!
      if %w[pin unpin].include?(@operation[:type].to_s)
        IsbfPinning.ensure_developer!(@user)
        IsbfPinning.deadline(@operation[:pinned_until]) if @operation[:type].to_s == "pin"
      end
      super
    end
  end

  module TopicCreation
    def create
      IsbfPinning.reject_side_channel!(@opts, @user)
      super
    end
  end

  module PostRevision
    def revise!(editor, fields, opts = {}, &block)
      IsbfPinning.reject_side_channel!(fields, editor)
      super
    end
  end

  module NativePinCleanup
    def update_pinned(status, global = false, pinned_until = nil)
      result = super
      if !status && custom_fields[IsbfPinning::HOME_FIELD]
        custom_fields.delete(IsbfPinning::HOME_FIELD)
        save_custom_fields
      end
      result
    end
  end

  module Expiry
    def execute(args)
      topic = Topic.find_by(id: args[:topic_id])
      return unless topic
      topic.with_lock do
        return if topic.pinned_until.nil? || topic.pinned_until > Time.current
        super
      end
    end
  end
end
