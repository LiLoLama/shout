# shout. — Lizenz-Webhook (Stripe → Ed25519 → E-Mail)

Kleiner Cloudflare Worker, der nach einem Stripe-Kauf automatisch einen
Ed25519-signierten Lizenzschlüssel erzeugt und per E-Mail verschickt.

**Architektur (bewusst serverlos & offline-freundlich):**

```
App „Kaufen"-Button ──▶ Stripe Payment Link (150 €, hosted by Stripe)
                                     │  Kunde zahlt, E-Mail wird erfasst
                                     ▼
                         Stripe Webhook: checkout.session.completed
                                     │
                                     ▼
        Worker  ──▶  signiert Schlüssel (privater Key = Worker-Secret)
                ──▶  mailt ihn an die Käufer-Adresse (Resend)
                                     │
                                     ▼
        Kunde fügt Schlüssel in shout. ein → App verifiziert OFFLINE
                                    (öffentlicher Key ist eingebaut)
```

Der **private** Signing-Key verlässt nie den Worker. Die App kennt nur den
**öffentlichen** Key (`LicenseStore.publicKeyBase64`) und braucht für die
Aktivierung kein Internet.

## Einrichtung

### 1. Abhängigkeiten
```bash
cd server
npm install
npm run typecheck   # optional
```

### 2. Stripe: Produkt + Payment Link
- Im Stripe-Dashboard ein Produkt „shout. Lifetime-Lizenz" mit **einmalig 150 €** anlegen.
- Dazu einen **Payment Link** erstellen. Diese URL kommt in die App
  (`Sources/FlowLokal/LicenseView.swift` → `purchaseURL`).
- Wichtig: Beim Payment Link **E-Mail-Adresse erfassen** aktiviert lassen
  (Standard) — sie wird als Lizenznehmer in den Schlüssel signiert.

### 3. Webhook in Stripe
- Endpoint: `https://<dein-worker>.workers.dev/webhook`
- Event: `checkout.session.completed`
- Das **Signing Secret** (`whsec_…`) für Schritt 4 kopieren.

### 4. E-Mail: Resend
- Kostenloses Konto auf resend.com (Free-Tier: 3.000 Mails/Monat, 100/Tag).
- **API-Key** erstellen (`re_…`).
- Für den Echtbetrieb eine **eigene Domain verifizieren** (Resend zeigt die DNS-Einträge SPF/DKIM). Zum Testen kann als Absender `onboarding@resend.dev` genutzt werden — dann aber nur an die eigene Konto-Adresse zustellbar.

### 5. Secrets setzen
```bash
npx wrangler secret put STRIPE_SECRET_KEY       # sk_live_… (oder sk_test_… zum Testen)
npx wrangler secret put STRIPE_WEBHOOK_SECRET    # whsec_…
npx wrangler secret put LICENSE_PRIVATE_KEY      # Inhalt aus ../.license-signing/PRIVATE_KEY.txt (32-Byte base64-Seed)
npx wrangler secret put RESEND_API_KEY           # re_…
npx wrangler secret put FROM_EMAIL               # z. B. "shout. <lizenz@deine-domain.de>"
```

### 6. Deployen
```bash
npm run deploy
```

## Lokal testen
```bash
# .dev.vars mit denselben Keys anlegen (nicht committen), dann:
npm run dev
# In einem zweiten Terminal Stripe-Events durchreichen:
stripe listen --forward-to localhost:8787/webhook
stripe trigger checkout.session.completed
```

## Schlüsselformat
Identisch zu `.license-signing/make-license.swift`:
`base64(payloadUTF8) + "." + base64(ed25519Signatur)`, wobei `payload` die
Käufer-E-Mail ist. Verifikation in `LicenseStore.verify(_:)`.

## Sicherheits-Hinweis
Der Payload enthält aktuell nur die E-Mail — keine Geräte-Bindung/kein Ablauf.
Ein geleakter Schlüssel funktioniert also auf beliebig vielen Geräten (bewusste
Einfachheit für v1). Härtung (Hardware-UUID/Ablaufdatum im Payload) ist in
`OFFEN.md` als offener Punkt notiert.
