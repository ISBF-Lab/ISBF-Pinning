# Approved pinned-bar spacing and image composition

Approved by the user with “就按这个改 注意圆角框线不要漏了” after the generated three-column comparison. This approval covers the home pinned-bar region, collapsed/expanded states, desktop/mobile sizing and image spacing. It does not establish a new site-wide design or approve other page regions.

Reference: [approved comparison](pinned-bar-spacing-20261022.png), SHA-256 `50ab584b9e75ea4e82e8d65297970b104362043d51f6f1a6e3fd8b934a8467f5`.

Implementation baseline: Pinning `9313b0097cac54d65b1a54e9908581441ae83cc1`, existing deployed release `f72010bc6d9f4d75488fe504d9d13784a1d87bf3`. The isolated Core source is `5a56f19ded90fe7f041222e2ad4bcdca63b9eb5a`. The reference is a design mockup, never an executable replacement for the active database theme.

Rules:

- Without an image, the rounded bar has zero external vertical spacing and meets the surrounding content dividers.
- With an image and overflow enabled, reserve exactly the actual image extension above/below the bar. The image reaches the outer dividers; the compact header keeps its native height. Expanding the list leaves image scale and anchor unchanged.
- Reuse `--isbf-v2-radius-md` (existing 16px fallback), theme text/muted/focus variables and the current border settings. Layer order: image, fill, interactive content, rounded border. A 100% opaque fill masks artwork inside the bar.
- Manual editing uses native `d-pointer-drag`, `DResizeHandles`, DButton and FormKit numeric controls. Corner scaling preserves aspect ratio. The image can cross either horizontal edge; saving creates a new PNG with the excess pixels removed. Keep the source upload unchanged during this operation.
- Draft guides, transform handles and transparency checkerboards belong only to the admin editor. They never enter the home feed or saved pixels. No new global tokens or unrelated theme fields.
- Image-making advice reserves a transparent central strip, places artwork above/below/around it, and leaves the actual fill, rounded outline, title, avatars and buttons to the site. Canvas height follows the artwork instead of a fixed recommended ratio.

The later user instruction “修改完直接上线 无需复测” authorizes this scoped release without another user acceptance cycle. Necessary build/security checks and fresh release backups remain required.
