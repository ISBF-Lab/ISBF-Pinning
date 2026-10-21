import { tracked } from "@glimmer/tracking";
import Service, { service } from "@ember/service";
import { ajax } from "discourse/lib/ajax";

export default class IsbfPinnedBar extends Service {
  @service appEvents;

  @tracked topics = [];
  @tracked error = false;
  @tracked defaultTopicId = 0;

  refresh = () => {
    if (this.#request) {
      return this.#request;
    }
    clearTimeout(this.#timer);
    this.#request = this.#fetchTopics();
    return this.#request;
  };

  #references = 0;
  #request;
  #timer;

  willDestroy() {
    this.#stop();
    super.willDestroy(...arguments);
  }

  acquire() {
    if (this.#references++ === 0) {
      this.appEvents.on("isbf:home-pin-saved", this, "refresh");
      this.appEvents.on("isbf:home-pins-changed", this, "refresh");
      window.addEventListener("focus", this.refresh);
      this.refresh();
    }
  }

  release() {
    this.#references = Math.max(0, this.#references - 1);
    if (this.#references === 0) {
      this.#stop();
    }
  }

  async #fetchTopics() {
    try {
      const data = await ajax("/isbf/pinning/topics.json");
      if (!this.isDestroying) {
        this.topics = data.topic_list?.topics || [];
        this.defaultTopicId = data.topic_list?.default_topic_id || 0;
        this.error = false;
      }
    } catch {
      if (!this.isDestroying) {
        this.topics = [];
        this.error = true;
      }
    } finally {
      this.#request = null;
      if (this.#references > 0 && !this.isDestroying) {
        const deadlines = this.topics
          .map((topic) =>
            Date.parse(
              topic.isbf_home_pinning?.pinned_until || topic.pinned_until
            )
          )
          .filter(Number.isFinite);
        const delay = Math.max(
          100,
          Math.min(
            30000,
            ...deadlines.map((deadline) => deadline - Date.now() + 50)
          )
        );
        this.#timer = setTimeout(this.refresh, delay);
      }
    }
  }

  #stop() {
    clearTimeout(this.#timer);
    window.removeEventListener("focus", this.refresh);
    this.appEvents.off("isbf:home-pin-saved", this, "refresh");
    this.appEvents.off("isbf:home-pins-changed", this, "refresh");
  }
}
