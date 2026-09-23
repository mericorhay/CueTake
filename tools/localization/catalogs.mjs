import crypto from "node:crypto";
import fs from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const directory = path.dirname(fileURLToPath(import.meta.url));
export const repositoryRoot = path.resolve(directory, "../..");
export const configPath = path.join(directory, "localization.config.json");
export const lockPath = path.join(directory, "ollama-translations.lock.json");

export async function readConfig() {
  return JSON.parse(await fs.readFile(configPath, "utf8"));
}

async function walk(current) {
  const result = [];
  for (const entry of await fs.readdir(current, { withFileTypes: true })) {
    if ([".git", ".build", "build", "DerivedData", ".localization-cache", ".wrangler", "node_modules"].includes(entry.name)) continue;
    const candidate = path.join(current, entry.name);
    if (entry.isDirectory()) result.push(...await walk(candidate));
    else if (entry.name.endsWith(".xcstrings")) result.push(candidate);
  }
  return result;
}

export async function catalogFiles() {
  return (await walk(repositoryRoot)).sort((a, b) => a.localeCompare(b));
}

export function relative(file) {
  return path.relative(repositoryRoot, file).replaceAll(path.sep, "/");
}

export async function readCatalog(file) {
  return JSON.parse(await fs.readFile(file, "utf8"));
}

export function leafUnits(localization, prefix = []) {
  if (!localization || typeof localization !== "object") return [];
  const units = [];
  if (localization.stringUnit) units.push({ path: prefix, stringUnit: localization.stringUnit });
  for (const [kind, choices] of Object.entries(localization.variations ?? {})) {
    for (const [choice, value] of Object.entries(choices)) {
      units.push(...leafUnits(value, [...prefix, "variations", kind, choice]));
    }
  }
  return units;
}

export function unitIdentifier(file, key, unitPath, source) {
  // Source text participates in the identity so a copy edit can never reuse a
  // translation generated for an older sentence with the same catalog key.
  const raw = JSON.stringify([relative(file), key, unitPath, source]);
  return crypto.createHash("sha256").update(raw).digest("hex").slice(0, 20);
}

export function translationUnits(file, catalog, sourceLocale) {
  const units = [];
  for (const [key, entry] of Object.entries(catalog.strings ?? {})) {
    const source = entry.localizations?.[sourceLocale];
    for (const leaf of leafUnits(source)) {
      units.push({
        id: unitIdentifier(file, key, leaf.path, leaf.stringUnit.value),
        file,
        key,
        comment: entry.comment ?? "",
        path: leaf.path,
        source: leaf.stringUnit.value,
      });
    }
  }
  return units;
}

export function setTranslation(catalog, unit, locale, value) {
  const entry = catalog.strings[unit.key];
  entry.localizations ??= {};
  entry.localizations[locale] ??= {};
  let cursor = entry.localizations[locale];
  for (let index = 0; index < unit.path.length; index += 3) {
    const [, kind, choice] = unit.path.slice(index, index + 3);
    cursor.variations ??= {};
    cursor.variations[kind] ??= {};
    cursor.variations[kind][choice] ??= {};
    cursor = cursor.variations[kind][choice];
  }
  cursor.stringUnit = { state: "translated", value };
}

export function placeholders(value) {
  // Apple string catalogs use printf placeholders. A literal %% is significant too.
  return value.match(/%(?:\d+\$)?(?:[-+#0 ']*\d*(?:\.\d+)?)?(?:hh|h|ll|l|L|z|j|t)?[@aAcCdDeEfFgGiIosSuUxXpn%]/g) ?? [];
}

export function placeholderSignature(value) {
  return placeholders(value).sort().join("|");
}

export function protectedTermsIn(value, terms) {
  return terms.filter(term => value.includes(term));
}

export function validatePair(source, target, protectedTerms) {
  const errors = [];
  if (typeof target !== "string" || target.trim().length === 0) errors.push("empty translation");
  if (placeholderSignature(source) !== placeholderSignature(target ?? "")) errors.push("placeholder mismatch");
  if ((source.match(/\n/g) ?? []).length !== ((target ?? "").match(/\n/g) ?? []).length) errors.push("newline mismatch");
  for (const term of protectedTermsIn(source, protectedTerms)) {
    if (!target.includes(term)) errors.push(`protected term changed: ${term}`);
  }
  return errors;
}

export function appleJSON(value) {
  return `${JSON.stringify(value, null, 2).replace(/^(\s*)"((?:\\.|[^"\\])*)":/gm, '$1"$2" :')}\n`;
}

export async function atomicWrite(file, contents) {
  const temporary = `${file}.localization-${process.pid}.tmp`;
  await fs.writeFile(temporary, contents, "utf8");
  await fs.rename(temporary, file);
}

export function sha256(contents) {
  return crypto.createHash("sha256").update(contents).digest("hex");
}
