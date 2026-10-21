import Component from "@glimmer/component";
import { service } from "@ember/service";
import IsbfPinnedBar from "./isbf-pinned-bar";

export default class IsbfHomePinnedBar extends Component {
  @service router;
  @service site;

  get visible() {
    const path =
      this.router.currentURL?.split(/[?#]/)[0].replace(/\/$/, "") || "/";
    return this.site.isbf_pinning?.enabled && ["/", "/latest"].includes(path);
  }

  <template>{{#if this.visible}}<IsbfPinnedBar />{{/if}}</template>
}
