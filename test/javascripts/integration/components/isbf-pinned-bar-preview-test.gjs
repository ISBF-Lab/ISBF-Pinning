import { render, waitUntil } from "@ember/test-helpers";
import { module, test } from "qunit";
import { setupRenderingTest } from "discourse/tests/helpers/component-test";
import IsbfPinnedBar from "discourse/plugins/isbf-pinning/discourse/components/isbf-pinned-bar";
import IsbfPinnedBarPreview from "discourse/plugins/isbf-pinning/discourse/components/isbf-pinned-bar-preview";
import { DEFAULT_APPEARANCE } from "discourse/plugins/isbf-pinning/discourse/lib/pinned-bar";

module("Integration | Component | IsbfPinnedBarPreview", function (hooks) {
  setupRenderingTest(hooks);

  hooks.beforeEach(function () {
    const canvas = document.createElement("canvas");
    canvas.width = 400;
    canvas.height = 1600;
    const context = canvas.getContext("2d");
    context.fillStyle = "#58b5dd80";
    context.fillRect(0, 0, 400, 1600);
    this.image = `${canvas.toDataURL()}#preview.png`;
    this.images = { isbf_pinning_bar_light_desktop_image: this.image };
    this.appearance = structuredClone(DEFAULT_APPEARANCE);
    this.appearance.light.fit = "cover";
    this.expanded = false;
    this.mobile = false;
    this.guides = true;
    this.mode = "light";
    this.topics = [1, 2, 3].map((id) => ({
      id,
      title: `Pinned topic ${id}`,
      slug: "pinned",
      created_at: "2026-01-01T00:00:00Z",
      excerpt: "Summary",
      pinned: true,
      pinned_globally: true,
    }));
  });

  test("guides follow actual expanded dimensions while the decorative image stays anchored", async function (assert) {
    await render(
      <template>
        <IsbfPinnedBarPreview
          @appearance={{this.appearance}}
          @expanded={{this.expanded}}
          @guides={{this.guides}}
          @images={{this.images}}
          @mobile={{this.mobile}}
          @mode={{this.mode}}
          @topics={{this.topics}}
        />
      </template>
    );
    await waitUntil(
      () =>
        document.querySelector(".isbf-pinning-original__boundary")?.style !==
          undefined &&
        document.querySelector(".isbf-pinned-bar__image")?.style.height
    );
    const bar = document.querySelector(".isbf-pinned-bar");
    const image = document.querySelector(".isbf-pinned-bar__image");
    const boundary = document.querySelector(".isbf-pinning-preview__boundary");
    await waitUntil(
      () =>
        Math.abs(
          boundary.getBoundingClientRect().height -
            bar.getBoundingClientRect().height
        ) < 0.5
    );
    const foldedHeight = bar.getBoundingClientRect().height;
    const foldedImageStyle = image.getAttribute("style");
    const original = document.querySelector(".isbf-pinning-original");
    const foldedVisibleHeight =
      original.style.getPropertyValue("--original-height");
    assert
      .dom(".isbf-pinning-preview__checker")
      .exists("transparent PNG has a checkerboard");
    assert.true(
      image.getBoundingClientRect().height > foldedHeight * 10,
      "a tall cover image does not increase bar height"
    );
    assert.closeTo(boundary.getBoundingClientRect().height, foldedHeight, 0.5);
    this.set("expanded", true);
    await waitUntil(
      () =>
        bar.offsetHeight >
        bar.querySelector(".isbf-pinned-bar__toggle").offsetHeight + 60
    );
    await waitUntil(
      () =>
        Math.abs(
          boundary.getBoundingClientRect().height -
            bar.getBoundingClientRect().height
        ) < 0.5
    );
    assert.strictEqual(
      image.getAttribute("style"),
      foldedImageStyle,
      "opening the list cannot stretch the decoration"
    );
    assert.notStrictEqual(
      original.style.getPropertyValue("--original-height"),
      foldedVisibleHeight,
      "the original-image intersection is recalculated"
    );
    this.set("guides", false);
    assert.dom(".isbf-pinning-preview__boundary").doesNotExist();
    assert.dom(".isbf-pinning-original__boundary").doesNotExist();
    assert
      .dom(image)
      .hasAttribute("src", this.image, "guides never modify the file");
  });

  test("mobile falls back within its own color mode and clipping leaves the original intact", async function (assert) {
    this.mobile = true;
    this.appearance.light.overflow = false;
    await render(
      <template>
        <IsbfPinnedBarPreview
          @appearance={{this.appearance}}
          @guides={{this.guides}}
          @images={{this.images}}
          @mobile={{this.mobile}}
          @mode={{this.mode}}
          @topics={{this.topics}}
        />
      </template>
    );
    await waitUntil(
      () =>
        document.querySelector(".isbf-pinned-bar__image")?.style.height &&
        document.querySelector(".isbf-pinned-bar").clientWidth <= 390
    );
    assert.dom(".isbf-pinned-bar__background").hasClass("is-clipped");
    assert.dom(".isbf-pinned-bar__image").hasAttribute("src", this.image);
    assert.true(
      document.querySelector(".isbf-pinned-bar").getBoundingClientRect()
        .width <= 390
    );
    assert.dom(".isbf-pinning-original img").hasAttribute("src", this.image);
    this.set("mode", "dark");
    assert
      .dom(".isbf-pinned-bar__image")
      .doesNotExist("dark mode never borrows the light image");
    assert.dom(".isbf-pinned-bar").hasAttribute("data-color-mode", "dark");
  });

  test("a tall decoration reserves its visible height without covering the adjacent feed", async function (assert) {
    await render(
      <template>
        <div class="contents" style="padding:0"><IsbfPinnedBar
            @appearance={{this.appearance}}
            @images={{this.images}}
            @mode="light"
            @topics={{this.topics}}
          /><p style="margin:0">Ordinary feed content</p></div>
      </template>
    );
    await waitUntil(
      () => document.querySelector(".isbf-pinned-bar__image")?.style.height
    );
    const bar = document.querySelector(".isbf-pinned-bar");
    const frame = document
      .querySelector(".isbf-pinned-bar__background")
      .getBoundingClientRect();
    const feed = document.querySelector(".contents").getBoundingClientRect();
    assert.true(
      frame.top < bar.getBoundingClientRect().top,
      "the decoration can extend above the bar"
    );
    assert.closeTo(
      frame.top,
      feed.top,
      0.5,
      "the image meets the upper boundary"
    );
    assert.closeTo(
      frame.bottom,
      document.querySelector(".contents > p").getBoundingClientRect().top,
      0.5,
      "the following post starts at the artwork's lower boundary"
    );
    assert.strictEqual(
      bar.offsetHeight,
      bar.querySelector(".isbf-pinned-bar__toggle").offsetHeight,
      "the compact bar retains its own height"
    );
    assert.strictEqual(
      getComputedStyle(bar, "::after").zIndex,
      "3",
      "the native rounded border stays above every layer"
    );
    assert.strictEqual(
      getComputedStyle(bar, "::before").zIndex,
      "1",
      "opaque fill masks the picture inside the frame"
    );
  });
});
