import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { service } from "@ember/service";
import { trustHTML } from "@ember/template";
import { modifier } from "ember-modifier";
import { getURLWithCDN } from "discourse/lib/get-url";
import DButton from "discourse/ui-kit/d-button";
import dAvatar from "discourse/ui-kit/helpers/d-avatar";
import dConcatClass from "discourse/ui-kit/helpers/d-concat-class";
import dIcon from "discourse/ui-kit/helpers/d-icon";
import dUniqueId from "discourse/ui-kit/helpers/d-unique-id";
import { i18n } from "discourse-i18n";
import {
  activeTopics,
  backgroundGeometry,
  excerptText,
  imageSetting,
  parseAppearance,
  selectedTopic,
  uniqueAuthors,
} from "../lib/pinned-bar";

export default class IsbfPinnedBar extends Component {
  @service appEvents;
  @service isbfPinnedBar;
  @service site;
  @service siteSettings;

  @tracked expanded = false;
  @tracked mode = "light";
  @tracked width = 600;
  @tracked geometry;

  panelId = `isbf-pinned-${dUniqueId()}`;

  measure = modifier((element, [appearance, , mobile]) => {
    let frame;
    let alive = true;
    const header = element.querySelector(".isbf-pinned-bar__toggle");
    const image = element.querySelector(".isbf-pinned-bar__image");
    const feed = element.closest(".contents");
    feed?.classList.add("isbf-pinning-feed");
    const update = () => {
      cancelAnimationFrame(frame);
      frame = requestAnimationFrame(() => {
        if (!alive) {
          return;
        }
        const width = element.clientWidth;
        const height = element.clientHeight;
        this.width = width;
        this.mode =
          getComputedStyle(document.documentElement)
            .getPropertyValue("--scheme-type")
            .trim() === "dark"
            ? "dark"
            : "light";
        const geometry = image?.naturalWidth
          ? backgroundGeometry({
              width,
              height,
              headerHeight: header.offsetHeight,
              imageWidth: image.naturalWidth,
              imageHeight: image.naturalHeight,
              mobile,
              appearance,
            })
          : null;
        if (geometry) {
          const barBox = element.getBoundingClientRect();
          const scale = barBox.height / height || 1;
          geometry.paintBelow = feed
            ? Math.min(
                geometry.below,
                Math.max(
                  0,
                  (feed.getBoundingClientRect().bottom - barBox.bottom) / scale
                )
              )
            : geometry.below;
        }
        if (JSON.stringify(geometry) !== JSON.stringify(this.geometry)) {
          this.geometry = geometry;
          this.args.onGeometry?.(geometry);
        }
      });
    };
    const resize = new ResizeObserver(update);
    resize.observe(element);
    resize.observe(header);
    if (feed) {
      resize.observe(feed);
    }
    const colors = window.matchMedia("(prefers-color-scheme: dark)");
    colors.addEventListener("change", update);
    this.appEvents.on("interface-color:changed", update);
    image?.addEventListener("load", update);
    update();
    return () => {
      alive = false;
      cancelAnimationFrame(frame);
      resize.disconnect();
      colors.removeEventListener("change", update);
      this.appEvents.off("interface-color:changed", update);
      image?.removeEventListener("load", update);
      feed?.classList.remove("isbf-pinning-feed");
    };
  });

  constructor() {
    super(...arguments);
    if (!this.args.topics) {
      this.isbfPinnedBar.acquire();
    }
  }

  willDestroy() {
    if (!this.args.topics) {
      this.isbfPinnedBar.release();
    }
    super.willDestroy(...arguments);
  }

  get topics() {
    return activeTopics(this.args.topics ?? this.isbfPinnedBar.topics);
  }

  get visible() {
    return this.topics.length > 0;
  }

  get isExpanded() {
    return this.args.expanded ?? this.expanded;
  }

  get colorMode() {
    return this.args.mode ?? this.mode;
  }

  get isMobile() {
    return this.args.mobile ?? this.site.mobileView;
  }

  get appearance() {
    return parseAppearance(
      this.args.appearance ?? this.siteSettings.isbf_pinning_bar_appearance
    )[this.colorMode];
  }

  get imageUrl() {
    const values = this.args.images ?? this.siteSettings;
    const desktop = values[imageSetting(this.colorMode, "desktop")];
    const source = this.isMobile
      ? values[imageSetting(this.colorMode, "mobile")] || desktop
      : desktop;
    return source ? getURLWithCDN(source) : null;
  }

  get defaultTopic() {
    return selectedTopic(
      this.topics,
      this.args.defaultTopicId ?? this.isbfPinnedBar.defaultTopicId
    );
  }

  get defaultTitle() {
    return this.defaultTopic?.title || i18n("isbf_pinning.bar.untitled");
  }

  get authors() {
    return uniqueAuthors(this.topics);
  }

  get avatarLimit() {
    return this.width < 360 ? 1 : this.width < 480 ? 2 : 3;
  }

  get shownAuthors() {
    return this.authors.slice(0, this.avatarLimit);
  }

