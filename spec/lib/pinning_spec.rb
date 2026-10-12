# frozen_string_literal: true

require "rails_helper"

RSpec.describe IsbfPinning do
  fab!(:admin)
  fab!(:moderator)
  fab!(:member) { Fabricate(:user, trust_level: 1) }
  fab!(:category)
  fab!(:topic) { Fabricate(:topic, category: category, user: member) }
  fab!(:first_post) { Fabricate(:post, topic: topic, user: member) }

  before do
    SiteSetting.isbf_pinning_enabled = true
    SiteSetting.isbf_pinning_home_actions_enabled = true
  end

  def native_pin(record = topic, scope: true, until_at: 3.days.from_now)
    record.update_pinned(true, true, until_at.iso8601)
    if scope
      record.custom_fields[IsbfPinning::HOME_FIELD] = true
      record.save_custom_fields
    end
    record.reload
  end

  it "uses the underlying admin column instead of staff, moderator or overridden role predicates" do
    expect(described_class.developer?(admin)).to eq(true)
    expect(described_class.developer?(moderator)).to eq(false)
    expect(described_class.developer?(member)).to eq(false)
    expect(described_class.developer?(nil)).to be_falsey
    allow(moderator).to receive(:admin?).and_return(true)
    expect(described_class.developer?(moderator)).to eq(false)
  end

  it "uses the authoritative Academy category when available and an independent fallback otherwise" do
    SiteSetting.isbf_pinning_official_category_id = category.id
    if SiteSetting.respond_to?(:academy_official_category)
      SiteSetting.academy_official_category = category.id
    end
    expect(described_class.official_category_id).to eq(category.id)
    if SiteSetting.respond_to?(:academy_official_category)
      SiteSetting.academy_official_category = 0
    else
      SiteSetting.isbf_pinning_official_category_id = 0
    end
    expect(described_class.official_category_id).to be_nil
  end

  it "defaults omitted deadlines to exactly 72 hours" do
    freeze_time
    expect(described_class.deadline(nil)).to eq(Time.current + 72.hours)
  end

  it "accepts explicit-zone ISO and native picker timestamps" do
    freeze_time
    future = 6.days.from_now.change(sec: 0)
    expect(described_class.deadline(future.iso8601)).to eq(future)
    expect(described_class.deadline(future.strftime("%Y-%m-%d %H:%M%:z"))).to eq(future)
    expect(described_class.deadline(future.strftime("%Y-%m-%d %H:%M %:z"))).to eq(future)
  end

  ["", "forever", "never", "2100-02-31T10:00:00Z", "2100-13-01T10:00:00Z",
   "2100-01-01", "2100-01-01T10:00:00", true, false, 123].each do |input|
    it "rejects invalid or permanent expiry #{input.inspect}" do
      expect { described_class.deadline(input) }.to raise_error(Discourse::InvalidParameters)
    end
  end

  it "rejects expired or current deadlines" do
    freeze_time
    [1.day.ago.iso8601, Time.current.iso8601].each do |value|
      expect { described_class.deadline(value) }.to raise_error(Discourse::InvalidParameters)
    end
  end

  it "distinguishes a home scope from a legacy native pin" do
    native_pin(scope: false)
    expect(described_class.scoped?(topic)).to eq(false)
    expect(described_class.active?(topic)).to eq(false)
    native_pin
    expect(described_class.metadata(topic, Guardian.new(admin))).to include(
      can_manage: true, scoped: true, active: true,
    )
    expect(described_class.metadata(topic, Guardian.new(member))[:can_manage]).to eq(false)
  end

  it "marks an expired home pin inactive before its native job runs" do
    native_pin
    topic.update_column(:pinned_until, 1.minute.ago)
    expect(described_class.scoped?(topic)).to eq(true)
    expect(described_class.active?(topic)).to eq(false)
  end

  it "rejects hidden topics, deleted first posts, category definitions and PMs as pin targets" do
    guardian = Guardian.new(admin)
    expect(described_class.eligible?(topic, guardian)).to eq(true)
    topic.update!(visible: false)
    expect(described_class.eligible?(topic.reload, guardian)).to eq(false)
    topic.update!(visible: true)
    first_post.update!(hidden: true)
    expect(described_class.eligible?(topic.reload, guardian)).to eq(false)
    first_post.update!(hidden: false, user_deleted: true)
    expect(described_class.eligible?(topic.reload, guardian)).to eq(false)
    first_post.update!(user_deleted: false, deleted_at: Time.current)
    expect(described_class.eligible?(topic.reload, guardian)).to be_falsey
    first_post.update!(deleted_at: nil)
    category.update!(topic_id: topic.id)
    expect(described_class.eligible?(topic.reload, guardian)).to eq(false)
    pm = Fabricate(:private_message_topic)
    expect(described_class.eligible?(pm, guardian)).to eq(false)
  end

  it "does not treat explicitly opted-out marketplace or team-up content as a home pin target" do
    %w[isbf_marketplace_home isbf_teamup_home].each do |field|
      topic.custom_fields[field] = false
      expect(described_class.home_visible?(topic)).to eq(false)
      topic.custom_fields.delete(field)
    end
  end

  it "checks developer permissions even when the native status updater is called directly" do
    [member, moderator, nil].each do |actor|
      %w[pinned pinned_globally].each do |status|
        [true, false].each do |enabled|
          expect do
            TopicStatusUpdater.new(topic, actor).update!(status, enabled)
          end.to raise_error(Discourse::InvalidAccess)
        end
      end
    end
    expect(topic.reload.pinned_at).to be_nil
  end

  it "blocks direct bulk pin and unpin attempts by a moderator" do
    %w[pin unpin].each do |operation|
      expect do
        TopicsBulkAction.new(moderator, [topic.id], type: operation).perform!
      end.to raise_error(Discourse::InvalidAccess)
    end
  end

  it "retimes through native fields and rejects permanent native status requests" do
    freeze_time
    TopicStatusUpdater.new(topic, admin).update!("pinned", true)
    expect(topic.reload.pinned_until).to eq(3.days.from_now)
    expect(topic.pinned_globally).to eq(false)
    expect(topic.custom_fields[IsbfPinning::HOME_FIELD]).to be_nil
    expect do
      TopicStatusUpdater.new(topic, admin).update!("pinned", true, until: "")
    end.to raise_error(Discourse::InvalidParameters)
  end

  it "preserves a home scope on native retiming and removes it on explicit unpin" do
    native_pin
    new_until = 7.days.from_now
    TopicStatusUpdater.new(topic, admin).update!("pinned", true, until: new_until.iso8601)
    expect(topic.reload.pinned_globally).to eq(true)
    expect(topic.pinned_until.to_i).to eq(new_until.to_i)
    expect(described_class.scoped?(topic)).to eq(true)
    TopicStatusUpdater.new(topic, admin).update!("pinned_globally", false)
    expect(topic.reload.pinned_at).to be_nil
    expect(topic.pinned_until).to be_nil
    expect(topic.custom_fields[IsbfPinning::HOME_FIELD]).to be_nil
  end

  it "does not let an old running unpin job cancel a renewed pin early" do
    native_pin(until_at: 1.day.from_now)
    TopicStatusUpdater.new(topic, admin).update!("pinned_globally", true, until: 8.days.from_now.iso8601)
    Jobs::UnpinTopic.new.execute(topic_id: topic.id)
    expect(topic.reload.pinned_at).to be_present
    expect(described_class.active?(topic)).to eq(true)
  end

  it "does not let a stale expiry job unpin a legacy permanent pin" do
    topic.update_pinned(true)
    Jobs::UnpinTopic.new.execute(topic_id: topic.id)
    expect(topic.reload.pinned_at).to be_present
  end

  it "expires a due home pin through the native job without requiring a human actor" do
    native_pin
    topic.update_column(:pinned_until, 1.second.ago)
    Jobs::UnpinTopic.new.execute(topic_id: topic.id)
    expect(topic.reload.pinned_at).to be_nil
    expect(topic.pinned_globally).to eq(false)
    expect(topic.pinned_until).to be_nil
    expect(topic.custom_fields[IsbfPinning::HOME_FIELD]).to be_nil
  end

  it "keeps expiry, read-independent ordering and developer guards when new actions are disabled" do
    native_pin
    SiteSetting.isbf_pinning_home_actions_enabled = false
    expect(described_class.metadata(topic, Guardian.new(admin))).to include(active: true, can_manage: false)
    expect do
      TopicStatusUpdater.new(topic, admin).update!("pinned_globally", true, until: 8.days.from_now.iso8601)
    end.to raise_error(Discourse::InvalidAccess)
    expect do
      TopicStatusUpdater.new(topic, moderator).update!("pinned_globally", false)
    end.to raise_error(Discourse::InvalidAccess)
    topic.update_column(:pinned_until, 1.second.ago)
    Jobs::UnpinTopic.new.execute(topic_id: topic.id)
    expect(topic.reload.pinned_at).to be_nil
  end

  it "blocks direct topic-creation and revision side channels regardless of skip-validation options" do
    opts = { title: "Bypass pin on a campus topic", raw: "Campus topic details for the test.", category: category.id, pinned_at: Time.current.iso8601 }
    expect do
      PostCreator.new(member, opts.merge(skip_validations: true)).create
    end.to raise_error(Discourse::InvalidAccess)
    expect do
      TopicCreator.new(member, Guardian.new(member), opts.merge(custom_fields: { IsbfPinning::HOME_FIELD => true })).create
    end.to raise_error(Discourse::InvalidAccess)
    expect do
      PostRevisor.new(first_post).revise!(member, { IsbfPinning::HOME_FIELD => true }, validate_post: false)
    end.to raise_error(Discourse::InvalidAccess)
    expect(topic.reload.pinned_at).to be_nil
  end
end
