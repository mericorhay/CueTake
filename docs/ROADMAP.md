# CueTake — what is left

Written 2026-09-13, after build 19. Ordered by importance. Tick things off here as they land.

> **Pending upload:** everything after build 22 (assistant workflow cards, reversed clips with
> sound, new tests) is on `main` but not on TestFlight — Apple's daily upload limit was reached on
> 2026-09-13 (error 90382). Rerun the TestFlight workflow after 24 hours.

## Before selling

- [ ] Connect the assistant: deploy `backend/assistant`, set `CUETAKE_ASSISTANT_URL` and
      `CUETAKE_ASSISTANT_TOKEN` repository secrets, rerun TestFlight. (Owner: Meriç)
- [ ] Payments: StoreKit 2, paywall, free-tier limits. Settings' "Subscription" row is static text.
- [ ] Privacy policy URL and App Store privacy labels. Draft in `docs/PRIVACY.md` (EN + TR) — needs
      legal name, contact and a public URL, then review.
      Was: Privacy policy URL and App Store privacy labels (the assistant sends messages and project
      context to our server). Likely also why external TestFlight review said "missing information".
- [x] App icon and in-app mark from the Gemini artwork (build 21). A vector version would still be nicer for print and the App Store page.
- [x] First launch: new users are dropped into `Project.sample`. Replace with an empty state that
      says "import your footage".
- [ ] On-device test pass: Liquid Glass, animations, 8K export, reverse memory, filler-word cutting.
- [ ] Export crash (reported 2026-09-13). Fixed in build 20, awaiting on-device confirmation:
      the Photos save closure was main-actor-inferred and PhotoKit runs it on its own queue
      (Swift 6 runtime trap). Also hardened two Objective-C exception paths (overlapping audio
      ramps, audio engine graph built before manual rendering).

## Looks like it works, does not

- [x] Caption styles: Pop / Clean / Karaoke only store an id; preview and export draw them all the
      same. Karaoke word highlight is not implemented although word timings exist.
- [x] Teleprompter does not follow speech: Studio and Retake still advance on a 130–135 ms timer.
      Now follows the voice live (on-device), paces itself when it cannot hear, never auto-stops.
      Needs an on-device check: that the movie file keeps its sound with the audio tap attached.
- [x] Prompt screen options (length, tone, format) are static.
- [x] Clean audio applies to added audio only, not the footage's own voice.
- [x] Reversed clips are silent.
- [ ] Workflows: script and record steps are skipped; music level needs music added by hand first.

## Behind competitors

- [x] Thumbnails on timeline clips (coloured boxes today).
- [ ] Assistant can talk but not act. First step done: it proposes workflows as cards that open
      in the studio or run on the open project. Still to do: acting on the timeline directly.
      Previously: Assistant can talk but not act. "Edit like you talk" / AI timeline agent: let it run editor
      tools and write workflows (tool use through the proxy).
- [x] Remember My Style (caption look and position, voice cleanup; Settings toggle).

## Fixed in the 2026-09-13 evening pass

- [x] Split, merge, pause trimming, word cuts and take switches deleted a clip's captions.
- [x] Stop in the studio moved on before the file was closed (take could go missing).
- [x] Captions screen could not edit anything; now a full captions studio.
- [x] Script screen was read-only and its rewrite chips were string tricks.

## Hygiene

- [x] Tests for transcript editing, audio envelope, caption placement, presets and AI-written
      workflow JSON (Domain, MediaEngine and EditorFeature test targets). Composer itself still
      untested — it needs real media files.
- [x] Remove the four unused `Unimplemented*` engines from `AppDependencies`.
- [x] Rate limiting on the assistant worker (20/min per address via a Cloudflare rate-limit binding).
