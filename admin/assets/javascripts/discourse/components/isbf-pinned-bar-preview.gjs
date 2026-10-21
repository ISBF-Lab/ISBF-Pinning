import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { trustHTML } from "@ember/template";
import { getURLWithCDN } from "discourse/lib/get-url";
import dConcatClass from "discourse/ui-kit/helpers/d-concat-class";
import { i18n } from "discourse-i18n";
import IsbfPinnedBar from "discourse/plugins/isbf-pinning/discourse/components/isbf-pinned-bar";
import { imageSetting } from "discourse/plugins/isbf-pinning/discourse/lib/pinned-bar";

export default class IsbfPinnedBarPreview extends Component {
  @tracked geometry;

  get imageUrl() {
    const desktop = this.args.images?.[imageSetting(this.args.mode, "desktop")];
    const image = this.args.mobile
      ? this.args.images?.[imageSetting(this.args.mode, "mobile")] || desktop
      : desktop;
    return image ? getURLWithCDN(image) : null;
  }

  get checkerboard() {
    return /\.(png|webp)(?:[?#]|$)/i.test(this.imageUrl || "");
  }

  get originalStyle() {
    const geometry = this.geometry;
    if (!geometry) {
      return undefined;
    }
    const { visible, imageWidth, imageHeight } = geometry;
    const top = (visible.y / imageHeight) * 100;
    const bottom = (visible.bottom / imageHeight) * 100;
    return trustHTML(
      `--original-top:${top}%;--original-bottom:${bottom}%;--original-left:${(visible.x / imageWidth) * 100}%;--original-width:${(Math.max(0, visible.right - visible.x) / imageWidth) * 100}%;--original-height:${Math.max(0, bottom - top)}%`
    );
  }

  get style() {
    const geometry = this.geometry;
    const above = geometry?.above || 0;
    const below = geometry?.below || 0;
    const image = geometry?.image;
    return trustHTML(
      `--preview-width:${this.args.mobile ? 390 : 600}px;--preview-above:${above}px;--preview-below:${below}px;--preview-bar-height:${geometry?.height || 0}px;--preview-image-top:${above + (image?.y || 0)}px;--preview-image-left:${image?.x || 0}px;--preview-image-width:${image?.width || 0}px;--preview-image-height:${image?.height || 0}px`
    );
  }

  @action
  measure(geometry) {
    this.geometry = geometry;
  }

  <template>
    <div class="isbf-pinning-preview__scroll">
      <div
        class={{dConcatClass "isbf-pinning-preview" (if @guides "has-guides")}}
        data-preview-mode={{@mode}}
        style={{this.style}}
      >
        {{#if this.checkerboard}}<div
            aria-hidden="true"
            class="isbf-pinning-preview__checker"
          ></div>{{/if}}
        <IsbfPinnedBar
          @appearance={{@appearance}}
          @defaultTopicId={{@defaultTopicId}}
          @expanded={{@expanded}}
          @images={{@images}}
          @mobile={{@mobile}}
          @mode={{@mode}}
          @onGeometry={{this.measure}}
          @onToggle={{@onToggle}}
          @topics={{@topics}}
        />
        {{#if @guides}}
          {{#if this.geometry}}
            <div aria-hidden="true" class="isbf-pinning-preview__above">{{i18n
                "isbf_pinning.editor.above"
              }}</div>
            <div aria-hidden="true" class="isbf-pinning-preview__boundary"><span
              >{{i18n "isbf_pinning.editor.visible"}}</span></div>
            <div aria-hidden="true" class="isbf-pinning-preview__below">{{i18n
                "isbf_pinning.editor.below"
              }}</div>
          {{/if}}
        {{/if}}
      </div>
    </div>
    {{#if this.imageUrl}}
      <h4>{{i18n "isbf_pinning.editor.original"}}</h4>
      <div
        class={{dConcatClass
          "isbf-pinning-original"
          (if this.checkerboard "has-alpha")
        }}
        style={{this.originalStyle}}
      >
        <a href={{this.imageUrl}} rel="noopener noreferrer" target="_blank"><img
            alt={{i18n "isbf_pinning.editor.original"}}
            src={{this.imageUrl}}
          /></a>
        {{#if @guides}}
          {{#if this.geometry}}
            <div aria-hidden="true" class="isbf-pinning-original__above">{{i18n
                "isbf_pinning.editor.above"
              }}</div>
            <div
              aria-hidden="true"
              class="isbf-pinning-original__boundary"
            >{{i18n "isbf_pinning.editor.visible"}}</div>
            <div aria-hidden="true" class="isbf-pinning-original__below">{{i18n
                "isbf_pinning.editor.below"
              }}</div>
          {{/if}}
        {{/if}}
      </div>
    {{/if}}
  </template>
}
