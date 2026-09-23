# CueTake localization pipeline

CueTake ships English (`en`), Spanish (`es`), and Turkish (`tr`) from Apple String Catalogs. English is the authored source language. Human-facing generated translations are produced only by a local Ollama model; the pipeline itself never contains translated copy.

The in-app language picker persists `AppSettings.language`, applies that locale to SwiftUI, and routes programmatic labels through `AppLocalization`. This keeps alerts, status text and model-created UI copy in the same language without sending the user to iOS Settings or requiring a restart.

## Generate translations locally

Run from the repository root:

```powershell
node tools/localization/translate-with-ollama.mjs --locale=es --refresh
node tools/localization/translate-with-ollama.mjs --locale=tr
node tools/localization/validate-localizations.mjs --strict --verify-lock
```

When authored English changes, refresh only the affected keys while keeping every other reviewed
translation stable:

```powershell
node tools/localization/translate-with-ollama.mjs --locale=es --refresh --key=key.one,key.two
node tools/localization/translate-with-ollama.mjs --locale=tr --refresh --key=key.one,key.two
```

`--refresh` rebuilds a generated locale from the validated local cache and asks Ollama only for missing or source-changed units. A run without it fills only missing values, which preserves the existing authored Turkish catalog. Use `--discard-cache` as well when a new prompt should regenerate unchanged source copy. Cache compatibility is tied to the exact model digest, `promptVersion`, and the source text for each unit.

The generator discovers every `.xcstrings` catalog, selects an installed preferred model below the configured 20 GiB model limit, and sends one request at a time with a bounded context. Small batches keep CPU-hosted inference reliable; any rejected batch is split automatically until it validates. It checkpoints validated responses in the ignored `.localization-cache` directory, so an interrupted run resumes without paying the translation cost again. Catalog files are replaced atomically only after all selected units pass validation.

The committed `ollama-translations.lock.json` records the Ollama model digest and the SHA-256 of every generated catalog. CI verifies coverage, placeholders, plural shapes, protected terms, translation states, Xcode regions, and those hashes. When source copy changes, regenerate the target locale and commit the catalog changes together with the new lock.

Do not edit generated Spanish values by hand. Improve context with String Catalog comments or adjust the model prompt and regenerate them through Ollama.
