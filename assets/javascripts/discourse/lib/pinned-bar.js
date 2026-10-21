const common = {
  border_width: 1,
  opacity: 1,
  x: 50,
  y: 0,
  fit: "contain",
  overflow: true,
};

export const DEFAULT_APPEARANCE = Object.freeze({
  light: Object.freeze({ ...common, fill: "#f5f7faff", border: "#152c4624" }),
  dark: Object.freeze({ ...common, fill: "#192329ff", border: "#a0b4c426" }),
});

export const IMAGE_SETTINGS = ["light", "dark"].flatMap((mode) =>
  ["desktop", "mobile"].map((device) => imageSetting(mode, device))
);

export function imageSetting(mode, device) {
  return `isbf_pinning_bar_${mode}_${device}_image`;
}

export function parseAppearance(value) {
  let parsed;
  try {
    parsed = typeof value === "string" ? JSON.parse(value) : value;
  } catch {
    parsed = null;
  }
  return Object.fromEntries(
    ["light", "dark"].map((mode) => {
      const result = { ...DEFAULT_APPEARANCE[mode] };
      const candidate = parsed?.[mode];
      for (const key of ["fill", "border"]) {
        if (/^#[\da-f]{8}$/i.test(candidate?.[key])) {
          result[key] = candidate[key];
        }
      }
      for (const [key, min, max] of [
        ["border_width", 0, 4],
        ["opacity", 0, 1],
        ["x", 0, 100],
        ["y", -500, 500],
      ]) {
        const number = candidate?.[key];
        if (typeof number === "number" && Number.isFinite(number)) {
          result[key] = Math.max(min, Math.min(max, number));
        }
      }
      if (["contain", "cover"].includes(candidate?.fit)) {
        result.fit = candidate.fit;
      }
      if (typeof candidate?.overflow === "boolean") {
        result.overflow = candidate.overflow;
      }
      return [mode, result];
    })
  );
}

export function backgroundGeometry({
  width,
  height,
  headerHeight,
  imageWidth,
  imageHeight,
  mobile,
  appearance,
  imageTransform,
}) {
  if (
    ![width, height, headerHeight, imageWidth, imageHeight].every(
      (n) => Number.isFinite(n) && n > 0
    )
  ) {
    return null;
  }
  const referenceHeight = width * (mobile ? 320 / 900 : 400 / 1600);
  const fitScale =
    appearance.fit === "cover"
      ? Math.max(width / imageWidth, referenceHeight / imageHeight)
      : width / imageWidth;
  const scale = fitScale * (imageTransform?.scale || 1);
  const image = {
    width: imageWidth * scale,
    height: imageHeight * scale,
    x:
      ((width - imageWidth * scale) * appearance.x) / 100 +
      width * (imageTransform?.x || 0),
    y: (headerHeight - imageHeight * scale) / 2 + appearance.y,
  };
  return {
    width,
    height,
    headerHeight,
    transformScale: imageTransform?.scale || 1,
    imageWidth,
    imageHeight,
    image,
    scale,
    above: Math.max(0, -image.y),
    below: Math.max(0, image.y + image.height - height),
    visible: {
      x: Math.max(0, -image.x / scale),
      y: Math.min(imageHeight, Math.max(0, -image.y / scale)),
      right: Math.min(imageWidth, (width - image.x) / scale),
      bottom: Math.max(0, Math.min(imageHeight, (height - image.y) / scale)),
    },
  };
}

export function activeTopics(topics, now = Date.now()) {
  return (topics || []).filter((topic) => {
    const pin = topic.isbf_home_pinning;
    if (pin?.scoped) {
      return pin.active && Date.parse(pin.pinned_until) > now;
    }
    return (
      topic.pinned &&
      topic.pinned_globally &&
      (!topic.pinned_until || Date.parse(topic.pinned_until) > now)
    );
  });
}

export function selectedTopic(topics, topicId) {
  return (
    topics.find((topic) => Number(topic.id) === Number(topicId)) || topics[0]
  );
}

export function uniqueAuthors(topics) {
  const authors = new Map();
  for (const topic of topics) {
    const author = topic.isbf_pin_author;
    if (Number.isSafeInteger(author?.id) && !authors.has(author.id)) {
      authors.set(author.id, author);
    }
  }
  return [...authors.values()];
}

export function excerptText(value) {
  if (!value) {
    return "";
  }
  const fragment = new DOMParser().parseFromString(String(value), "text/html");
  fragment
    .querySelectorAll("script, style, img, video, iframe")
    .forEach((node) => node.remove());
  return fragment.body.textContent.replace(/\s+/g, " ").trim();
}
