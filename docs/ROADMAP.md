# CueTake — what is left

Written 2026-09-13, after build 19. Ordered by importance. Tick things off here as they land.

## Before selling

- [ ] Connect the assistant: deploy `backend/assistant`, set `CUETAKE_ASSISTANT_URL` and
      `CUETAKE_ASSISTANT_TOKEN` repository secrets, rerun TestFlight. (Owner: Meriç)
- [ ] Payments: StoreKit 2, paywall, free-tier limits. Settings' "Subscription" row is static text.
- [ ] Privacy policy URL and App Store privacy labels (the assistant sends messages and project
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
- [ ] Teleprompter does not follow speech: Studio and Retake still advance on a 130–135 ms timer.
- [ ] Prompt screen options (length, tone, format) are static.
- [ ] Clean audio applies to added audio only, not the footage's own voice.
- [ ] Reversed clips are silent.
- [ ] Workflows: script and record steps are skipped; music level needs music added by hand first.

## Behind competitors

- [x] Thumbnails on timeline clips (coloured boxes today).
- [ ] Assistant can talk but not act. "Edit like you talk" / AI timeline agent: let it run editor
      tools and write workflows (tool use through the proxy).
- [ ] Remember My Style.

## Hygiene

- [ ] Tests for transcript editing, audio envelope, composer arithmetic.
- [ ] Remove the four unused `Unimplemented*` engines from `AppDependencies`.
- [ ] Rate limiting on the assistant worker.
