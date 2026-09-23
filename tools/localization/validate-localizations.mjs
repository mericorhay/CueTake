#!/usr/bin/env node
import fs from "node:fs/promises";
import path from "node:path";
import {
  catalogFiles,
  leafUnits,
  lockPath,
  protectedTermsIn,
  readCatalog,
  readConfig,
  relative,
  repositoryRoot,
  sha256,
  validatePair,
} from "./catalogs.mjs";

const config = await readConfig();
const strict = process.argv.includes("--strict");
const verifyLock = process.argv.includes("--verify-lock");
const errors = [];
const warnings = [];
let stringCount = 0;
let leafCount = 0;
const coverage = Object.fromEntries(config.requiredLocales.map(locale => [locale, 0]));

for (const file of await catalogFiles()) {
  const catalog = await readCatalog(file);
  const name = relative(file);
  if (catalog.sourceLanguage !== config.sourceLocale) {
    errors.push(`${name}: sourceLanguage must be ${config.sourceLocale}`);
  }

  for (const [key, entry] of Object.entries(catalog.strings ?? {})) {
    stringCount += 1;
    const sourceLocalization = entry.localizations?.[config.sourceLocale];
    const sourceLeaves = leafUnits(sourceLocalization);
    if (sourceLeaves.length === 0) {
      errors.push(`${name} :: ${key}: missing ${config.sourceLocale} source`);
      continue;
    }
    leafCount += sourceLeaves.length;
    for (const sourceLeaf of sourceLeaves) {
      const prose = sourceLeaf.stringUnit.value.replaceAll(/suflör/gi, "");
      if (/[çğıİöşüÇĞÖŞÜ]/.test(prose)) {
        errors.push(`${name} :: ${key} [${config.sourceLocale}]: source copy appears to be Turkish`);
      }
    }

    for (const locale of config.requiredLocales) {
      const targetLeaves = leafUnits(entry.localizations?.[locale]);
      if (targetLeaves.length === 0) {
        errors.push(`${name} :: ${key}: missing ${locale}`);
        continue;
      }
      coverage[locale] += targetLeaves.length;
      for (const leaf of targetLeaves) {
        if (leaf.stringUnit.state !== "translated") {
          errors.push(`${name} :: ${key} [${locale}]: state is ${leaf.stringUnit.state ?? "missing"}`);
        }
      }

      // Generated languages mirror the source leaf structure exactly. Turkish predates
      // this pipeline and may intentionally omit plural categories unsupported by Turkish.
      if (config.generatedLocales.includes(locale)) {
        const sourcePaths = sourceLeaves.map(unit => JSON.stringify(unit.path)).sort().join("|");
        const targetPaths = targetLeaves.map(unit => JSON.stringify(unit.path)).sort().join("|");
        if (sourcePaths !== targetPaths) errors.push(`${name} :: ${key} [${locale}]: variation shape mismatch`);

        for (const sourceLeaf of sourceLeaves) {
          const targetLeaf = targetLeaves.find(candidate => JSON.stringify(candidate.path) === JSON.stringify(sourceLeaf.path));
          if (!targetLeaf) continue;
          for (const issue of validatePair(sourceLeaf.stringUnit.value, targetLeaf.stringUnit.value, config.protectedTerms)) {
            errors.push(`${name} :: ${key} [${locale}]: ${issue}`);
          }
          const source = sourceLeaf.stringUnit.value;
          const target = targetLeaf.stringUnit.value;
          if (source === target && /[A-Za-z]{4}/.test(source) && protectedTermsIn(source, config.protectedTerms).length === 0) {
            warnings.push(`${name} :: ${key} [${locale}]: unchanged from source`);
          }
        }
      }
    }
  }
}

const project = await fs.readFile(path.join(repositoryRoot, "CueTake.xcodeproj/project.pbxproj"), "utf8");
for (const locale of config.requiredLocales) {
  const regionPattern = new RegExp(`knownRegions\\s*=\\s*\\([\\s\\S]*?\\b${locale.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}\\b[\\s\\S]*?\\);`);
  if (!regionPattern.test(project)) errors.push(`Xcode knownRegions is missing ${locale}`);
}

if (verifyLock) {
  let lock;
  try { lock = JSON.parse(await fs.readFile(lockPath, "utf8")); }
  catch { errors.push("missing or unreadable tools/localization/ollama-translations.lock.json"); }
  if (lock) {
    if (lock.modelBytes > config.maximumModelBytes) errors.push("Ollama lock exceeds the configured model memory limit");
    for (const locale of config.generatedLocales) {
      if (!lock.generatedLocales?.includes(locale)) errors.push(`Ollama lock does not cover ${locale}`);
    }
    for (const file of await catalogFiles()) {
      const name = relative(file);
      const actual = sha256(await fs.readFile(file));
      if (lock.catalogs?.[name]?.sha256 !== actual) errors.push(`${name}: catalog differs from Ollama lock`);
    }
  }
}

console.log(`Localization coverage: ${stringCount} strings / ${leafCount} source units`);
for (const locale of config.requiredLocales) console.log(`  ${locale}: ${coverage[locale]} localized units`);
if (warnings.length) {
  console.warn(`Warnings (${warnings.length}):`);
  for (const warning of warnings.slice(0, 30)) console.warn(`  - ${warning}`);
  if (warnings.length > 30) console.warn(`  ... ${warnings.length - 30} more`);
}
if (errors.length) {
  console.error(`Errors (${errors.length}):`);
  for (const error of errors.slice(0, 100)) console.error(`  - ${error}`);
  if (errors.length > 100) console.error(`  ... ${errors.length - 100} more`);
  process.exitCode = 1;
} else {
  console.log("Localization validation passed.");
}

if (strict && warnings.length) {
  // Warnings identify text that deserves linguistic review but do not block shipping:
  // product names and shared technical vocabulary are often identical across languages.
  console.log("Strict structural checks passed; linguistic warnings remain advisory.");
}
