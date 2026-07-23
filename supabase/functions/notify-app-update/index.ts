// Supabase Edge Function: sends an FCM push to every registered device
// announcing a new app release, with a link to go install it. Unlike
// notify-crisis (triggered by a Database Webhook on INSERT), this one is
// called directly by the release-apk.yml GitHub Actions workflow right
// after it publishes a GitHub Release — there's no database row to hang a
// webhook off of, just a CI step that just built the new APK.
//
// Required secrets (`supabase secrets set NAME=value`):
//   FCM_SERVICE_ACCOUNT_JSON  - same Firebase Admin SDK service-account JSON
//                               used by notify-crisis.
//   RELEASE_NOTIFY_SECRET     - required. The caller must send a matching
//                               `x-webhook-secret` header. This function is
//                               deployed with --no-verify-jwt (CI can't hold
//                               a Supabase user JWT), so this is the only
//                               access control.
//
// SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are injected automatically by
// the Edge Functions runtime — no need to set them.
//
// Deploy with: supabase functions deploy notify-app-update --no-verify-jwt

import { createClient } from "npm:@supabase/supabase-js@2";
import { importPKCS8, SignJWT } from "npm:jose@5";

const FCM_SCOPE = "https://www.googleapis.com/auth/firebase.messaging";

interface ReleasePayload {
  version: string;
  url: string;
}

interface ServiceAccount {
  project_id: string;
  client_email: string;
  private_key: string;
}

async function getAccessToken(serviceAccount: ServiceAccount): Promise<string> {
  const privateKey = await importPKCS8(serviceAccount.private_key, "RS256");
  const now = Math.floor(Date.now() / 1000);

  const jwt = await new SignJWT({ scope: FCM_SCOPE })
    .setProtectedHeader({ alg: "RS256" })
    .setIssuer(serviceAccount.client_email)
    .setSubject(serviceAccount.client_email)
    .setAudience("https://oauth2.googleapis.com/token")
    .setIssuedAt(now)
    .setExpirationTime(now + 3600)
    .sign(privateKey);

  const response = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: jwt,
    }),
  });

  const json = await response.json();
  if (!response.ok) {
    throw new Error(`OAuth token exchange failed: ${JSON.stringify(json)}`);
  }
  return json.access_token as string;
}

Deno.serve(async (req) => {
  const secret = Deno.env.get("RELEASE_NOTIFY_SECRET");
  if (!secret || req.headers.get("x-webhook-secret") !== secret) {
    return new Response("unauthorized", { status: 401 });
  }

  try {
    const { version, url } = (await req.json()) as ReleasePayload;
    if (!version || !url) {
      return new Response("version and url are required", { status: 400 });
    }

    const serviceAccount = JSON.parse(
      Deno.env.get("FCM_SERVICE_ACCOUNT_JSON")!,
    ) as ServiceAccount;
    const accessToken = await getAccessToken(serviceAccount);

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );
    const { data: tokens, error } = await supabase.from("device_tokens").select("token");
    if (error) throw error;

    const sendResults = await Promise.allSettled(
      (tokens ?? []).map(({ token }: { token: string }) =>
        fetch(
          `https://fcm.googleapis.com/v1/projects/${serviceAccount.project_id}/messages:send`,
          {
            method: "POST",
            headers: {
              Authorization: `Bearer ${accessToken}`,
              "Content-Type": "application/json",
            },
            body: JSON.stringify({
              message: {
                token,
                notification: {
                  title: "TruthLens India update available",
                  body: `${version} is ready — tap to download`,
                },
                data: { type: "app_update", update_url: url },
              },
            }),
          },
        )
      ),
    );

    const sent = sendResults.filter((r) => r.status === "fulfilled").length;
    return new Response(JSON.stringify({ sent, total: sendResults.length }), {
      headers: { "Content-Type": "application/json" },
    });
  } catch (err) {
    console.error(err);
    return new Response(JSON.stringify({ error: String(err) }), { status: 500 });
  }
});
