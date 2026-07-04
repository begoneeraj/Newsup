// Supabase Edge Function: sends an FCM push to every registered device
// whenever a row is inserted into crisis_reports. Wired up via a Database
// Webhook (Database -> Webhooks in the Supabase dashboard) rather than a
// Postgres trigger + pg_net, since Webhooks are the supported no-extra-setup
// path for "call this function on INSERT."
//
// Required secrets (`supabase secrets set NAME=value`):
//   FCM_SERVICE_ACCOUNT_JSON  - the full contents of the Firebase Admin SDK
//                               service-account JSON downloaded from the
//                               Firebase console (Project settings -> Service
//                               accounts -> Generate new private key).
//   WEBHOOK_SECRET            - optional. If set, the Database Webhook must
//                               send a matching `x-webhook-secret` header
//                               (configurable in the webhook's custom
//                               headers), so this public URL can't be
//                               triggered by anyone who finds it.
//
// SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are injected automatically by
// the Edge Functions runtime — no need to set them.
//
// Deploy with: supabase functions deploy notify-crisis --no-verify-jwt
// (Database Webhooks call this unauthenticated; WEBHOOK_SECRET above is the
// real access control here.)

import { createClient } from "npm:@supabase/supabase-js@2";
import { importPKCS8, SignJWT } from "npm:jose@5";

const FCM_SCOPE = "https://www.googleapis.com/auth/firebase.messaging";

interface CrisisReportRow {
  id: string;
  title: string;
}

interface WebhookPayload {
  type: string;
  table: string;
  record: CrisisReportRow;
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
  const webhookSecret = Deno.env.get("WEBHOOK_SECRET");
  if (webhookSecret && req.headers.get("x-webhook-secret") !== webhookSecret) {
    return new Response("unauthorized", { status: 401 });
  }

  try {
    const payload = (await req.json()) as WebhookPayload;
    if (payload.type !== "INSERT" || payload.table !== "crisis_reports") {
      return new Response("ignored", { status: 200 });
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

    const report = payload.record;
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
                  title: "New crisis report",
                  body: report.title,
                },
                data: { crisis_id: report.id },
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
