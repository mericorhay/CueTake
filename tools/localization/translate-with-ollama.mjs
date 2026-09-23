#!/usr/bin/env node
import fs from "node:fs/promises";
import path from "node:path";
import {
  appleJSON,
  atomicWrite,
  catalogFiles,
  lockPath,
  readCatalog,
  readConfig,
  relative,
  repositoryRoot,
  setTranslation,
  sha256,
  translationUnits,
  validatePair,
} from "./catalogs.mjs";

const config = await readConfig();
const localeArgument = process.argv.find(argument => argument.startsWith("--locale="))?.split("=")[1];
const locale = localeArgument ?? config.generatedLocales[0];
const refresh = process.argv.includes("--refresh");
const discardCache = process.argv.includes("--discard-cache");
const dryRun = process.argv.includes("--dry-run");
if (!config.generatedLocales.includes(locale)) throw new Error(`${locale} is not a generated locale`);

const endpoint = config.ollamaURL.replace(/\/$/, "");
const timeout = config.requestTimeoutMinutes * 60_000;
const cacheDirectory = path.join(repositoryRoot, ".localization-cache");
const cacheFile = path.join(cacheDirectory, `${locale}.json`);
await fs.mkdir(cacheDirectory, { recursive: true });

async function ollama(pathname, body) {
  const response = await fetch(`${endpoint}${pathname}`, {
    method: body ? "POST" : "GET",
    headers: body ? { "content-type": "application/json" } : undefined,
    body: body ? JSON.stringify(body) : undefined,
    signal: AbortSignal.timeout(timeout),
  });
  if (!response.ok) throw new Error(`Ollama ${pathname} returned ${response.status}: ${await response.text()}`);
  return response.json();
}

const tags = await ollama("/api/tags");
const installed = new Map((tags.models ?? []).map(model => [model.name, model]));
const modelName = config.modelPreferences.find(name => installed.has(name) && installed.get(name).size <= config.maximumModelBytes);
if (!modelName) {
  const choices = [...installed.values()].map(model => `${model.name} (${(model.size / 2 ** 30).toFixed(1)} GiB)`).join(", ") || "none";
  throw new Error(`No preferred Ollama model fits the ${(config.maximumModelBytes / 2 ** 30).toFixed(0)} GiB limit. Installed: ${choices}`);
}
const model = installed.get(modelName);
console.log(`Ollama model: ${modelName} (${(model.size / 2 ** 30).toFixed(1)} GiB on disk)`);
console.log(`Memory controls: one sequential request, context ${config.options.num_ctx}, batch ${config.options.num_batch}`);

const catalogs = new Map();
const allUnits = [];
for (const file of await catalogFiles()) {
  const catalog = await readCatalog(file);
  catalogs.set(file, catalog);
  for (const unit of translationUnits(file, catalog, config.sourceLocale)) {
    const existing = catalog.strings[unit.key].localizations?.[locale];
    let cursor = existing;
    for (let index = 0; cursor && index < unit.path.length; index += 3) {
      const [, kind, choice] = unit.path.slice(index, index + 3);
      cursor = cursor.variations?.[kind]?.[choice];
    }
    if (refresh || !cursor?.stringUnit?.value) allUnits.push(unit);
  }
}

let cache = { model: modelName, modelDigest: model.digest, promptVersion: config.promptVersion, locale, translations: {} };
try {
  const stored = JSON.parse(await fs.readFile(cacheFile, "utf8"));
  if (!discardCache && stored.model === modelName && stored.modelDigest === model.digest
      && stored.promptVersion === config.promptVersion && stored.locale === locale) cache = stored;
} catch { /* A new run has no cache. */ }

const pending = allUnits.filter(unit => !(unit.id in cache.translations));
console.log(`${allUnits.length} units selected; ${pending.length} require model output; ${allUnits.length - pending.length} resumed from cache.`);
if (dryRun) process.exit(0);

const targetLanguage = config.localeNames[locale];
const schema = {
  type: "object",
  properties: {
    translations: {
      type: "array",
      items: {
        type: "object",
        properties: { id: { type: "string" }, text: { type: "string" } },
        required: ["id", "text"],
        additionalProperties: false,
      },
    },
  },
  required: ["translations"],
  additionalProperties: false,
};

const systemPrompt = [
  `You are the professional localization engine for CueTake, a premium mobile video editor. Translate English interface copy into neutral, natural ${targetLanguage}.`,
  "Return only the requested JSON. Translate every item exactly once and retain its id.",
  "Use concise, contemporary language that fits small iPhone controls. Preserve meaning, tone, capitalization intent, punctuation intent, and every newline.",
  "Preserve printf placeholders exactly, including their index, type, percent signs, and multiplicity. Do not translate brand names or protected technical terms.",
  "Use the key, catalog path, and developer comment as context. Never expose the key in the visible translation.",
  "Do not add explanations, alternatives, quotation marks, or translator notes.",
].join("\n");

