import { getOwner } from "@ember/owner";
import { visit } from "@ember/test-helpers";
import { test } from "qunit";
import { cloneJSON } from "discourse/lib/object";
import discoveryFixtures from "discourse/tests/fixtures/discovery-fixtures";
import { acceptance } from "discourse/tests/helpers/qunit-helpers";

function payload({ chronological = true, incoming = false } = {}) {
  const result = cloneJSON(discoveryFixtures["/latest.json"]);
  const sample = result.topic_list.topics[0];
  const topic = (id, createdAt, pinned = false) => ({
    ...cloneJSON(sample),
    id,
    created_at: createdAt,
    bumped_at: "2026-10-23T12:00:00Z",
    pinned,
  });
  const recent = topic(5002, "2026-10-22T12:00:00Z");
  const updated = topic(5001, "2026-10-21T12:00:00Z");
  const pin = topic(4999, "2026-10-15T12:00:00Z", true);
  result.topic_list.isbf_home_feed_chronological = chronological;
  result.topic_list.more_topics_url = null;
  result.topic_list.topics = incoming
    ? [
        pin,
        topic(5004, "2026-10-23T12:00:00Z"),
        topic(5003, "2026-10-23T12:00:00Z"),
        updated,
      ]
    : [recent, updated, pin];
  return result;
}

acceptance("Chronological home feed updates", function (needs) {
  needs.user();
  needs.pretender((server, helper) => {
    server.get("/latest.json", (request) =>
      helper.response(
        payload({ incoming: Boolean(request.queryParams.topic_ids) })
      )
    );
  });

  test("new and updated posts keep their original feed dates", async function (assert) {
    await visit("/latest");
    const store = getOwner(this).lookup("service:store");
    const list = store.createRecord("topic-list", {
      ...payload(),
      filter: "latest",
    });

    await list.loadBefore([4999, 5004, 5003, 5001], true);

    assert.deepEqual(
      list.topics.map((topic) => topic.id),
      [5004, 5003, 5002, 5001, 4999],
      "new posts lead, equal dates use descending IDs, and updated older posts stay at their dates"
    );
    assert.strictEqual(
      getOwner(this).lookup("service:session").topicList,
      list,
      "the cached list retains the corrected order"
    );
  });

  test("lists outside the chronological home feed retain native insertion order", async function (assert) {
    await visit("/latest");
    const store = getOwner(this).lookup("service:store");
    const list = store.createRecord("topic-list", {
      ...payload({ chronological: false }),
      filter: "latest",
    });

    await list.loadBefore([4999, 5004, 5003, 5001], true);

    assert.deepEqual(
      list.topics.map((topic) => topic.id),
      [4999, 5004, 5003, 5001, 5002],
      "a non-home list keeps the server's pin-priority and native insertion order"
    );
  });
});
