import Component from "@glimmer/component";
import { action } from "@ember/object";
import FKControlInput from "discourse/form-kit/components/fk/control/input";
import { i18n } from "discourse-i18n";

export default class IsbfPinnedColorControl extends Component {
  get color() {
    return /^#[\da-f]{8}$/i.test(this.args.field.value)
      ? this.args.field.value
      : "#00000000";
  }

  get pickerField() {
    return {
      hasExplicitType: true,
      disabled: this.args.field.disabled,
      describedBy: this.args.field.describedBy,
      error: this.args.field.error,
      id: `${this.args.field.id}-picker`,
      value: this.color.slice(0, 7),
      set: this.pickColor,
    };
  }

  get alphaField() {
    return {
      hasExplicitType: true,
      disabled: this.args.field.disabled,
      describedBy: this.args.field.describedBy,
      error: this.args.field.error,
      id: `${this.args.field.id}-alpha`,
      value: Math.round((parseInt(this.color.slice(7), 16) / 255) * 100),
      set: this.setAlpha,
    };
  }

  @action
  pickColor(color) {
    this.args.field.set(`${color}${this.color.slice(7)}`);
  }

  @action
  setAlpha(alpha) {
    this.args.field.set(
      `${this.color.slice(0, 7)}${Math.round((Number(alpha) * 255) / 100)
        .toString(16)
        .padStart(2, "0")}`
    );
  }

  <template>
    <div class="isbf-pinning-editor__color">
      <FKControlInput
        aria-label={{@label}}
        @field={{this.pickerField}}
        @type="color"
      />
      <FKControlInput
        maxlength="9"
        pattern="#[0-9a-fA-F]{8}"
        @field={{@field}}
      />
      <FKControlInput
        aria-label={{i18n "isbf_pinning.editor.color_alpha"}}
        max="100"
        min="0"
        step="1"
        @field={{this.alphaField}}
        @type="range"
      />
      <span>{{this.alphaField.value}}%</span>
    </div>
  </template>
}
