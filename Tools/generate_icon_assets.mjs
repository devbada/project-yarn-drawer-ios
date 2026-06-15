import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const scriptDirectory = path.dirname(fileURLToPath(import.meta.url));
const iosRoot = path.resolve(scriptDirectory, "..");
const repoRoot = path.resolve(iosRoot, "..");
const spritePath = path.join(repoRoot, "design-system/assets/icons.svg");
const assetRoot = path.join(iosRoot, "YarnDrawer/Resources/Assets.xcassets");
const sprite = fs.readFileSync(spritePath, "utf8");

const symbols = [...sprite.matchAll(
  /<symbol id="i-([^"]+)" viewBox="([^"]+)">([\s\S]*?)<\/symbol>/g
)];

for (const [, name, viewBox, body] of symbols) {
  const assetName = `Icon${name.split("-").map((part) =>
    part.charAt(0).toUpperCase() + part.slice(1)
  ).join("")}`;
  const directory = path.join(assetRoot, `${assetName}.imageset`);
  const fileName = `${assetName}.svg`;
  fs.mkdirSync(directory, { recursive: true });
  fs.writeFileSync(
    path.join(directory, fileName),
    `<svg xmlns="http://www.w3.org/2000/svg" viewBox="${viewBox}" fill="none" stroke="#000000" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round">\n${body.trim()}\n</svg>\n`
  );
  fs.writeFileSync(
    path.join(directory, "Contents.json"),
    JSON.stringify({
      images: [{ filename: fileName, idiom: "universal" }],
      info: { author: "xcode", version: 1 },
      properties: { "preserves-vector-representation": true, "template-rendering-intent": "template" }
    }, null, 2) + "\n"
  );
}

fs.writeFileSync(
  path.join(assetRoot, "Contents.json"),
  JSON.stringify({ info: { author: "xcode", version: 1 } }, null, 2) + "\n"
);

console.log(`Generated ${symbols.length} icon assets.`);
