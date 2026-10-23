# frozen_string_literal: true

require "rails_helper"

RSpec.describe "ISBF timed home pinning", type: :request do
  fab!(:admin)
  fab!(:moderator)
  fab!(:member) { Fabricate(:user, active: true, approved: true, trust_level: 1) }
  fab!(:high_trust) { Fabricate(:user, trust_level: 4) }
  fab!(:category)
  fab!(:official_category, :category)
  fab!(:topic) { Fabricate(:topic, category: category, user: member) }
  fab!(:first_post) { Fabricate(:post, topic: topic, user: member) }

  before do
    SiteSetting.isbf_pinning_enabled = true
    SiteSetting.isbf_pinning_home_actions_enabled = true
    SiteSetting.isbf_pinning_official_category_id = official_category.id
    if SiteSetting.respond_to?(:academy_official_category)
      SiteSetting.academy_official_category = official_category.id
    end
  end

  def status_request(record = topic, actor: admin, **fields)
    sign_in(actor) if actor
    put "/t/#{record.id}/status.json",
        params: { status: "pinned_globally", enabled: true, isbf_home_pin: true }.merge(fields)
  end

  def ids
    expect(response.status).to eq(200), response.body
    response.parsed_body.fetch("topic_list").fetch("topics").map { |t| t.fetch("id") }
  end

  def make_topic(age:, home_pin: false, category_record: category, pinned_at: Time.current)
    record =
      Fabricate(:topic, category: category_record, user: member, created_at: age, bumped_at: age)
    Fabricate(:post, topic: record, user: member)
    if home_pin
      record.update_pinned(true, true, 10.days.from_now.iso8601)
      record.update_column(:pinned_at, pinned_at)
      record.custom_fields[IsbfPinning::HOME_FIELD] = true
      record.save_custom_fields
    end
    record
  end

  it "adds a timed home scope using the original status endpoint and returns matching metadata" do
    freeze_time
    status_request
    expect(response.status).to eq(200), response.body
    expect(response.parsed_body["success"]).to be_present
    metadata = response.parsed_body.fetch("isbf_home_pinning")
    expect(metadata).to include("can_manage" => true, "scoped" => true, "active" => true)
    expect(Time.iso8601(metadata["pinned_until"])).to eq(3.days.from_now.change(usec: 0))
    expect(topic.reload.pinned_globally).to eq(true)
    expect(topic.custom_fields[IsbfPinning::HOME_FIELD]).to eq(true)
    get "/t/#{topic.id}.json"
    expect(response.parsed_body["isbf_home_pinning"]).to eq(metadata)
  end

  it "returns the capability and authoritative official category through the native site serializer" do
    sign_in(member)
    get "/site.json"
    expect(response.status).to eq(200), response.body
    expect(response.parsed_body["isbf_pinning"]).to include(
      "version" => 1,
      "enabled" => true,
      "home_actions_enabled" => true,
      "official_category_id" => official_category.id,
    )
  end

  %w[member moderator high_trust].each do |name|
    it "rejects #{name} on native pin, global pin, retime, unpin and home scope routes" do
      actor = public_send(name)
      sign_in(actor)
      %w[pinned pinned_globally].each do |status|
        [true, false].each do |enabled|
          status_request(actor: actor, status: status, enabled: enabled)
          expect(response.status).to eq(403), response.body
          put "/t/#{topic.id}/status.json",
              params: {
                status: status,
                enabled: enabled,
                until: 3.days.from_now.iso8601,
              }
          expect(response.status).to eq(403), response.body
        end
      end
      expect(topic.reload.pinned_at).to be_nil
    end
  end

  it "rejects visitors on the native status endpoint" do
    status_request(actor: nil)
    expect(response.status).to eq(403), response.body
    expect(topic.reload.pinned_at).to be_nil
  end

  it "retains all unrelated native moderation actions" do
    sign_in(moderator)
    put "/t/#{topic.id}/status.json", params: { status: "closed", enabled: true }
    expect(response.status).to eq(200), response.body
    expect(topic.reload.closed).to eq(true)
  end

  it "sets, renews and cancels a home deadline while keeping one topic" do
    hide_const("RequestStore")
    deadline = 5.days.from_now.change(sec: 0)
    expect { status_request(until: deadline.iso8601) }.not_to change(Topic, :count)
    expect(response.status).to eq(200), response.body
    expect(response.parsed_body).to have_key("topic_status_update")
    expect(ActiveSupport::IsolatedExecutionState.key?(IsbfPinning::REQUEST_KEY)).to eq(false)
    expect(topic.reload.pinned_until).to eq(deadline)
    deadline += 2.days
    status_request(until: deadline.iso8601)
    expect(response.status).to eq(200), response.body
    expect(response.parsed_body).to have_key("topic_status_update")
    expect(ActiveSupport::IsolatedExecutionState.key?(IsbfPinning::REQUEST_KEY)).to eq(false)
    expect(topic.reload.pinned_until).to eq(deadline)
    status_request(enabled: false)
    expect(response.status).to eq(200), response.body
    expect(response.parsed_body).to have_key("topic_status_update")
    expect(ActiveSupport::IsolatedExecutionState.key?(IsbfPinning::REQUEST_KEY)).to eq(false)
    expect(response.parsed_body["isbf_home_pinning"]).to include(
      "scoped" => false,
      "active" => false,
    )
    expect(topic.reload.pinned_at).to be_nil

    put "/t/#{topic.id}/status.json", params: { status: "pinned", enabled: true }
    expect(response.status).to eq(200), response.body
    expect(topic.reload.pinned_at).to be_present
    expect(topic.pinned_globally).to eq(false)
    expect(topic.custom_fields[IsbfPinning::HOME_FIELD]).to be_nil
    expect(ActiveSupport::IsolatedExecutionState.key?(IsbfPinning::REQUEST_KEY)).to eq(false)
  end

  context "with Rails execution state and no RequestStore" do
    before { hide_const("RequestStore") }

    around do |example|
      previous_present = ActiveSupport::IsolatedExecutionState.key?(IsbfPinning::REQUEST_KEY)
      previous = ActiveSupport::IsolatedExecutionState[IsbfPinning::REQUEST_KEY]
      ActiveSupport::IsolatedExecutionState.delete(IsbfPinning::REQUEST_KEY)
      begin
        example.run
      ensure
        if previous_present
          ActiveSupport::IsolatedExecutionState[IsbfPinning::REQUEST_KEY] = previous
        else
          ActiveSupport::IsolatedExecutionState.delete(IsbfPinning::REQUEST_KEY)
        end
      end
    end

    [false, true].each do |ineligible|
      it "restores inherited state after a #{ineligible ? "failed" : "successful"} native status request" do
        sign_in(admin)
        first_post.update!(hidden: true) if ineligible
        [nil, { topic_id: -1 }].each do |previous|
          ActiveSupport::IsolatedExecutionState[IsbfPinning::REQUEST_KEY] = previous
          status_request(actor: nil)
          expect(response.status).to eq(ineligible ? 403 : 200), response.body
          expect(ActiveSupport::IsolatedExecutionState.key?(IsbfPinning::REQUEST_KEY)).to eq(true)
          expect(ActiveSupport::IsolatedExecutionState[IsbfPinning::REQUEST_KEY]).to equal(previous)
        end
      end
    end

    it "preserves inherited state when validation rejects the request before scoping it" do
      previous = { topic_id: -1 }
      [
        [member, {}, 403],
        [admin, { until: "not-a-date" }, 400],
        [admin, { enabled: "yes" }, 400],
        [admin, { isbf_home_pin: false }, 400],
        [admin, { status: "closed" }, 400],
      ].each do |actor, fields, expected_status|
        sign_in(actor)
        ActiveSupport::IsolatedExecutionState[IsbfPinning::REQUEST_KEY] = previous
        status_request(actor: nil, **fields)
        expect(response.status).to eq(expected_status), response.body
        expect(ActiveSupport::IsolatedExecutionState[IsbfPinning::REQUEST_KEY]).to equal(previous)
      end
    end

    it "clears failed home scope before a later native pin on the same topic" do
      sign_in(admin)
      first_post.update!(hidden: true)
      status_request(actor: nil)
      expect(response.status).to eq(403), response.body
      expect(ActiveSupport::IsolatedExecutionState.key?(IsbfPinning::REQUEST_KEY)).to eq(false)

      first_post.update!(hidden: false)
      put "/t/#{topic.id}/status.json", params: { status: "pinned", enabled: true }
      expect(response.status).to eq(200), response.body
      expect(response.parsed_body).to have_key("topic_status_update")
      expect(topic.reload.pinned_at).to be_present
      expect(topic.pinned_globally).to eq(false)
      expect(topic.custom_fields[IsbfPinning::HOME_FIELD]).to be_nil
      expect(ActiveSupport::IsolatedExecutionState.key?(IsbfPinning::REQUEST_KEY)).to eq(false)
    end
  end

  ["", "forever", "not-a-date", "1900-01-01T12:00:00Z", "2100-02-31T12:00:00Z"].each do |deadline|
    it "rejects invalid or expired deadline #{deadline.inspect} without changing the previous pin" do
      status_request
      existing = topic.reload.pinned_until
      status_request(until: deadline)
      expect(response.status).to eq(400), response.body
      expect(topic.reload.pinned_until).to eq(existing)
    end
  end

  it "does not silently interpret malformed scope or enabled flags" do
    [false, "false", "yes"].each do |scope|
      status_request(isbf_home_pin: scope)
      expect(response.status).to eq(400), response.body
    end
    ["yes", "1", ""].each do |flag|
      status_request(enabled: flag)
      expect(response.status).to eq(400), response.body
    end
    status_request(status: "closed")
    expect(response.status).to eq(400), response.body
    expect(topic.reload.pinned_at).to be_nil
  end

  it "blocks source field injection through normal posting, editing and direct topic update" do
    sign_in(member)
    payload = {
      title: "Try a native pin bypass",
      raw: "Description of this campus topic.",
      category: category.id,
    }
    [
      { pinned_at: Time.current.iso8601 },
      { pinned_globally: true },
      { topic_custom_fields: { isbf_home_pin: true } },
      { custom_fields: { isbf_home_pin: true } },
    ].each do |fields|
      post "/posts.json", params: payload.merge(fields)
      expect(response.status).to eq(403), response.body
      put "/posts/#{first_post.id}.json", params: { post: { raw: first_post.raw }.merge(fields) }
      expect(response.status).to eq(403), response.body
    end
    put "/t/#{topic.id}.json", params: { title: topic.title, pinned_globally: true }
    expect(response.status).to eq(403), response.body
    expect(topic.reload.pinned_at).to be_nil
  end

  it "requires checked status requests for developer source field changes too" do
    sign_in(admin)
    post "/posts.json",
         params: {
           title: "No pin through topic create",
           raw: "Details for this new campus topic.",
           category: category.id,
           pinned_at: Time.current.iso8601,
         }
    expect(response.status).to eq(400), response.body
    expect(topic.reload.pinned_at).to be_nil
  end

  it "prevents bulk permission bypass and defaults developer bulk pins to three days" do
    sign_in(moderator)
    put "/topics/bulk.json",
        params: {
          topic_ids: [topic.id],
          operation: {
            type: "pin",
            pinned_globally: true,
          },
        }
    expect(response.status).to eq(403), response.body
    sign_in(admin)
    freeze_time
    put "/topics/bulk.json",
        params: {
          topic_ids: [topic.id],
          operation: {
            type: "pin",
            pinned_globally: true,
          },
        }
    expect(response.status).to eq(200), response.body
    expect(topic.reload.pinned_until).to eq(3.days.from_now.change(usec: 0))
    expect(topic.custom_fields[IsbfPinning::HOME_FIELD]).to be_nil
  end

  it "keeps home pins in chronological feed positions and pin-time order in the bar after reading" do
    old_pin = make_topic(age: 8.days.ago, home_pin: true, pinned_at: 3.hours.ago)
    new_pin = make_topic(age: 9.days.ago, home_pin: true, pinned_at: 1.hour.ago)
    recent = make_topic(age: 1.hour.ago)
    older = make_topic(age: 2.hours.ago)
    TopicUser.change(
      member.id,
      new_pin.id,
      cleared_pinned_at: Time.current,
      last_read_post_number: 1,
    )
    sequence = [recent.id, older.id, old_pin.id, new_pin.id]
    get "/latest.json"
    expect(ids & sequence).to eq(sequence)
    expect(response.parsed_body.dig("topic_list", "isbf_home_pinning_scope")).to eq(false)
    expect(response.parsed_body.dig("topic_list", "isbf_home_feed_chronological")).to eq(true)
    sign_in(member)
    get "/latest.json"
    expect(ids & sequence).to eq(sequence)
    expect(response.parsed_body.dig("topic_list", "isbf_home_pinning_scope")).to eq(false)
    metadata =
      response
        .parsed_body
        .dig("topic_list", "topics")
        .find { |t| t["id"] == new_pin.id }
        .fetch("isbf_home_pinning")
    expect(metadata).to include("active" => true, "can_manage" => false)
    get "/isbf/pinning/topics.json"
    expect(ids).to eq([new_pin.id, old_pin.id])
    expect(response.parsed_body.dig("topic_list", "isbf_home_pinning_scope")).to eq(true)
    expect(response.parsed_body.dig("topic_list", "isbf_home_feed_chronological")).to eq(false)
  end

  it "marks incremental home updates as chronological without including unrelated topics" do
    pin = make_topic(age: 10.days.ago, home_pin: true)
    updated = make_topic(age: 2.days.ago)
    recent = make_topic(age: 1.hour.ago)
    sign_in(member)

    get "/latest.json", params: { topic_ids: [pin.id, recent.id, updated.id].join(",") }

    expect(ids).to eq([recent.id, updated.id, pin.id])
    expect(response.parsed_body.dig("topic_list", "isbf_home_feed_chronological")).to eq(true)
  end

  it "serializes home pins when optional companion home fields are absent" do
    record = make_topic(age: 10.days.ago, home_pin: true)
    sign_in(member)
    get "/latest.json"
    expect(ids).to include(record.id)
    metadata =
      response
        .parsed_body
        .dig("topic_list", "topics")
        .find { |t| t["id"] == record.id }
        .fetch("isbf_home_pinning")
    expect(metadata).to include("active" => true, "scoped" => true)
  end

  %w[isbf_marketplace_home isbf_teamup_home].each do |field|
    [true, false].each do |home_visible|
      it "preloads #{field}=#{home_visible} when serializing a native topic list" do
        record = make_topic(age: 10.days.ago, home_pin: true)
        record.custom_fields[field] = home_visible
        record.save_custom_fields
        sign_in(member)
        get "/c/#{category.slug}/#{category.id}/l/latest.json"
        expect(ids).to include(record.id)
        metadata =
          response
            .parsed_body
            .dig("topic_list", "topics")
            .find { |t| t["id"] == record.id }
            .fetch("isbf_home_pinning")
        expect(metadata).to include("active" => home_visible, "scoped" => true)
      end
    end
  end

  it "preserves caller-requested alternative ordering and category navigation outside the home feed" do
    pin = make_topic(age: 10.days.ago, home_pin: true)
    recent = make_topic(age: 1.hour.ago)
    query = TopicQuery.new(member, category: category.id.to_s, order: "created")
    sequence = query.list_category_topic_ids(category)
    expect(sequence.index(recent.id)).to be < sequence.index(pin.id)
    sign_in(member)
    get "/latest.json", params: { order: "created", ascending: "true" }
    expect(response.parsed_body.dig("topic_list", "isbf_home_pinning_scope")).to eq(false)
    expect(response.parsed_body.dig("topic_list", "isbf_home_feed_chronological")).to eq(false)
  end

  it "paginates more home pins than one page without losing or repeating topics" do
    records =
      7.times.map do |i|
        make_topic(age: (i + 10).days.ago, home_pin: true, pinned_at: (i + 1).hours.ago)
      end
    4.times { |i| records << make_topic(age: (i + 1).hours.ago) }
    sign_in(member)
    all = []
    4.times do |page|
      get "/latest.json", params: { per_page: 3, page: page }
      all.concat(ids)
    end
    expect(all.uniq.size).to eq(all.size)
    expect(all).to include(*records.map(&:id))
    expect(all & records.map(&:id)).to eq((records.last(4) + records.first(7)).map(&:id))
  end

  it "restores ordinary ordering at the deadline even before the job clears native fields" do
    record = make_topic(age: 10.days.ago, home_pin: true)
    recent = make_topic(age: 1.hour.ago)
    record.update_column(:pinned_until, 1.minute.ago)
    sign_in(member)
    get "/latest.json"
    expect(ids.index(recent.id)).to be < ids.index(record.id)
    metadata =
      response
        .parsed_body
        .dig("topic_list", "topics")
        .find { |t| t["id"] == record.id }
        .fetch("isbf_home_pinning")
    expect(metadata["active"]).to eq(false)
  end

  it "leaves unrelated category, profile and filter ordering unchanged for home pins" do
    record = make_topic(age: 10.days.ago, home_pin: true)
    recent = make_topic(age: 1.hour.ago)
    sign_in(member)
    get "/c/#{category.slug}/#{category.id}/l/latest.json"
    expect(ids.index(recent.id)).to be < ids.index(record.id)
    expect(response.parsed_body.dig("topic_list", "isbf_home_pinning_scope")).to eq(false)
    get "/topics/created-by/#{member.username}.json"
    expect(response.status).to eq(200), response.body
    expect(ids.index(recent.id)).to be < ids.index(record.id)
    expect(response.parsed_body.dig("topic_list", "isbf_home_pinning_scope")).to eq(false)
    get "/filter.json", params: { q: "category:#{category.slug} order:created" }
    expect(ids.index(recent.id)).to be < ids.index(record.id)
    expect(response.parsed_body.dig("topic_list", "isbf_home_pinning_scope")).to eq(false)
  end

  it "applies the same home scope to the authoritative official category without exposing other categories" do
    record = make_topic(age: 10.days.ago, home_pin: true, category_record: official_category)
    recent = make_topic(age: 1.hour.ago, category_record: official_category)
    sign_in(member)
    get "/c/#{official_category.slug}/#{official_category.id}/l/latest.json"
    expect(ids.first).to eq(record.id)
    expect(ids).to include(recent.id)
    expect(ids).not_to include(topic.id)
    expect(response.parsed_body.dig("topic_list", "isbf_home_pinning_scope")).to eq(true)
    expect(response.parsed_body.dig("topic_list", "isbf_home_feed_chronological")).to eq(false)
  end

  it "marks only positive matching native official filter lists as scoped" do
    q =
      "isbf-official:#{official_category.id} isbf-campus:shenzhen isbf-official-type:academic order:activity"
    query = TopicQuery.new(member, q: q)
    list = query.create_list(:filter)
    expect(list.isbf_home_pinning_scope).to eq(true)
    query = TopicQuery.new(member, q: "-isbf-official:#{official_category.id}")
    list = query.create_list(:filter)
    expect(list.isbf_home_pinning_scope).to eq(false)
  end

  it "keeps legacy pins at their feed dates and preserves personal clearing in the bar" do
    record = make_topic(age: 10.days.ago)
    record.update_pinned(true, true)
    recent = make_topic(age: 1.hour.ago)
    sign_in(member)
    get "/latest.json"
    expect(ids.index(recent.id)).to be < ids.index(record.id)
    get "/isbf/pinning/topics.json"
    expect(ids).to include(record.id)
    TopicUser.change(member.id, record.id, cleared_pinned_at: 1.hour.from_now)
    get "/isbf/pinning/topics.json"
    expect(ids).not_to include(record.id)
  end

  it "rejects hidden or opted-out first posts instead of letting a pin bypass homepage restrictions" do
    topic.update!(visible: false)
    status_request
    expect(response.status).to eq(403), response.body
    topic.update!(visible: true)
    first_post.update!(hidden: true)
    status_request
    expect(response.status).to eq(403), response.body
    first_post.update!(hidden: false)
    topic.custom_fields["isbf_teamup_home"] = false
    topic.save_custom_fields
    status_request
    expect(response.status).to eq(403), response.body
    expect(topic.reload.pinned_at).to be_nil
  end

  it "keeps legacy and active home records unmodified when new home actions are disabled" do
    status_request
    pinned_at = topic.reload.pinned_at
    SiteSetting.isbf_pinning_home_actions_enabled = false
    status_request(until: 5.days.from_now.iso8601)
    expect(response.status).to eq(403), response.body
    get "/latest.json"
    expect(ids.first).to eq(topic.id)
    expect(topic.reload.pinned_at).to eq_time(pinned_at)
    status_request(enabled: false)
    expect(response.status).to eq(403), response.body
    expect(topic.reload.pinned_at).to eq_time(pinned_at)
  end

  it "does not allow hidden categories to be exposed by a pin or the list metadata" do
    group = Fabricate(:group)
    category.set_permissions(group.name => :full)
    category.save!
    status_request
    expect(response.status).to eq(200), response.body
    sign_in(member)
    get "/latest.json"
    expect(ids).not_to include(topic.id)
  end

  it "keeps Marketplace and Teamup home exclusions ahead of pagination with both plugins installed" do
    unless defined?(IsbfMarketplace) && defined?(IsbfTeamup)
      skip "Companion plugins are validated on the existing site; isolated plugin CI does not load them"
    end
    market = Fabricate(:category)
    group = Fabricate(:category)
    SiteSetting.isbf_marketplace_category_id = market.id
    SiteSetting.isbf_teamup_category_id = group.id
    SiteSetting.isbf_teamup_enabled = true
    hidden_market = make_topic(age: 1.hour.ago, home_pin: true, category_record: market)
    hidden_market.custom_fields[IsbfMarketplace::HOME_FIELD] = false
    hidden_market.save_custom_fields
    hidden_group = make_topic(age: 2.hours.ago, home_pin: true, category_record: group)
    hidden_group.custom_fields[IsbfTeamup::HOME_FIELD] = false
    hidden_group.save_custom_fields
    visible = make_topic(age: 5.days.ago, home_pin: true)
    sign_in(member)
    get "/latest.json", params: { per_page: 2 }
    expect(ids).to include(visible.id)
    expect(ids).not_to include(hidden_market.id, hidden_group.id)
  end

  it "retains scoped ordering with the installed Official campus/type native filter" do
    unless defined?(IsbfOfficial) && IsbfOfficial.category_id
      skip "Official integration requires Academy and Official plugins"
    end
    record = make_topic(age: 10.days.ago, home_pin: true, category_record: official_category)
    record.custom_fields["isbf_official_campuses"] = ["shenzhen"]
    record.custom_fields["isbf_official_types"] = ["academic"]
    record.save_custom_fields
    sign_in(member)
    get "/filter.json",
        params: {
          q:
            "isbf-official:#{official_category.id} isbf-campus:shenzhen isbf-official-type:academic order:activity",
        }
    expect(ids.first).to eq(record.id)
    expect(response.parsed_body.dig("topic_list", "isbf_home_pinning_scope")).to eq(true)
  end
end
