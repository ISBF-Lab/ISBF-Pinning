import { apiInitializer } from "discourse/lib/api";

function compareCreatedTopics(left, right) {
  return (
    (Date.parse(right.created_at ?? right.createdAt) || 0) -
      (Date.parse(left.created_at ?? left.createdAt) || 0) ||
    Number(right.id) - Number(left.id)
  );
}

export default apiInitializer((api) => {
  const topicListClass = api.container.factoryFor("model:topic-list").class;
  const originalLoadBefore = topicListClass.prototype.loadBefore;

  api.addModelMethod("topic-list", "loadBefore", async function (...args) {
    const result = await originalLoadBefore.apply(this, args);

    // Native updates prepend topics, including older posts that received replies.
    if (
      this.topic_list?.isbf_home_feed_chronological === true &&
      !this.isDestroying &&
      !this.isDestroyed
    ) {
      this.set("topics", [...this.topics].sort(compareCreatedTopics));
    }

    return result;
  });
});
