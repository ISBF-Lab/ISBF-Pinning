import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { array, concat, fn } from "@ember/helper";
import { action, set } from "@ember/object";
import { service } from "@ember/service";
import AdminConfigAreaCard from "discourse/admin/components/admin-config-area-card";
import SiteSettingUpload from "discourse/admin/components/site-settings/upload";
import Form from "discourse/components/form";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
import { getURLWithCDN } from "discourse/lib/get-url";
import { eq, not, or } from "discourse/truth-helpers";
import DButton from "discourse/ui-kit/d-button";
import DConditionalLoadingSpinner from "discourse/ui-kit/d-conditional-loading-spinner";
import { i18n } from "discourse-i18n";
import {
  backgroundGeometry,
  DEFAULT_APPEARANCE,
  IMAGE_SETTINGS,
  imageSetting,
  parseAppearance,
} from "discourse/plugins/isbf-pinning/discourse/lib/pinned-bar";
import IsbfPinnedBarPreview from "./isbf-pinned-bar-preview";
import IsbfPinnedColorControl from "./isbf-pinned-color-control";
import IsbfPinnedImageAdjuster from "./isbf-pinned-image-adjuster";
import IsbfPinnedNumberControl from "./isbf-pinned-number-control";

const APPEARANCE = "isbf_pinning_bar_appearance";
const DEFAULT_TOPIC = "isbf_pinning_bar_default_topic_id";
const GUIDES_KEY = "isbf-pinning-preview-guides";

export default class IsbfPinnedBarSettings extends Component {
  @service a11y;
  @service isbfPinnedBar;
  @service siteSettings;

  @tracked data;
  @tracked draft;
  @tracked settings;
  @tracked loading = true;
  @tracked mode = "light";
  @tracked mobile = false;
  @tracked expanded = false;
  @tracked guides = false;
  @tracked saved = false;
  @tracked saving = false;
  @tracked error = false;
  @tracked adjusting = false;
  @tracked previewGeometry;

  #form;

  constructor() {
    super(...arguments);
    try {
      this.guides = localStorage.getItem(GUIDES_KEY) === "true";
    } catch {
      this.guides = false;
    }
    this.isbfPinnedBar.acquire();
    this.load();
  }

  willDestroy() {
    this.isbfPinnedBar.release();
    super.willDestroy(...arguments);
  }

  get images() {
    return Object.fromEntries(
      IMAGE_SETTINGS.map((name) => [name, this.draft?.[name] || ""])
    );
  }

  get uploadFields() {
    return ["desktop", "mobile"].map((device) => {
      const name = imageSetting(this.mode, device);
      return {
        name,
        setting: this.settings?.find((setting) => setting.setting === name),
        label: i18n(`isbf_pinning.editor.${device}_image`),
      };
    });
  }

  get currentImageKey() {
    return imageSetting(this.mode, this.mobile ? "mobile" : "desktop");
  }

  get currentImageSource() {
    return (
      this.images[this.currentImageKey] ||
      this.images[imageSetting(this.mode, "desktop")]
    );
  }

  get imageTransform() {
    let adjustment = this.draft?.image_adjustments?.[this.currentImageKey];
    if (
      this.mobile &&
      !this.images[this.currentImageKey] &&
      !adjustment?.edited
    ) {
      adjustment =
        this.draft?.image_adjustments?.[imageSetting(this.mode, "desktop")];
    }
    return adjustment?.source === this.currentImageSource
      ? { scale: adjustment.scale / 100, x: adjustment.offset_x / 100 }
      : { scale: 1, x: 0 };
  }

  get adjustmentFields() {
    return [
      { key: "scale", min: 25, max: 400, step: 1 },
      { key: "offset_x", min: -399, max: 399, step: 0.1 },
    ].map((field) => ({
      ...field,
      label: i18n(`isbf_pinning.editor.image_${field.key}`),
    }));
  }

  get imageGuidance() {
    const width = this.mobile ? 900 : 1600;
    const previewWidth =
      this.previewGeometry?.width || (this.mobile ? 390 : 600);
    const headerHeight =
      this.previewGeometry?.headerHeight || (this.mobile ? 52 : 60);
    return i18n("isbf_pinning.editor.image_prompt", {
      width,
      bar_height: Math.round((width * headerHeight) / previewWidth),
    });
  }