const queue = [];
for (let offset = 0; offset < pending.length; offset += config.batchSize) {
  queue.push(pending.slice(offset, offset + config.batchSize));
}
let processed = 0;
while (queue.length) {
  const batch = queue.shift();
  const input = batch.map(({ id, key, comment, source, file, path: unitPath }) => ({
    id,
    key,
    catalog: relative(file),
    variant: unitPath.length ? unitPath.join(".") : "default",
    comment,
    source,
  }));

  let translated;
  let lastError;
  const attemptLimit = batch.length === 1 ? 4 : 2;
  for (let attempt = 1; attempt <= attemptLimit; attempt += 1) {
    try {
      const response = await ollama("/api/chat", {
        model: modelName,
        stream: false,
        // gpt-oss returns an empty content field when reasoning is disabled in
        // current Ollama builds. Low reasoning keeps structured output reliable.
        think: "low",
        keep_alive: "10m",
        format: schema,
        options: config.options,
        messages: [
          { role: "system", content: systemPrompt },
          { role: "user", content: JSON.stringify({
            targetLanguage,
            correction: attempt > 1 ? `The previous response was rejected: ${lastError?.message}. Correct that problem.` : undefined,
            items: input,
          }) },
        ],
      });
      const parsed = JSON.parse(response.message?.content ?? "");
      const returned = new Map((parsed.translations ?? []).map(item => [item.id, item.text]));
      if (returned.size !== batch.length) throw new Error(`expected ${batch.length} results, received ${returned.size}`);
      translated = batch.map(unit => {
        if (!returned.has(unit.id)) throw new Error(`missing id ${unit.id}`);
        const text = returned.get(unit.id);
        const issues = validatePair(unit.source, text, config.protectedTerms);
        if (issues.length) throw new Error(`${unit.key}: ${issues.join(", ")}`);
        return [unit.id, text];
      });
      break;
    } catch (error) {
      lastError = error;
      console.warn(`Batch of ${batch.length}, attempt ${attempt} failed: ${error.message}`);
    }
  }
  if (!translated) {
    if (batch.length === 1) throw lastError;
    const middle = Math.ceil(batch.length / 2);
    queue.unshift(batch.slice(middle), batch.slice(0, middle));
    console.warn(`Splitting rejected batch into ${middle} and ${batch.length - middle} units.`);
    continue;
  }

  for (const [id, text] of translated) cache.translations[id] = text;
  const running = await ollama("/api/ps");
  const loaded = (running.models ?? []).find(candidate => candidate.name === modelName);
  if (loaded?.size > config.maximumModelBytes) {
    await ollama("/api/generate", { model: modelName, keep_alive: 0 });
    throw new Error(`Ollama runtime reached ${(loaded.size / 2 ** 30).toFixed(1)} GiB, above the configured limit`);
  }
  cache.updatedAt = new Date().toISOString();
  await atomicWrite(cacheFile, `${JSON.stringify(cache, null, 2)}\n`);
  processed += batch.length;
  console.log(`[${processed}/${pending.length}] model translations validated and checkpointed`);
}

for (const unit of allUnits) {
  const value = cache.translations[unit.id];
  if (typeof value !== "string") throw new Error(`No cached model translation for ${unit.id}`);
  setTranslation(catalogs.get(unit.file), unit, locale, value);
}

const lock = {
  version: 1,
  generator: "Ollama",
  model: modelName,
  modelDigest: model.digest,
  modelBytes: model.size,
  sourceLocale: config.sourceLocale,
  generatedLocales: config.generatedLocales,
  controls: {
    sequentialRequests: true,
    numCtx: config.options.num_ctx,
    numBatch: config.options.num_batch,
    maximumModelBytes: config.maximumModelBytes,
  },
  catalogs: {},
};

for (const [file, catalog] of catalogs) {
  const contents = appleJSON(catalog);
  await atomicWrite(file, contents);
  lock.catalogs[relative(file)] = {
    sha256: sha256(contents),
    translatedUnits: translationUnits(file, catalog, config.sourceLocale).length,
  };
}
await atomicWrite(lockPath, `${JSON.stringify(lock, null, 2)}\n`);
await ollama("/api/generate", { model: modelName, keep_alive: 0 });
console.log(`Wrote ${catalogs.size} catalogs and ${path.relative(repositoryRoot, lockPath)}. Ollama model unloaded.`);
