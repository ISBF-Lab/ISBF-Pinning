import { withPluginApi } from "discourse/lib/plugin-api";
import IsbfHomePinnedBar from "../components/isbf-home-pinned-bar";

export default {
  name: "isbf-pinned-bar",
  initialize() {
    withPluginApi((api) =>
      api.renderInOutlet("before-topic-list", IsbfHomePinnedBar)
    );
  },
};