  get numberFields() {
    return [
      { key: "border_width", min: 0, max: 4, step: 0.5 },
      { key: "opacity", min: 0, max: 1, step: 0.01 },
      { key: "x", min: 0, max: 100, step: 1 },
      { key: "y", min: -500, max: 500, step: 1 },
    ].map((field) => ({
      ...field,
      name: field.key,
      label: i18n(`isbf_pinning.editor.${field.key}`),
    }));
  }

  get colorFields() {
    return ["fill", "border"].map((key) => ({
      name: key,
      label: i18n(`isbf_pinning.editor.${key}`),
    }));
  }

  @action
  measurePreview(geometry) {
    this.previewGeometry = geometry;
  }

  @action
  async load() {
    this.loading = true;
    this.error = false;
    try {
      const result = await ajax("/admin/site_settings.json", {
        data: {
          names: [APPEARANCE, DEFAULT_TOPIC, ...IMAGE_SETTINGS].join("|"),
        },
      });
      if (this.isDestroying) {
        return;
      }
      this.settings = result.site_settings;
      const values = Object.fromEntries(
        this.settings.map((setting) => [setting.setting, setting.value])
      );
      this.data = {
        ...parseAppearance(values[APPEARANCE]),
        default_topic_id: String(values[DEFAULT_TOPIC] || 0),
        ...Object.fromEntries(
          IMAGE_SETTINGS.map((name) => [name, values[name] || ""])
        ),
        image_adjustments: Object.fromEntries(
          IMAGE_SETTINGS.map((name) => [
            name,
            {
              source: values[name] || "",
              scale: 100,
              offset_x: 0,
              edited: false,
            },
          ])
        ),
      };
      this.draft = structuredClone(this.data);
    } catch (error) {
      if (!this.isDestroying) {
        this.error = true;
        popupAjaxError(error);
      }
    } finally {
      if (!this.isDestroying) {
        this.loading = false;
      }
    }
  }

  @action
  registerForm(form) {
    this.#form = form;
  }

  @action
  async changeDraft(name, value, data) {
    this.draft = structuredClone(data);
    this.saved = false;
    if (IMAGE_SETTINGS.includes(name)) {
      this.adjusting = false;
      for (const [key, setting] of Object.entries({
        source: value,
        scale: 100,
        offset_x: 0,
        edited: false,
      })) {
        await this.#form.set(`image_adjustments.${name}.${key}`, setting);
      }
    }
  }

  @action
  async toggleAdjustment() {
    if (this.adjusting) {
      this.adjusting = false;
      return;
    }
    const base = `image_adjustments.${this.currentImageKey}`;
    if (
      this.draft.image_adjustments[this.currentImageKey].source !==
      this.currentImageSource
    ) {
      const transform = this.imageTransform;
      await this.#form.set(`${base}.source`, this.currentImageSource);
      await this.#form.set(`${base}.scale`, transform.scale * 100);
      await this.#form.set(`${base}.offset_x`, transform.x * 100);
    }
    await this.#form.set(`${base}.edited`, true);
    await this.#form.set(`${this.mode}.fit`, "contain");
    this.adjusting = true;
  }

  @action
  async adjustImage({ scale, x, y }) {
    if (this.saving) {
      return;
    }
    const base = `image_adjustments.${this.currentImageKey}`;
    await this.#form.set(`${base}.scale`, Math.round(scale * 10000) / 100);
    await this.#form.set(`${base}.offset_x`, Math.round(x * 10000) / 100);
    await this.#form.set(`${this.mode}.y`, Math.round(y * 100) / 100);
  }

