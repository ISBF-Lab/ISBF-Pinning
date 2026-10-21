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
import { eq } from "discourse/truth-helpers";
import DButton from "discourse/ui-kit/d-button";
import DConditionalLoadingSpinner from "discourse/ui-kit/d-conditional-loading-spinner";
import { i18n } from "discourse-i18n";
import {
  DEFAULT_APPEARANCE,
  IMAGE_SETTINGS,
  imageSetting,
  parseAppearance,
} from "discourse/plugins/isbf-pinning/discourse/lib/pinned-bar";
import IsbfPinnedBarPreview from "./isbf-pinned-bar-preview";
import IsbfPinnedColorControl from "./isbf-pinned-color-control";
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
  changeDraft(name, value, data) {
    this.draft = structuredClone(data);
    this.saved = false;
  }

  @action
  chooseMode(mode) {
    this.mode = mode;
  }

  @action
  chooseDevice(mobile) {
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
    const values = {
      [APPEARANCE]: JSON.stringify({ light: data.light, dark: data.dark }),
      [DEFAULT_TOPIC]: Number(data.default_topic_id || 0),
      ...Object.fromEntries(
        IMAGE_SETTINGS.map((name) => [name, data[name] || ""])
      ),
    };
    this.saving = true;
    this.saved = false;
    try {
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
    this.saved = true;
    this.a11y.announce(i18n("isbf_pinning.editor.saved"));
    this.isbfPinnedBar.refresh();
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
                @label="isbf_pinning.editor.light"
              />
              <DButton
                aria-pressed={{if (eq this.mode "dark") "true" "false"}}
                @action={{fn this.chooseMode "dark"}}
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
                    @label="isbf_pinning.editor.desktop"
                  />
                  <DButton
                    aria-pressed={{if this.mobile "true" "false"}}
                    @action={{fn this.chooseDevice true}}
                    @label="isbf_pinning.editor.mobile"
                  />
                  <DButton
                    aria-pressed={{if this.expanded "true" "false"}}
                    @action={{this.toggleExpanded}}
                    @label="isbf_pinning.editor.expanded"
                  />
                  <DButton
                    aria-pressed={{if this.guides "true" "false"}}
                    @action={{this.toggleGuides}}
                    @label="isbf_pinning.editor.guides"
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
                    @mobile={{this.mobile}}
                    @mode={{this.mode}}
                    @onToggle={{this.toggleExpanded}}
                    @topics={{this.isbfPinnedBar.topics}}
                  />
                {{else}}
                  <p>{{i18n "isbf_pinning.editor.no_topics"}}</p>
                {{/if}}
                <h3>{{i18n "isbf_pinning.editor.image_requirements"}}</h3>
                <p>{{i18n "isbf_pinning.editor.image_help"}}</p>
              </aside>
            </div>
          {{/if}}
        </DConditionalLoadingSpinner>
      </:content>
    </AdminConfigAreaCard>
  </template>
}
