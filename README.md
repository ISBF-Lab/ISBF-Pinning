# ISBF Pinning

Native Discourse timed pins with developer-only human control and an ISBF home-feed scope.
No Core edits, database tables, upload endpoints or replacement topic infrastructure.
The homepage bar uses a read-only list endpoint and the native settings/upload APIs.
See [Pinned bar and appearance editor](docs/PINNED_BAR.md) for configuration, geometry,
permissions, compatibility and validation details.

## Contract

`PUT /t/:topic_id/status.json` keeps the native status API. Add `isbf_home_pin: true`,
`status: "pinned_globally"`, `enabled: true|false` and optional `until` with an explicit-zone
ISO timestamp. An omitted deadline means 72 hours; invalid, permanent and past dates are
rejected. Existing native future-date picker timestamps are accepted too. Successful home
requests return `isbf_home_pinning` with `can_manage`, `scoped`, `active`, `pinned_at` and
`pinned_until`. The same metadata is present in native topic-list items and topic details.
Native topic-list responses include boolean `topic_list.isbf_home_pinning_scope` so clients
must not infer ordering from the current screen or an unrelated background request.

Only the underlying User `admin` column authorizes human pinning, renewal and cancellation.
On this installation that is the developer role; renamed moderator, official memberships,
TL4 and category group moderation do not grant it. The status updater, bulk operator,
Guardian and create/edit side-channel guards enforce this independently of theme visibility.
Pin fields in human posting/edit requests are rejected, including custom-field injection.
Internal native system-user category-definition creation is retained.

## Ordering and timing

The boolean Topic custom field `isbf_home_pin` marks newly scoped pins. Native `pinned_at`,
`pinned_globally` and `pinned_until` provide timing and the existing `UnpinTopic` job. Pins
are ordered by pin time in the dedicated bar. The unfiltered Latest feed keeps all original
posts in creation-date and ID descending order before LIMIT/OFFSET, including pinned posts.
Scope applies to the unfiltered Latest feed, the actual Official category Latest route and
positive `isbf-official:<actual-id>` native filters (including campus/type selections).
Marketplace and Teamup home filters compose before pagination. Scoped pins ignore personal
read/cleared state. Other category/profile/search/market/team lists retain ordinary ordering;
legacy category/global pins retain native behavior outside the home feed and personal clearing
in the bar. Official category and Official filter lists retain their existing pin priority.

The current locked deadline is checked before a native expiry job acts, preventing an old
running job from undoing a renewal. Expired scoped records lose priority immediately even if
the job is delayed. Cancellation clears the scope marker. No existing pin records are migrated.

## Configuration and rollback

- `isbf_pinning_enabled`: UI capability and new home actions, default true.
- `isbf_pinning_home_actions_enabled`: new, renewed or manually cancelled home pins, default true. Set false for
  rollback while retaining developer guards, existing scoped ordering and native expiry.
- Official category reuses authoritative `academy_official_category` when available.
  `isbf_pinning_official_category_id` is an independent-plugin fallback, default zero, and
  must remain zero on the production Academy installation.

Deployment uses the reviewed merged commit as `/shared/isbf-pinning-releases/<commit>/isbf-pinning`
and the provided install helper creates only the app's plugin symlink. Save the database,
actual theme, plugins, category settings and native pin/custom-field state before deployment.
Keep this plugin installed when disabling new actions or restoring the old theme; removing it
would remove scope ordering and the custom human permission guard. Existing topics and pins
are retained on rollback.

## Verification

Run native request/query/permission/timing specs from `spec/`, and browser tests from
`test/javascripts/`, against the target Core and its locked dependencies. The bar candidate
uses Core `5a56f19ded90fe7f041222e2ad4bcdca63b9eb5a`. Companion Marketplace/Teamup/Official
integration specs are skipped when those plugins are absent and require the matching
isolated integration environment. Native test passes do not replace real-role, light/dark,
mobile-keyboard, device or user web acceptance.
