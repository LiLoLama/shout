import Stripe from 'stripe';

// Erzeugt und verschickt nach einem Stripe-Kauf einen Ed25519-signierten
// shout.-Lizenzschlüssel. Der private Schlüssel liegt ausschließlich als
// Worker-Secret vor; die App verifiziert offline mit dem öffentlichen Key.
// Schlüsselformat (identisch zu .license-signing/make-license.swift):
//   base64(payloadUTF8) + "." + base64(ed25519Signature)   // payload = Käufer-E-Mail

interface Env {
  STRIPE_SECRET_KEY: string;
  STRIPE_WEBHOOK_SECRET: string;
  LICENSE_PRIVATE_KEY: string; // base64 des 32-Byte Ed25519-Seeds
  RESEND_API_KEY: string;
  FROM_EMAIL: string;          // z. B. "shout. <lizenz@deine-domain.de>"
}

// PKCS#8-Präfix für einen rohen Ed25519-Seed (fix), damit Web Crypto ihn importiert.
const PKCS8_PREFIX = new Uint8Array([
  0x30, 0x2e, 0x02, 0x01, 0x00, 0x30, 0x05, 0x06,
  0x03, 0x2b, 0x65, 0x70, 0x04, 0x22, 0x04, 0x20,
]);

function base64ToBytes(b64: string): Uint8Array {
  const bin = atob(b64);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

function bytesToBase64(input: ArrayBuffer | Uint8Array): string {
  const bytes = input instanceof Uint8Array ? input : new Uint8Array(input);
  let bin = '';
  for (const b of bytes) bin += String.fromCharCode(b);
  return btoa(bin);
}

async function signLicense(licensee: string, privateKeyB64: string): Promise<string> {
  const seed = base64ToBytes(privateKeyB64);
  if (seed.length !== 32) {
    throw new Error('LICENSE_PRIVATE_KEY muss ein base64-kodierter 32-Byte-Seed sein');
  }
  const pkcs8 = new Uint8Array(PKCS8_PREFIX.length + 32);
  pkcs8.set(PKCS8_PREFIX, 0);
  pkcs8.set(seed, PKCS8_PREFIX.length);

  const key = await crypto.subtle.importKey('pkcs8', pkcs8, { name: 'Ed25519' }, false, ['sign']);
  const payload = new TextEncoder().encode(licensee);
  const signature = await crypto.subtle.sign('Ed25519', key, payload);
  return `${bytesToBase64(payload)}.${bytesToBase64(signature)}`;
}

async function sendLicenseEmail(env: Env, to: string, licenseKey: string): Promise<void> {
  const text =
    `Danke für deinen Kauf von shout.!\n\n` +
    `Dein Lizenzschlüssel:\n\n${licenseKey}\n\n` +
    `So aktivierst du ihn:\n` +
    `shout. öffnen → „Konto & Lizenz" → Schlüssel einfügen → „Aktivieren".\n\n` +
    `Der Schlüssel schaltet die Vollversion dauerhaft frei. Bei Fragen einfach antworten.\n`;

  const resp = await fetch('https://api.resend.com/emails', {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${env.RESEND_API_KEY}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      from: env.FROM_EMAIL,
      to: [to],
      subject: 'Deine shout.-Lizenz',
      text,
    }),
  });
  if (!resp.ok) {
    throw new Error(`Resend ${resp.status}: ${await resp.text()}`);
  }
}

export default {
  async fetch(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
    const url = new URL(request.url);

    if (request.method === 'GET' && url.pathname === '/') {
      return new Response('shout. license webhook: OK');
    }
    if (request.method !== 'POST' || url.pathname !== '/webhook') {
      return new Response('Not found', { status: 404 });
    }

    const signature = request.headers.get('stripe-signature');
    if (!signature) return new Response('Missing stripe-signature', { status: 400 });

    const payload = await request.text(); // Roh-Body für die Signaturprüfung
    const stripe = new Stripe(env.STRIPE_SECRET_KEY, { httpClient: Stripe.createFetchHttpClient() });

    let event: Stripe.Event;
    try {
      // Async-Variante + SubtleCrypto: Pflicht in Workers (kein sync crypto).
      event = await stripe.webhooks.constructEventAsync(
        payload, signature, env.STRIPE_WEBHOOK_SECRET, undefined, Stripe.createSubtleCryptoProvider(),
      );
    } catch (err) {
      return new Response(`Signaturprüfung fehlgeschlagen: ${(err as Error).message}`, { status: 400 });
    }

    if (event.type === 'checkout.session.completed') {
      const session = event.data.object as Stripe.Checkout.Session;
      const email = session.customer_details?.email ?? session.customer_email ?? null;

      if (email) {
        // Ausstellung + Versand aus dem kritischen Pfad nehmen → schnelles 200.
        ctx.waitUntil((async () => {
          try {
            const key = await signLicense(email, env.LICENSE_PRIVATE_KEY);
            await sendLicenseEmail(env, email, key);
            console.log(JSON.stringify({ msg: 'license issued', email, session: session.id }));
          } catch (e) {
            console.error(JSON.stringify({ msg: 'fulfillment failed', email, error: String(e) }));
          }
        })());
      } else {
        console.error(JSON.stringify({ msg: 'no email on session', session: session.id }));
      }
    }

    return new Response(JSON.stringify({ received: true }), {
      headers: { 'content-type': 'application/json' },
    });
  },
} satisfies ExportedHandler<Env>;
