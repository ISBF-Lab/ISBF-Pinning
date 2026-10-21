import { click, render, waitUntil } from "@ember/test-helpers";
import { module, test } from "qunit";
import { setupRenderingTest } from "discourse/tests/helpers/component-test";
import IsbfPinnedBar from "discourse/plugins/isbf-pinning/discourse/components/isbf-pinned-bar";
import { DEFAULT_APPEARANCE } from "discourse/plugins/isbf-pinning/discourse/lib/pinned-bar";

module("Integration | Component | IsbfPinnedBar", function (hooks) {
  setupRenderingTest(hooks);

  test("renders the chosen title, unique authors and compact escaped excerpts", async function (assert) {
    const author = {
      id: 1,
      username: "author",
      name: "Author",
      avatar_template: "/letter_avatar_proxy/v4/letter/a/ffffff/{size}.png",
    };
    const topics = [1, 2].map((id) => ({
      id,
      title: `Pinned ${id}`,
      slug: `pinned-${id}`,
      excerpt: "<b>Safe summary</b>",
      created_at: "2026-01-01T00:00:00Z",
      pinned: true,
      pinned_globally: true,
      isbf_pin_author: author,
    }));

    await render(
      <template>
        <IsbfPinnedBar @defaultTopicId={{2}} @topics={{topics}} />
      </template>
    );
    assert
      .dom(".isbf-pinned-bar__title")
      .hasText("Pinned 2", "the chosen real title is shown");
    assert
      .dom(".isbf-pinned-bar__authors .avatar")
      .exists({ count: 1 }, "a repeated author appears once");
    assert
      .dom(".isbf-pinned-bar__toggle")
      .hasAttribute("aria-expanded", "false", "the bar starts collapsed");
    await click(".isbf-pinned-bar__toggle");
    assert
      .dom(".isbf-pinned-bar__toggle")
      .hasAttribute("aria-expanded", "true", "the header expands the list");
    assert
      .dom(".isbf-pinned-bar__item:first-child .isbf-pinned-bar__excerpt")
      .hasText("Safe summary", "the summary is text");
    assert
      .dom(".isbf-pinned-bar__excerpt b")
      .doesNotExist("excerpt HTML is never injected");
    assert
      .dom(".isbf-pinned-bar__item:first-child .isbf-pinned-bar__link")
      .hasAttribute(
        "href",
        "/t/pinned-1/1",
        "topic navigation uses the real topic"
      );
    assert
      .dom(".isbf-pinning-preview__boundary")
      .doesNotExist("developer guides never render in the public component");
  });

  test("hides the entire bar without active pins", async function (assert) {
    const topics = [];
    await render(<template><IsbfPinnedBar @topics={{topics}} /></template>);
    assert
      .dom(".isbf-pinned-bar")
      .doesNotExist("empty containers cannot leave a feed gap");
  });

  test("interface color changes update the mode without a refresh", async function (assert) {
    const topics = [
      {
        id: 1,
        title: "Pinned",
        slug: "pinned",
        created_at: "2026-01-01T00:00:00Z",
        pinned: true,
        pinned_globally: true,
      },
    ];
    const style = document.documentElement.style;
    const previous = style.getPropertyValue("--scheme-type");
    const events = this.owner.lookup("service:app-events");
    try {
      style.setProperty("--scheme-type", "light");
      await render(<template><IsbfPinnedBar @topics={{topics}} /></template>);
      style.setProperty("--scheme-type", "dark");
      events.trigger("interface-color:changed", "dark");
      await waitUntil(
        () =>
          document.querySelector(".isbf-pinned-bar")?.dataset.colorMode ===
          "dark"
      );
      assert.strictEqual(
        getComputedStyle(document.querySelector(".isbf-pinned-bar"))
          .getPropertyValue("--pin-fill")
          .trim(),
        DEFAULT_APPEARANCE.dark.fill
      );
      style.setProperty("--scheme-type", "light");
      events.trigger("interface-color:changed", "light");
      await waitUntil(
        () =>
          document.querySelector(".isbf-pinned-bar")?.dataset.colorMode ===
          "light"
      );
      assert.strictEqual(
        getComputedStyle(document.querySelector(".isbf-pinned-bar"))
          .getPropertyValue("--pin-fill")
          .trim(),
        DEFAULT_APPEARANCE.light.fill
      );
    } finally {
      if (previous) {
        style.setProperty("--scheme-type", previous);
      } else {
        style.removeProperty("--scheme-type");
      }
    }
  });
});
