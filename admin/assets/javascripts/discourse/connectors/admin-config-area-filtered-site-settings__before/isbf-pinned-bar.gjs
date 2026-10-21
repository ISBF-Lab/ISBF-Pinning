import Component from "@glimmer/component";
import { service } from "@ember/service";
import IsbfPinnedBarSettings from "../../components/isbf-pinned-bar-settings";

export default class IsbfPinnedBarConnector extends Component {
  @service currentUser;
  @service router;

  get visible() {
    return (
      this.currentUser?.admin &&
      this.router.currentRouteName === "adminConfig.interface.settings"
    );
  }

  <template>{{#if this.visible}}<IsbfPinnedBarSettings />{{/if}}</template>
}
