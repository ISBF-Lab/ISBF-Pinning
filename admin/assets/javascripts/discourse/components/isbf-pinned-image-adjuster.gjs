import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { on } from "@ember/modifier";
import { action } from "@ember/object";
import { trustHTML } from "@ember/template";
import DButton from "discourse/ui-kit/d-button";
import DResizeHandles from "discourse/ui-kit/d-resize-handles";
import dPointerDrag from "discourse/ui-kit/modifiers/d-pointer-drag";
import { i18n } from "discourse-i18n";
import IsbfPinnedBar from "discourse/plugins/isbf-pinning/discourse/components/isbf-pinned-bar";

const clamp = (value, min, max) => Math.max(min, Math.min(max, value));

export default class IsbfPinnedImageAdjuster extends Component {
  @tracked geometry;

  directions = ["nw", "ne", "se", "sw"];

  #move;

  get appearance() {
    return this.args.appearance[this.args.mode];
  }

  get selectionStyle() {
    const geometry = this.geometry;
    if (!geometry) {
      return undefined;
    }
    const image = geometry.image;
    return trustHTML(
      `width:${image.width}px;height:${image.height}px;inset-inline-start:${image.x}px;top:calc(50% + ${image.y - geometry.headerHeight / 2}px)`
    );
  }

  @action
  measure(geometry) {
    this.geometry = geometry;
  }

  @action
  startMove() {
    if (this.args.disabled || !this.geometry) {
      return false;
    }
    this.#move = {
      transform: { ...this.args.imageTransform },
      y: this.appearance.y,
    };
  }

  @action
  moveImage(event, info) {
    if (!this.#move || !this.geometry) {
      return;
    }
    this.#change({
      ...this.#move.transform,
      x: this.#move.transform.x + info.delta.x / this.geometry.width,
      y: this.#move.y + info.delta.y,
    });
  }

  @action
  endMove() {
    this.#move = null;
  }

  @action
  cancelMove() {
    if (this.#move) {
      this.args.onChange({ ...this.#move.transform, y: this.#move.y });
    }
    this.#move = null;
  }

  @action
  startResize(direction, { session }) {
    if (this.args.disabled || !this.geometry) {
      return false;
    }
    Object.assign(session, {
      geometry: this.geometry,
      transform: { ...this.args.imageTransform },
      y: this.appearance.y,
    });
  }

  @action
  resizeImage(direction, { delta, session }) {
    const { geometry, transform, y } = session;
    const east = direction.includes("e");
    const south = direction.includes("s");
    const horizontal = (delta.x * (east ? 1 : -1)) / geometry.image.width;
    const vertical = (delta.y * (south ? 1 : -1)) / geometry.image.height;
    const change =
      Math.abs(horizontal) > Math.abs(vertical) ? horizontal : vertical;
    const scale = clamp(transform.scale * (1 + change), 0.25, 4);
    const factor = scale / transform.scale;
    const width = geometry.image.width * factor;
    const height = geometry.image.height * factor;
    const left = geometry.image.x + (east ? 0 : geometry.image.width - width);
    this.#change({
      scale,
      x:
        (left - ((geometry.width - width) * this.appearance.x) / 100) /
        geometry.width,
      y: y + ((height - geometry.image.height) * (south ? 1 : -1)) / 2,
    });
  }

  @action
  cancelResize(direction, { session }) {
    if (session.transform) {
      this.args.onChange({ ...session.transform, y: session.y });
    }
  }

  @action
  moveWithKeyboard(event) {
    const distance = event.shiftKey ? 10 : 1;
    const deltas = {
      ArrowLeft: [-distance, 0],
      ArrowRight: [distance, 0],
      ArrowUp: [0, -distance],
      ArrowDown: [0, distance],
    };
    const delta = deltas[event.key];
    if (!delta || !this.geometry || this.args.disabled) {
      return;
    }
    event.preventDefault();
    this.#change({
      ...this.args.imageTransform,
      x: this.args.imageTransform.x + delta[0] / this.geometry.width,
      y: this.appearance.y + delta[1],
    });
  }

  #change(transform) {
    const width =
      this.geometry.image.width *
      (transform.scale / this.geometry.transformScale);
    const base = ((this.geometry.width - width) * this.appearance.x) / 100;
    const left = clamp(
      base + transform.x * this.geometry.width,
      1 - width,
      this.geometry.width - 1
    );
    this.args.onChange({
      scale: clamp(transform.scale, 0.25, 4),
      x: (left - base) / this.geometry.width,
      y: clamp(transform.y, -500, 500),
    });
  }

  <template>
    <div class="isbf-pinning-image-editor">
      <IsbfPinnedBar
        @appearance={{@appearance}}
        @defaultTopicId={{@defaultTopicId}}
        @expanded={{false}}
        @images={{@images}}
        @imageTransform={{@imageTransform}}
        @mobile={{@mobile}}
        @mode={{@mode}}
        @onGeometry={{this.measure}}
        @topics={{@topics}}
      />
      {{#if this.geometry}}
        <div
          class="isbf-pinning-image-editor__selection"
          style={{this.selectionStyle}}
        >
          <DButton
            aria-label={{i18n "isbf_pinning.editor.move_image"}}
            class="isbf-pinning-image-editor__move"
            @disabled={{@disabled}}
            {{on "keydown" this.moveWithKeyboard}}
            {{dPointerDrag
              onDragStart=this.startMove
              onDrag=this.moveImage
              onDragEnd=this.endMove
              onDragCancel=this.cancelMove
              threshold=3
            }}
          />
          <DResizeHandles
            @directions={{this.directions}}
            @handleClass="isbf-pinning-image-editor__handle"
            @onResize={{this.resizeImage}}
            @onResizeCancel={{this.cancelResize}}
            @onResizeStart={{this.startResize}}
          />
        </div>
      {{/if}}
    </div>
    <p>{{i18n "isbf_pinning.editor.adjust_help"}}</p>
  </template>
}
