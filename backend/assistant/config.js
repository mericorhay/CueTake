// What the app reads at launch from GET /config, so limits and switches change without an app
// update. Edit, then `npx wrangler deploy`. Phones pick it up on their next launch.
//
// Everything is optional: leave a field out and the app uses what it ships with. Nothing here is
// secret — the endpoint is public.
//
//   limits      monthly uses by feature, then plan. -1 means no limit. Feature names:
//               aiEdit, assistantMessage, scriptWriting, captionTranslation, workflowRun,
//               stockBroll, cloudListening
//   freeStyles  video styles the free plan may use: boldBusiness, vlog, podcast, ugcAd,
//               minimal, energetic (the app's VideoStyle raw values). Replaces the built-in list.
//   flags       on/off switches the app checks by name
//   values      free-form text values
//
// An optional APP_CONFIG variable (JSON, set in the Cloudflare dashboard) is merged over this,
// for a quick change without a deploy.
export const APP_CONFIG = {
  limits: {
    aiEdit: { free: 5, pro: 150 },
    assistantMessage: { free: 30, pro: 1500 },
    scriptWriting: { free: 10, pro: 500 },
    captionTranslation: { free: 2, pro: 60 },
    workflowRun: { free: 10, pro: -1 },
    stockBroll: { pro: 40 },
    cloudListening: { pro: 300 },
  },
  flags: {},
  values: {},
};

export function handleConfig(env) {
  let config = APP_CONFIG;
  if (env.APP_CONFIG) {
    try {
      config = { ...APP_CONFIG, ...JSON.parse(env.APP_CONFIG) };
    } catch {
      console.log("APP_CONFIG is not valid JSON; serving the built-in config");
    }
  }
  return new Response(JSON.stringify(config), {
    headers: { "content-type": "application/json", "cache-control": "public, max-age=300" },
  });
}