  @action
  makeOpaque() {
    return this.#form.set(
      `${this.mode}.fill`,
      `${this.draft[this.mode].fill.slice(0, 7)}ff`
    );
  }

  @action
  chooseMode(mode) {
    this.adjusting = false;
    this.mode = mode;
  }

  @action
  chooseDevice(mobile) {
    this.adjusting = false;
    this.mobile = mobile;
  }

  @action
  toggleExpanded() {
    this.expanded = !this.expanded;
  }

  @action
  toggleGuides() {
    this.guides = !this.guides;
    try {
      localStorage.setItem(GUIDES_KEY, String(this.guides));
    } catch {
      // Preview aids remain usable when browser storage is unavailable.
    }
  }

  @action
  async resetMode() {
    for (const [key, value] of Object.entries(DEFAULT_APPEARANCE[this.mode])) {
      await this.#form.set(`${this.mode}.${key}`, value);
    }
    for (const device of ["desktop", "mobile"]) {
      await this.#form.set(imageSetting(this.mode, device), "");
    }
  }

  @action
  validate(data, { addError }) {
    for (const name of IMAGE_SETTINGS) {
      for (const property of this.adjustmentFields) {
        const value = data.image_adjustments[name][property.key];
        if (
          !Number.isFinite(value) ||
          value < property.min ||
          value > property.max
        ) {
          addError(`image_adjustments.${name}.${property.key}`, {
            title: property.label,
            message: i18n("isbf_pinning.editor.invalid_number", {
              min: property.min,
              max: property.max,
            }),
          });
        }
      }
    }
    for (const mode of ["light", "dark"]) {
      for (const key of ["fill", "border"]) {
        if (!/^#[\da-f]{8}$/i.test(data[mode]?.[key])) {
          addError(`${mode}.${key}`, {
            title: i18n(`isbf_pinning.editor.${key}`),
            message: i18n("isbf_pinning.editor.invalid_color"),
          });
        }
      }
      for (const property of this.numberFields) {
        const value = data[mode]?.[property.key];
        if (
          !Number.isFinite(value) ||
          value < property.min ||
          value > property.max ||
          (property.key === "border_width" && (value * 2) % 1 !== 0)
        ) {
          addError(`${mode}.${property.key}`, {
            title: property.label,
            message: i18n("isbf_pinning.editor.invalid_number", {
              min: property.min,
              max: property.max,
            }),
          });
        }
      }
    }
  }

  @action
  async save(data) {
    let values;
    this.saving = true;
    this.saved = false;
    try {
      const images = await this.#cropImages(data);
      values = {
        [APPEARANCE]: JSON.stringify({ light: data.light, dark: data.dark }),
        [DEFAULT_TOPIC]: Number(data.default_topic_id || 0),
        ...images,
      };
      await ajax("/admin/site_settings/bulk_update.json", {
        type: "PUT",
        data: {
          settings: Object.fromEntries(
            Object.entries(values).map(([name, value]) => [name, { value }])
          ),
        },
      });
    } catch (error) {
      popupAjaxError(error);
      return;
    } finally {
      this.saving = false;
    }
    Object.entries(values).forEach(([name, value]) =>
      set(this.siteSettings, name, value)
    );
    this.adjusting = false;
    await this.load();
    this.saved = true;
    this.a11y.announce(i18n("isbf_pinning.editor.saved"));
    this.isbfPinnedBar.refresh();
  }

  async #cropImages(data) {
    const images = Object.fromEntries(
      IMAGE_SETTINGS.map((name) => [name, data[name] || ""])
    );
    for (const mode of ["light", "dark"]) {
      for (const device of ["desktop", "mobile"]) {
        const name = imageSetting(mode, device);
        const adjustment = data.image_adjustments[name];
        const source =
          data[name] ||
          (adjustment.edited && data[imageSetting(mode, "desktop")]);
        if (!source) {
          continue;
        }
        const dimensions = await this.#imageDimensions(source);
        const transform =
          adjustment.source === source
            ? { scale: adjustment.scale / 100, x: adjustment.offset_x / 100 }
            : { scale: 1, x: 0 };
        const mobile = device === "mobile";
        const width = mobile ? 390 : 600;
        const geometry = backgroundGeometry({
          width,
          height: mobile ? 52 : 60,
          headerHeight: mobile ? 52 : 60,
          imageWidth: dimensions.width,
          imageHeight: dimensions.height,
          mobile,
          appearance: data[mode],
          imageTransform: transform,
        });
        const cropLeft = -geometry.image.x / geometry.image.width;
        const cropWidth = width / geometry.image.width;
        if (
          Math.abs(cropLeft) < 0.000001 &&
          Math.abs(cropWidth - 1) < 0.000001
        ) {
          images[name] = source;
          continue;
        }
        const result = await ajax("/isbf/pinning/backgrounds/crop.json", {
          type: "POST",
          data: {
            upload_url: source,
            setting_name: name,
            crop_left: cropLeft,
            crop_width: cropWidth,
          },
        });
        images[name] = result.url;
      }
    }
    return images;
  }

  #imageDimensions(source) {
    return new Promise((resolve, reject) => {
      const image = new Image();
      const timeout = setTimeout(
        () => reject(new Error(i18n("isbf_pinning.editor.image_load_error"))),
        15000
      );
      image.onload = () => {
        clearTimeout(timeout);
        resolve({ width: image.naturalWidth, height: image.naturalHeight });
      };
      image.onerror = () => {
        clearTimeout(timeout);
        reject(new Error(i18n("isbf_pinning.editor.image_load_error")));
      };
      image.src = getURLWithCDN(source);
    });
  }

  <template>
    <AdminConfigAreaCard
      class="isbf-pinning-editor"
      @heading="isbf_pinning.editor.title"
    >
      <:content>
        <DConditionalLoadingSpinner @condition={{this.loading}}>
          {{#if this.error}}
            <DButton @action={{this.load}} @label="isbf_pinning.editor.retry" />
          {{else if this.data}}
            <div class="isbf-pinning-editor__modes">
              <DButton
                aria-pressed={{if (eq this.mode "light") "true" "false"}}
                @action={{fn this.chooseMode "light"}}
                @disabled={{this.saving}}
                @label="isbf_pinning.editor.light"
              />
              <DButton
                aria-pressed={{if (eq this.mode "dark") "true" "false"}}
                @action={{fn this.chooseMode "dark"}}
                @disabled={{this.saving}}
                @label="isbf_pinning.editor.dark"
              />
            </div>
            <div class="isbf-pinning-editor__layout">
              <Form
                @data={{this.data}}
                @onRegisterApi={{this.registerForm}}
                @onSet={{this.changeDraft}}
                @onSubmit={{this.save}}
                @validate={{this.validate}}
                as |form|
              >
                <form.Field
                  @disabled={{this.saving}}
                  @format="full"
                  @name="default_topic_id"
                  @title={{i18n "isbf_pinning.editor.default_topic"}}
                  @type="select"
                  as |field|
                >
                  <field.Control @includeNone={{false}} as |select|>
                    <select.Option @value="0">{{i18n
                        "isbf_pinning.editor.first_topic"
                      }}</select.Option>
                    {{#each
                      this.isbfPinnedBar.topics key="id"
                      as |topic|
                    }}<select.Option
                        @value={{concat "" topic.id}}
                      >{{topic.title}}</select.Option>{{/each}}
                  </field.Control>
                </form.Field>
                {{#each (array this.mode) key="@identity" as |mode|}}
                  <form.Object @name={{mode}} as |appearance|>
                    {{#each this.colorFields key="name" as |property|}}
                      <appearance.Field
                        @disabled={{this.saving}}
                        @format="full"
                        @name={{property.name}}
                        @title={{property.label}}
                        @type="custom"
                        as |field|
                      >
                        <field.Control><IsbfPinnedColorControl
                            @field={{field}}
                            @label={{property.label}}
                          /></field.Control>
                      </appearance.Field>
                    {{/each}}
                    {{#each this.numberFields key="name" as |property|}}
                      <appearance.Field
                        @disabled={{this.saving}}
                        @format="full"
                        @name={{property.name}}
                        @title={{property.label}}
                        @type="custom"
                        as |field|
                      >
                        <field.Control><IsbfPinnedNumberControl
                            @field={{field}}
                            @label={{property.label}}
                            @max={{property.max}}
                            @min={{property.min}}
                            @step={{property.step}}
                          /></field.Control>
                      </appearance.Field>
                    {{/each}}
                    <appearance.Field
                      @disabled={{this.saving}}
                      @format="full"
                      @name="fit"
                      @title={{i18n "isbf_pinning.editor.fit"}}
                      @type="select"
                      as |field|
                    >
                      <field.Control @includeNone={{false}} as |select|>
                        <select.Option @value="contain">{{i18n
                            "isbf_pinning.editor.contain"
                          }}</select.Option>
                        <select.Option @value="cover">{{i18n
                            "isbf_pinning.editor.cover"
                          }}</select.Option>
                      </field.Control>
                    </appearance.Field>
                    <appearance.Field
                      @disabled={{this.saving}}
                      @format="full"
                      @name="overflow"
                      @title={{i18n "isbf_pinning.editor.overflow"}}
                      @type="checkbox"
                      as |field|
                    >
                      <field.Control />
                    </appearance.Field>
                  </form.Object>
                {{/each}}
                {{#each this.uploadFields key="name" as |upload|}}
                  <form.Field
                    @disabled={{this.saving}}
                    @format="full"
                    @name={{upload.name}}
                    @title={{upload.label}}
                    @type="custom"
                    as |field|
                  >
                    <field.Control><SiteSettingUpload
                        @changeValueCallback={{field.set}}
                        @disabled={{field.disabled}}
                        @setting={{upload.setting}}
                        @value={{field.value}}
                      /></field.Control>
                  </form.Field>
                {{/each}}
                {{#if this.adjusting}}
                  <form.Object @name="image_adjustments" as |adjustments|>
                    <adjustments.Object
                      @name={{this.currentImageKey}}
                      as |image|
                    >
                      {{#each this.adjustmentFields key="key" as |property|}}
                        <image.Field
                          @disabled={{this.saving}}
                          @format="full"
                          @name={{property.key}}
                          @title={{property.label}}
                          @type="custom"
                          as |field|
                        >
                          <field.Control><IsbfPinnedNumberControl
                              @field={{field}}
                              @label={{property.label}}
                              @max={{property.max}}
                              @min={{property.min}}
                              @step={{property.step}}
                            /></field.Control>
                        </image.Field>
                      {{/each}}
                    </adjustments.Object>
                  </form.Object>
                {{/if}}
                <form.Submit @label="isbf_pinning.editor.save" />
                <DButton
                  @action={{this.resetMode}}
                  @disabled={{this.saving}}
                  @label="isbf_pinning.editor.reset"
                />
                {{#if this.saved}}<p>{{i18n
                      "isbf_pinning.editor.saved"
                    }}</p>{{/if}}
              </Form>
              <aside class="isbf-pinning-editor__preview">
                <div class="isbf-pinning-editor__preview-controls">
                  <DButton
                    aria-pressed={{if this.mobile "false" "true"}}
                    @action={{fn this.chooseDevice false}}
                    @disabled={{this.saving}}
                    @label="isbf_pinning.editor.desktop"
                  />
                  <DButton
                    aria-pressed={{if this.mobile "true" "false"}}
                    @action={{fn this.chooseDevice true}}
                    @disabled={{this.saving}}
                    @label="isbf_pinning.editor.mobile"
                  />
                  <DButton
                    aria-pressed={{if this.expanded "true" "false"}}
                    @action={{this.toggleExpanded}}
                    @disabled={{this.saving}}
                    @label="isbf_pinning.editor.expanded"
                  />
                  <DButton
                    aria-pressed={{if this.guides "true" "false"}}
                    @action={{this.toggleGuides}}
                    @disabled={{this.saving}}
                    @label="isbf_pinning.editor.guides"
                  />
                  <DButton
                    aria-pressed={{if this.adjusting "true" "false"}}
                    @action={{this.toggleAdjustment}}
                    @disabled={{or this.saving (not this.currentImageSource)}}
                    @label="isbf_pinning.editor.adjust_image"
                  />
                  <DButton
                    @action={{this.makeOpaque}}
                    @disabled={{this.saving}}
                    @label="isbf_pinning.editor.opaque_fill"
                  />
                </div>
                {{#if this.guides}}<p>{{i18n
                      "isbf_pinning.editor.guides_help"
                    }}</p>{{/if}}
                {{#if this.isbfPinnedBar.topics.length}}
                  <IsbfPinnedBarPreview
                    @appearance={{this.draft}}
                    @defaultTopicId={{this.draft.default_topic_id}}
                    @expanded={{this.expanded}}
                    @guides={{this.guides}}
                    @images={{this.images}}
                    @imageTransform={{this.imageTransform}}
                    @mobile={{this.mobile}}
                    @mode={{this.mode}}
                    @onGeometry={{this.measurePreview}}
                    @onToggle={{this.toggleExpanded}}
                    @topics={{this.isbfPinnedBar.topics}}
                  />
                  {{#if this.adjusting}}
                    <IsbfPinnedImageAdjuster
                      @appearance={{this.draft}}
                      @defaultTopicId={{this.draft.default_topic_id}}
                      @disabled={{this.saving}}
                      @images={{this.images}}
                      @imageTransform={{this.imageTransform}}
                      @mobile={{this.mobile}}
                      @mode={{this.mode}}
                      @onChange={{this.adjustImage}}
                      @topics={{this.isbfPinnedBar.topics}}
                    />
                  {{/if}}
                {{else}}
                  <p>{{i18n "isbf_pinning.editor.no_topics"}}</p>
                {{/if}}
                <h3>{{i18n "isbf_pinning.editor.image_requirements"}}</h3>
                <p>{{i18n "isbf_pinning.editor.image_help"}}</p>
                <p
                  class="isbf-pinning-editor__image-guidance"
                >{{this.imageGuidance}}</p>
              </aside>
            </div>
          {{/if}}
        </DConditionalLoadingSpinner>
      </:content>
    </AdminConfigAreaCard>
  </template>
}
