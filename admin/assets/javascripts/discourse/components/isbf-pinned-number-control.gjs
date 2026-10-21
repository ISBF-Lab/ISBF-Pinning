import Component from "@glimmer/component";
import { action } from "@ember/object";
import FKControlInput from "discourse/form-kit/components/fk/control/input";

export default class IsbfPinnedNumberControl extends Component {
  get rangeField() {
    return {
      hasExplicitType: true,
      disabled: this.args.field.disabled,
      describedBy: this.args.field.describedBy,
      error: this.args.field.error,
      id: `${this.args.field.id}-range`,
      name: this.args.field.name,
      value: this.args.field.value,
      set: this.setNumber,
    };
  }

  @action
  setNumber(value) {
    this.args.field.set(Number(value));
  }

  <template>
    <div class="isbf-pinning-editor__number">
      <FKControlInput
        aria-label={{@label}}
        max={{@max}}
        min={{@min}}
        step={{@step}}
        @field={{this.rangeField}}
        @type="range"
      />
      <FKControlInput
        max={{@max}}
        min={{@min}}
        step={{@step}}
        @field={{@field}}
        @type="number"
      />
    </div>
  </template>
}