  get moreAuthors() {
    return Math.max(0, this.authors.length - this.avatarLimit);
  }

  get rows() {
    return this.topics.map((topic) => ({
      ...topic,
      href: `/t/${encodeURIComponent(topic.slug || "topic")}/${topic.id}`,
      excerpt: excerptText(topic.excerpt),
      title: topic.title || i18n("isbf_pinning.bar.untitled"),
      authorName:
        topic.isbf_pin_author?.name || topic.isbf_pin_author?.username,
      date: new Intl.DateTimeFormat(document.documentElement.lang || "zh-CN", {
        dateStyle: "medium",
      }).format(new Date(topic.created_at)),
    }));
  }

  get style() {
    const config = this.appearance;
    return trustHTML(
      `--pin-fill:${config.fill};--pin-border:${config.border};--pin-border-width:${config.border_width}px;--pin-image-opacity:${config.opacity}`
    );
  }

  get imageStyle() {
    const image = this.geometry?.image;
    const above = this.appearance.overflow ? this.geometry?.above || 0 : 0;
    return image
      ? trustHTML(
          `width:${image.width}px;height:${image.height}px;inset-inline-start:${image.x}px;top:${image.y + above}px`
        )
      : undefined;
  }

  get backgroundStyle() {
    const above = this.geometry?.above || 0;
    const below = this.geometry?.paintBelow || 0;
    return trustHTML(
      `--pin-overflow-above:${above}px;--pin-overflow-below:${below}px`
    );
  }

  @action
  toggle() {
    this.expanded = !this.isExpanded;
    this.args.onToggle?.(this.expanded);
  }

  <template>
    {{#if this.visible}}
      <section
        aria-label={{i18n "isbf_pinning.bar.label"}}
        class={{dConcatClass
          "isbf-pinned-bar"
          (if this.isExpanded "is-expanded")
          (if this.isMobile "--mobile")
        }}
        data-color-mode={{this.colorMode}}
        style={{this.style}}
        ...attributes
        {{this.measure this.appearance this.imageUrl this.isMobile}}
      >
        {{#if this.imageUrl}}
          <div
            aria-hidden="true"
            class={{dConcatClass
              "isbf-pinned-bar__background"
              (unless this.appearance.overflow "is-clipped")
            }}
            style={{this.backgroundStyle}}
          >
            <img
              alt=""
              class={{dConcatClass
                "isbf-pinned-bar__image"
                (if this.geometry "is-measured")
              }}
              draggable="false"
              src={{this.imageUrl}}
              style={{this.imageStyle}}
            />
          </div>
        {{/if}}
        <DButton
          aria-controls={{this.panelId}}
          aria-expanded={{if this.isExpanded "true" "false"}}
          class="isbf-pinned-bar__toggle"
          @action={{this.toggle}}
        >
          <span class="isbf-pinned-bar__label">{{dIcon "thumbtack"}}
            {{i18n "isbf_pinning.bar.label"}}</span>
          <span class="isbf-pinned-bar__count">{{i18n
              "isbf_pinning.bar.count"
              count=this.topics.length
            }}</span>
          <span aria-hidden="true" class="isbf-pinned-bar__divider"></span>
          <span class="isbf-pinned-bar__authors">
            {{#each this.shownAuthors key="id" as |author|}}
              <span class="isbf-pinned-bar__avatar">{{dAvatar
                  author
                  imageSize="small"
                }}</span>
            {{/each}}
            {{#if this.moreAuthors}}<span
                class="isbf-pinned-bar__more"
              >+{{this.moreAuthors}}</span>{{/if}}
          </span>
          <span class="isbf-pinned-bar__title">{{this.defaultTitle}}</span>
          <span aria-hidden="true" class="isbf-pinned-bar__chevron">{{dIcon
              "chevron-down"
            }}</span>
        </DButton>
        <div
          class="isbf-pinned-bar__expansion"
          inert={{unless this.isExpanded true}}
        >
          <div class="isbf-pinned-bar__clip">
            <ul class="isbf-pinned-bar__list" id={{this.panelId}}>
              {{#each this.rows key="id" as |topic|}}
                <li class="isbf-pinned-bar__item">
                  <a class="isbf-pinned-bar__link" href={{topic.href}}>
                    <span class="isbf-pinned-bar__author-avatar">{{dAvatar
                        topic.isbf_pin_author
                        imageSize="large"
                      }}</span>
                    <span class="isbf-pinned-bar__content">
                      <span class="isbf-pinned-bar__meta">{{topic.authorName}}
                        <span>·
                          <time
                            datetime={{topic.created_at}}
                          >{{topic.date}}</time></span></span>
                      <span
                        class="isbf-pinned-bar__post-title"
                      >{{topic.title}}</span>
                      <span
                        class="isbf-pinned-bar__excerpt"
                      >{{topic.excerpt}}</span>
                    </span>
                    {{dIcon "chevron-right"}}
                  </a>
                </li>
              {{/each}}
            </ul>
          </div>
        </div>
      </section>
    {{/if}}
  </template>
}
