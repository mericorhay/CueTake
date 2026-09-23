import assert from "node:assert/strict";
import test from "node:test";
import {
  appleJSON,
  leafUnits,
  placeholderSignature,
  setTranslation,
  validatePair,
} from "./catalogs.mjs";

test("placeholder validation allows grammatical reordering", () => {
  const source = "%1$lld of %2$lld clips · %@";
  const reordered = "%@ · %2$lld clips, %1$lld ready";
  assert.equal(placeholderSignature(source), placeholderSignature(reordered));
  assert.deepEqual(validatePair(source, reordered, []), []);
});

test("placeholder validation rejects missing format arguments", () => {
  assert.deepEqual(validatePair("Delete %lld clips?", "Delete clips?", []), ["placeholder mismatch"]);
});

test("protected product terms and authored line breaks are immutable", () => {
  assert.deepEqual(validatePair("CueTake\nStudio", "Other\nStudio", ["CueTake"]), ["protected term changed: CueTake"]);
  assert.deepEqual(validatePair("First\nSecond", "First Second", []), ["newline mismatch"]);
});

test("Workflow remains a protected term across source capitalization", () => {
  assert.deepEqual(validatePair("Run a workflow", "Ejecutar un Workflow", ["Workflow"]), []);
  assert.deepEqual(validatePair("Run a workflow", "Ejecutar un flujo de trabajo", ["Workflow"]), ["protected term changed: Workflow"]);
});

test("plural translations retain the source variation topology", () => {
  const catalog = {
    strings: {
      count: {
        localizations: {
          en: {
            variations: {
              plural: {
                one: { stringUnit: { state: "translated", value: "%lld item" } },
                other: { stringUnit: { state: "translated", value: "%lld items" } },
              },
            },
          },
        },
      },
    },
  };
  const leaves = leafUnits(catalog.strings.count.localizations.en);
  setTranslation(catalog, { key: "count", path: leaves[0].path }, "es", "%lld TARGET_ONE");
  setTranslation(catalog, { key: "count", path: leaves[1].path }, "es", "%lld TARGET_OTHER");
  assert.deepEqual(leafUnits(catalog.strings.count.localizations.es).map(unit => unit.path), leaves.map(unit => unit.path));
});

test("Apple-style JSON remains valid JSON", () => {
  const value = { sourceLanguage: "en", strings: { key: { comment: "context" } }, version: "1.0" };
  assert.deepEqual(JSON.parse(appleJSON(value)), value);
});
