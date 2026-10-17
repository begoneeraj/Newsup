"""Build the public, dependency-free policy pages from reviewed copy."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1] / 'sites' / 'truthlens-policies' / 'dist'
EMAIL = 'begoneraj@gmail.com'
OWNER = 'Pushpraj singh prashant'
PAGES = {
 'index.html': ('Policies & support', '''
<p class="intro">Understand how TruthLens India works, who publishes it, and how to control your data.</p>
<p class="notice">Independent news aggregation and AI-assisted analysis for adults 18+. TruthLens India is not a government service.</p>
<div class="cards">
<a class="card" href="privacy.html"><h2>Privacy policy</h2><p>Data, service providers, retention and your choices.</p></a>
<a class="card" href="delete-account.html"><h2>Delete your account</h2><p>Request deletion even if you no longer have the app.</p></a>
<a class="card" href="editorial.html"><h2>Editorial standards</h2><p>Sources, AI limitations and corrections.</p></a>
<a class="card" href="contact.html"><h2>Publisher & contact</h2><p>Support, grievances and copyright concerns.</p></a>
</div><p>Published and operated by Pushpraj singh prashant. Contact: <a href="mailto:begoneraj@gmail.com">begoneraj@gmail.com</a>.</p>'''),
 'privacy.html': ('Privacy policy', '''
<p class="intro">TruthLens India is operated by Pushpraj singh prashant. This policy explains the Android app and this policy website.</p>
<h2>Information we process</h2><div class="table-wrap"><table><thead><tr><th>Information</th><th>Purpose and location</th></tr></thead><tbody>
<tr><td>Google name, email, profile picture and account identifier</td><td>Firebase Authentication signs you in and stores your app account. Your profile is displayed in the app. We do not receive your Google password.</td></tr>
<tr><td>Bookmarks, reading-game progress, appearance preferences, policy acknowledgement</td><td>Stored on your device in app preferences. These features do not upload this information to our database.</td></tr>
<tr><td>Optional notification token and platform</td><td>Firebase Cloud Messaging delivers notifications. Supabase stores the device token when you opt in.</td></tr>
<tr><td>Technical connection information, including IP address</td><td>Google/Firebase, Supabase, font and image hosts receive connection information when the app connects. This website's hosting provider also processes web requests for hosting and security.</td></tr>
<tr><td>Support messages and information you choose to include</td><td>Our support email provider processes requests so the publisher can respond, investigate and verify ownership.</td></tr>
</tbody></table></div>
<h2>Your choices</h2><p>The service is for adults 18 and over. Before sign-in, you acknowledge this notice and agree to the terms. We do not request your date of birth, identity document, location, contacts, camera or microphone. Notifications require a separate choice and Android permission. You can disable them in Account → Privacy & account controls.</p>
<p>No advertising, behavioural advertising, or analytics SDK is configured in this release. We do not sell your personal information. Public news content is processed by our backend using AI providers including Groq; the app does not send your authentication profile to the news-analysis model.</p>
<h2>Service providers and external links</h2><p>We use Google Sign-In, Firebase Authentication, Firebase Cloud Messaging and Cloud Firestore, Supabase, and Google Fonts. These providers may process data outside India under their service terms and safeguards. See <a href="https://firebase.google.com/support/privacy">Firebase privacy information</a>, <a href="https://policies.google.com/privacy">Google's privacy policy</a> and <a href="https://supabase.com/privacy">Supabase's privacy policy</a>. Original publishers and apps to which you share content apply their own policies.</p>
<h2>Retention and security</h2><p>Your app account is retained until deletion. Local bookmarks and progress remain until cleared, the app's data is removed, or you delete your account on that device. Other devices may retain their own local copies. Notification registrations are removed through the app's disable/delete controls; legacy records or records on inaccessible devices can be included in an email deletion request. Operational logs and backups are subject to the configured retention of our service providers and may not disappear immediately with live data. We do not claim that all provider records are erased instantly.</p>
<p>Support correspondence is retained as needed to resolve the request, document its handling and meet applicable legal requirements. You may request its removal; we will explain any lawful retention exception. Connections use HTTPS. No system can guarantee absolute security.</p>
<h2>Access, correction, withdrawal and deletion</h2><p>Email <a href="mailto:begoneraj@gmail.com">begoneraj@gmail.com</a> to request access, correction, deletion or withdraw your use of the service. We may verify ownership using the registered email; do not send passwords, OTPs or identity documents. See <a href="delete-account.html">account deletion instructions</a>. If we must retain information for a legal or security reason, we will explain the category and reason when responding.</p>
<h2>Children</h2><p>This release is not intended for people under 18. If you believe a child's information was supplied, contact the publisher so it can be investigated and removed as appropriate. We do not offer a parental-consent flow in this release.</p>
<h2>Contact and changes</h2><p>Publisher and privacy/grievance contact: Pushpraj singh prashant, <a href="mailto:begoneraj@gmail.com">begoneraj@gmail.com</a>. Material changes will update the policy date and the app's acknowledgement. <a href="contact.html">Contact details and complaint process</a>.</p>'''),
 'delete-account.html': ('Delete your account & data', '''
<p class="intro">You can request deletion of your TruthLens India account without reinstalling the app.</p>
<h2>Request deletion by email</h2><ol><li>Email <strong>begoneraj@gmail.com</strong> from the Google email address used for TruthLens India.</li><li>Use the subject <strong>TruthLens India account deletion</strong>. State that you want your app account and associated data deleted. Mention if you have lost access to the device or have used multiple devices.</li><li>The publisher may reply to verify ownership and clarify which data should be removed. Never send your password, OTP or identity documents.</li></ol>
<p><a class="button" href="mailto:begoneraj@gmail.com?subject=TruthLens%20India%20account%20deletion">Compose deletion request</a></p>
<p>This button opens your email app; it does not submit anything automatically. If it does not open, copy the email address above. You may request deletion of specific data without deleting your account by describing it in your message.</p>
<h2>Delete inside the app</h2><p>Open your profile avatar → Privacy & account controls → Delete my account. Confirm the deletion and reauthenticate with the same Google account. Keep an internet connection until completion. If an error appears, deletion is not confirmed; retry or email support.</p>
<h2>What is deleted</h2><p>The app deletes your Firebase Authentication profile and the current device's notification registration, bookmarks, reading-game progress and preferences. Your Google account is not deleted. No cloud bookmark or game-progress profile is stored. Local copies on other devices must be cleared there; contact support about inaccessible devices or legacy notification records.</p>
<h2>What may remain</h2><p>Public news and third-party content are not your account data. Content shared to other apps remains with its recipients. Provider backups, security logs and records required by law may remain according to the applicable retention rules. If a retention exception applies to your request, the publisher will explain it. See the <a href="privacy.html">privacy policy</a>.</p>
<p>We aim to acknowledge requests within 24 hours and resolve them within 15 days after ownership is verified, or explain any delay. Statutory deadlines, where applicable, take precedence.</p>'''),
 'contact.html': ('Publisher, support & grievances', '''
<p class="intro">TruthLens India is published and operated by <strong>Pushpraj singh prashant</strong>, an independent individual publisher.</p>
<p>Public support, privacy and grievance contact: <a href="mailto:begoneraj@gmail.com">begoneraj@gmail.com</a>.</p>
<h2>Send a concern</h2><p>For an inaccurate claim, missing attribution, harmful content, copyright concern or privacy request, email the contact above. Include the article title or ID, the issue, relevant source links and the action you are requesting. Do not include passwords, OTPs or unnecessary sensitive information.</p>
<p>We aim to acknowledge complaints within 24 hours and resolve them within 15 days, or explain any delay. Applicable statutory timelines take precedence. This is an operational target, not a claim that every statutory category applies to this service.</p>
<h2>Corrections and lawful requests</h2><p>Reports are reviewed against the linked evidence. Appropriate corrections, attribution changes or removal may follow. Rights holders should identify the protected work and the allegedly infringing item. Lawful requests are reviewed for authenticity and applicable obligations.</p>
<p><a href="delete-account.html">Request account or data deletion</a> · <a href="editorial.html">Read editorial standards</a></p>'''),
 'editorial.html': ('Editorial standards & AI transparency', '''
<p class="intro">Read the evidence. Understand the uncertainty. Report mistakes.</p>
<h2>What the app does</h2><p>TruthLens India aggregates news and public information, generates AI-assisted claim analysis and tracks longer-running crises. It is not affiliated with or endorsed by the Government of India. Government sources, where cited, are source material and do not imply official status.</p>
<h2>AI limitations</h2><p>Summaries, analysis, verdicts and confidence scores may be produced automatically. They can be incomplete or wrong. A numerical score is a model assessment, not a calibrated probability or guarantee. Unless an item explicitly identifies a human reviewer, do not assume it was reviewed by an expert. Unverified claims are not established facts.</p>
<h2>Sources and attribution</h2><p>Each published news item should identify its original publisher or author and link to supporting sources. We distinguish original reporting from our analysis. Sources can disagree or change; readers should inspect the originals and their dates. We do not claim ownership of linked reporting. Licensing and permission requirements apply even when attribution is given.</p>
<h2>Corrections and content standards</h2><p>We investigate reports of errors, fabricated sources, harmful content and copyright issues. We may correct, label, restrict or remove an item. We aim to avoid misleading headlines, unsupported accusations and presentation of automated analysis as established fact. Contact <a href="mailto:begoneraj@gmail.com">begoneraj@gmail.com</a> with the article ID and supporting evidence.</p>
<h2>Ownership and independence</h2><p>The publisher is Pushpraj singh prashant. This release contains no advertising or paid subscriptions. No professional accreditation, award or government endorsement is claimed.</p>'''),
 'terms.html': ('Terms of use', '''
<p class="intro">These terms apply to TruthLens India, operated by Pushpraj singh prashant.</p>
<h2>Eligibility and account</h2><p>You must be at least 18 years old to use this release. Sign in with a Google account you are entitled to use and protect your credentials. You may stop using the service or <a href="delete-account.html">delete your app account</a> at any time.</p>
<h2>Permitted use</h2><p>Use the service lawfully. Do not interfere with its security, impersonate people, abuse its infrastructure or infringe intellectual-property or privacy rights. This release does not provide a public user-posting or commenting service.</p>
<h2>Information and intellectual property</h2><p>The app provides news aggregation and automated analysis for information. It is not professional legal, financial or medical advice. Check original sources before relying on a claim. Third-party articles and media remain the property of their owners; links do not grant permission to republish. Share only material you are entitled to share.</p>
<h2>Availability and liability</h2><p>We do not guarantee uninterrupted availability or complete accuracy. We may update, correct or remove content and restrict abusive access. Nothing here excludes non-excludable consumer rights or liability that cannot lawfully be limited. There are no payments or subscriptions in this release.</p>
<h2>Privacy, disputes and changes</h2><p>The <a href="privacy.html">privacy policy</a> describes data practices. Contact <a href="mailto:begoneraj@gmail.com">begoneraj@gmail.com</a> first about a concern. These terms are governed by applicable Indian law, subject to mandatory rights and the jurisdiction of competent courts. Material updates will be dated and may require renewed acknowledgement.</p>'''),
}

def main():
    ROOT.mkdir(parents=True, exist_ok=True)
    for name, (title, body) in PAGES.items():
        html = f'''<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>{title} — TruthLens India</title><meta name="description" content="TruthLens India official publisher policies, support and account deletion."><link rel="stylesheet" href="style.css"></head><body><header><a class="brand" href="index.html">TruthLens India</a><nav aria-label="Policy navigation"><a href="privacy.html">Privacy</a><a href="terms.html">Terms</a><a href="delete-account.html">Delete account</a><a href="contact.html">Contact</a></nav></header><main><p class="eyebrow">Transparency & control</p><h1>{title}</h1>{body}</main><footer>Effective 17 October 2026 · {OWNER}<br><a href="mailto:{EMAIL}">{EMAIL}</a> · <a href="editorial.html">Editorial standards</a></footer></body></html>'''
        (ROOT / name).write_text(html, encoding='utf-8')
    print(f'Built {len(PAGES)} policy pages in {ROOT}')

if __name__ == '__main__':
    main()
