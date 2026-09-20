// Tailwind plugin that exposes Heroicons as `hero-*` utilities.
//
// Reads SVGs from the `heroicons` npm package (`24/{outline,solid}`)
// at build time and registers one utility per icon, e.g. `hero-x-mark` and
// `hero-x-mark-solid`. The icon inherits `currentColor` via a CSS mask, so it
// blends with daisyUI semantic colors. Sizing comes from the element itself
// (e.g. `size-4`), which `<.icon>` in `CoreComponents` already provides.
//
// Usage in HEEx: `<.icon name="hero-x-mark" class="size-4" />`
const plugin = require("tailwindcss/plugin");
const fs = require("fs");
const path = require("path");

const outlineDir = path.join(__dirname, "../node_modules/heroicons/24/outline");
const solidDir = path.join(__dirname, "../node_modules/heroicons/24/solid");

function loadIcons(dir, suffix) {
  const values = {};
  if (!fs.existsSync(dir)) return values;
  for (const file of fs.readdirSync(dir)) {
    if (!file.endsWith(".svg")) continue;
    const name = path.basename(file, ".svg") + suffix;
    const svg = fs
      .readFileSync(path.join(dir, file), "utf8")
      .replace(/\s+/g, " ")
      .trim();
    values[name] = `url("data:image/svg+xml,${encodeURIComponent(svg)}")`;
  }
  return values;
}

module.exports = plugin(function ({ matchUtilities }) {
  const values = {
    ...loadIcons(outlineDir, ""),
    ...loadIcons(solidDir, "-solid"),
  };

  matchUtilities(
    {
      hero: (value) => ({
        "--hero-icon": value,
        "-webkit-mask-image": "var(--hero-icon)",
        "mask-image": "var(--hero-icon)",
        "-webkit-mask-repeat": "no-repeat",
        "mask-repeat": "no-repeat",
        "-webkit-mask-position": "center",
        "mask-position": "center",
        "-webkit-mask-size": "contain",
        "mask-size": "contain",
        "background-color": "currentColor",
        display: "inline-block",
        "flex-shrink": "0",
      }),
    },
    { values }
  );
});
