import { module, test } from "qunit";
import {
  activeTopics,
  backgroundGeometry,
  DEFAULT_APPEARANCE,
  excerptText,
  parseAppearance,
  selectedTopic,
  uniqueAuthors,
} from "discourse/plugins/isbf-pinning/discourse/lib/pinned-bar";

module("Unit | Lib | pinned-bar", function () {
  test("selection falls back without changing native order or duplicating authors", function (assert) {
    const topics = [
      { id: 7, isbf_pin_author: { id: 2 } },
      { id: 8, isbf_pin_author: { id: 2 } },
      { id: 9, isbf_pin_author: { id: 3 } },
    ];
    assert.strictEqual(
      selectedTopic(topics, 8),
      topics[1],
      "the chosen active topic is shown"
    );
    assert.strictEqual(
      selectedTopic(topics, 99),
      topics[0],
      "an inaccessible or removed choice falls back"
    );
    assert.deepEqual(
      uniqueAuthors(topics).map((author) => author.id),
      [2, 3],
      "authors are deduplicated by real user ID"
    );
  });

  test("expired scoped pins disappear", function (assert) {
    const topics = [
      {
        id: 1,
        isbf_home_pinning: {
          scoped: true,
          active: true,
          pinned_until: "2026-01-02T00:00:00Z",
        },
      },
      { id: 2, pinned: true, pinned_globally: true },
    ];
    assert.deepEqual(
      activeTopics(topics, Date.parse("2026-01-03T00:00:00Z")).map(
        (topic) => topic.id
      ),
      [2],
      "expired pins no longer count"
    );
  });

  test("guides use real dimensions while expansion preserves the image anchor", function (assert) {
    const options = {
      width: 600,
      height: 60,
      headerHeight: 60,
      imageWidth: 1600,
      imageHeight: 400,
      mobile: false,
      appearance: DEFAULT_APPEARANCE.dark,
    };
    const folded = backgroundGeometry(options);
    const expanded = backgroundGeometry({ ...options, height: 450 });
    assert.deepEqual(
      folded.image,
      { width: 600, height: 150, x: 0, y: -45 },
      "the image fits the desktop reference area"
    );
    assert.deepEqual(
      expanded.image,
      folded.image,
      "expansion does not stretch or shift the image"
    );
    assert.strictEqual(
      folded.below,
      45,
      "the collapsed bar exposes a lower extension"
    );
    assert.strictEqual(
      expanded.below,
      0,
      "the expanded boundary is recalculated"
    );
    assert.notDeepEqual(
      backgroundGeometry({ ...options, width: 390, mobile: true }).visible,
      folded.visible,
      "mobile is calculated from its own dimensions"
    );
  });

  test("cover and position updates change the real image intersection", function (assert) {
    const options = {
      width: 600,
      height: 60,
      headerHeight: 60,
      imageWidth: 400,
      imageHeight: 1600,
      mobile: false,
      appearance: DEFAULT_APPEARANCE.light,
    };
    const contain = backgroundGeometry(options);
    const cover = backgroundGeometry({
      ...options,
      appearance: { ...options.appearance, fit: "cover", y: 40 },
    });
    assert.true(cover.scale > contain.scale, "cover uses the larger scale");
    assert.notDeepEqual(
      cover.visible,
      contain.visible,
      "the original-image visible region changes with scale and offset"
    );
  });

  test("invalid styles are discarded and excerpts remain plain text", function (assert) {
    const parsed = parseAppearance({
      dark: { fill: "red;background:url(x)", y: Infinity },
    });
    assert.strictEqual(
      parsed.dark.fill,
      DEFAULT_APPEARANCE.dark.fill,
      "CSS injection cannot enter the style string"
    );
    assert.strictEqual(
      parsed.light.fill,
      DEFAULT_APPEARANCE.light.fill,
      "light and dark defaults are independent"
    );
    assert.strictEqual(
      excerptText(
        "<p>Hello <b>world</b><img src=x onerror=alert(1)></p><script>bad()</script>"
      ),
      "Hello world",
      "only excerpt text is retained"
    );
  });
});
