import { click, fillIn, render, settled } from "@ember/test-helpers";
import { module, test } from "qunit";
import { setupRenderingTest } from "discourse/tests/helpers/component-test";
import pretender from "discourse/tests/helpers/create-pretender";
import IsbfPinnedBarSettings from "discourse/plugins/isbf-pinning/discourse/components/isbf-pinned-bar-settings";
import IsbfPinnedBarConnector from "discourse/plugins/isbf-pinning/discourse/connectors/admin-config-area-filtered-site-settings__before/isbf-pinned-bar";
import {
  DEFAULT_APPEARANCE,
  IMAGE_SETTINGS,
} from "discourse/plugins/isbf-pinning/discourse/lib/pinned-bar";

module("Integration | Component | IsbfPinnedBarSettings", function (hooks) {
  setupRenderingTest(hooks, { stubRouter: true });

  hooks.beforeEach(function () {
    localStorage.removeItem("isbf-pinning-preview-guides");
    this.currentUser.set("admin", true);
    this.saved = [];
    const settings = [
      {
        setting: "isbf_pinning_bar_appearance",
        value: JSON.stringify(DEFAULT_APPEARANCE),
      },
      { setting: "isbf_pinning_bar_default_topic_id", value: "0" },
      ...IMAGE_SETTINGS.map((setting) => ({
        setting,
        value: "",
        authorized_extensions: "png|webp|jpg|jpeg",
        max_file_size_kb: 5120,
      })),
    ];
    pretender.get("/admin/site_settings.json", () => [
      200,
      { "Content-Type": "application/json" },
      JSON.stringify({ site_settings: settings }),
    ]);
    pretender.get("/isbf/pinning/topics.json", () => [
      200,
      { "Content-Type": "application/json" },
      JSON.stringify({
        topic_list: {
          topics: [
            {
              id: 1,
              title: "Real pinned topic",
              slug: "pinned",
              created_at: "2026-01-01T00:00:00Z",
              excerpt: "A short summary",
              pinned: true,
              pinned_globally: true,
              isbf_pin_author: {
                id: 1,
                username: "author",
                avatar_template: "/images/avatar.png",
              },
            },
          ],
        },
      }),
    ]);
    pretender.put("/admin/site_settings/bulk_update.json", (request) => {
      this.saved.push(new URLSearchParams(request.requestBody));
      return [204, {}, ""];
    });
  });

  hooks.afterEach(function () {
    localStorage.removeItem("isbf-pinning-preview-guides");
  });

  test("the appearance editor belongs to interface settings instead of developer settings", async function (assert) {
    const router = this.owner.lookup("service:router");
    router.currentRouteName = "adminConfig.developer.settings";
    await render(<template><IsbfPinnedBarConnector /></template>);
    assert.dom(".isbf-pinning-editor").doesNotExist();

    router.currentRouteName = "adminConfig.interface.settings";
    await settled();
    assert.dom(".isbf-pinning-editor").exists();

    router.currentRouteName = "adminConfig.developer.settings";
    await settled();
    assert.dom(".isbf-pinning-editor").doesNotExist();
  });

  test("native color and numeric controls retain values across modes and save only website settings", async function (assert) {
    await render(<template><IsbfPinnedBarSettings /></template>);
    assert.dom('input[name="light.border_width"][type="range"]').hasValue("1");
    assert.dom('input[name="light.overflow"]').isChecked();
    await click('input[name="light.overflow"]');
    assert.dom('input[name="light.overflow"]').isNotChecked();
    await fillIn('input[name="light.border_width"][type="number"]', "2.5");
    assert
      .dom('input[name="light.border_width"][type="range"]')
      .hasValue("2.5");
    const fill = document.querySelector('input[name="light.fill"]');
    const color = fill.closest(".isbf-pinning-editor__color");
    await fillIn(color.querySelector('input[type="color"]'), "#123456");
    await fillIn(color.querySelector('input[type="range"]'), "0");
    assert.dom('input[name="light.fill"]').hasValue("#12345600");
    await click(".isbf-pinning-editor__modes .btn:nth-child(2)");
    assert.dom('input[name="dark.border_width"][type="number"]').hasValue("1");
    await fillIn('input[name="dark.border_width"][type="range"]', "0.5");
    assert
      .dom('input[name="dark.border_width"][type="number"]')
      .hasValue("0.5");
    await click(".isbf-pinning-editor__preview-controls .btn:nth-child(4)");
    assert.strictEqual(
      localStorage.getItem("isbf-pinning-preview-guides"),
      "true"
    );
    await click('button[type="submit"]');
    assert.strictEqual(this.saved.length, 1);
    const appearance = JSON.parse(
      this.saved[0].get("settings[isbf_pinning_bar_appearance][value]")
    );
    assert.strictEqual(appearance.light.fill, "#12345600");
    assert.strictEqual(appearance.light.border_width, 2.5);
    assert.false(
      appearance.light.overflow,
      "the visible overflow control persists"
    );
    assert.strictEqual(appearance.dark.border_width, 0.5);
    assert.false(
      [...this.saved[0].keys()].some((key) => key.includes("guides")),
      "editor aids never become public settings"
    );
    await click(".isbf-pinning-editor__modes .btn:first-child");
    assert.dom('input[name="light.fill"]').hasValue("#12345600");
  });

  test("invalid color cannot be saved and resetting one mode preserves the other", async function (assert) {
    await render(<template><IsbfPinnedBarSettings /></template>);
    await fillIn('input[name="light.fill"]', "invalid");
    await click('button[type="submit"]');
    assert.strictEqual(this.saved.length, 0);
    await click(".isbf-pinning-editor__modes .btn:nth-child(2)");
    await fillIn('input[name="dark.border_width"][type="number"]', "3");
    await click(".isbf-pinning-editor__modes .btn:first-child");
    await click(".isbf-pinning-editor form > .btn:last-of-type");
    assert
      .dom('input[name="light.fill"]')
      .hasValue(DEFAULT_APPEARANCE.light.fill);
    await click(".isbf-pinning-editor__modes .btn:nth-child(2)");
    assert.dom('input[name="dark.border_width"][type="number"]').hasValue("3");
  });
});
