# SAP Jarvis — data protection record

Internal record describing what the application processes, for SAP data-protection and security
reviews (PET / SADD input). Version 0.1.0, September 2026. Owner: I314819.

## 1. Purpose

SAP Jarvis is a macOS menu-bar application for SAP employees that converts the user's own
speech into text and inserts it at the cursor of the application they are working in. It is a
personal productivity tool; it does not provide the text to anyone else.

## 2. Processing overview

| Step | Data | Where | Retention |
|---|---|---|---|
| Recording | Microphone audio (16 kHz mono) | RAM of the user's Mac | Discarded at the end of each recording (seconds) |
| Speech recognition | Audio chunks, recognized text | Apple Neural Engine on the Mac (WhisperKit, Silero VAD) | Not stored |
| Delivery | Recognized text | Focused application via Accessibility, or the macOS pasteboard (marked transient, previous contents restored after ≤ 1 s) | Under the user's control in the target app |
| Diagnostics | Timings, chunk counts, audio level peak, device names, app bundle ids | Apple unified log on the Mac | System default (in-memory / hours); no transcript text is ever logged |

No processing happens outside the user's Mac.

## 3. Categories of personal data

- Voice (biometric-adjacent, but never stored or transmitted; processed transiently for recognition only).
- Content of dictation: whatever the user says. Delivered only to the destination the user chose.
- Configuration: preferred languages, keyboard shortcuts, microphone name, vocabulary words the
  user entered, feature toggles. Stored in the app's preferences (`com.sap.jarvis`) on the Mac.
- No identifiers: no user id, account, e-mail, device id or usage statistics are collected.

## 4. Data transfers

- **Model download (one time):** the application downloads the speech model and the voice
  activity model from `huggingface.co` on first use (about 1.6 GB). The request carries no user
  data beyond what any HTTPS download exposes (IP address, user agent).
- **Feedback (user-initiated):** "Report an Issue…" opens the browser at the SAP-internal GitHub
  issue tracker with a pre-filled template containing the app version, macOS version and model
  name. The user decides what else to write and whether to submit.
- Nothing else. No analytics, crash reporting, update checks, cloud services or SAP backends.

## 5. Storage on the device

| Item | Location | Removal |
|---|---|---|
| Settings | User defaults `com.sap.jarvis` | Settings → Privacy → Reset Settings, or delete the app's preferences |
| Models | `~/Library/Application Support/Jarvis/Models` | Settings → Privacy → Delete Models…, or delete the folder |
| Application | `/Applications/Jarvis.app` | Move to Trash |

Audio and text are never written to disk by the application.

## 6. macOS permissions and why

| Permission | Use | Not used for |
|---|---|---|
| Microphone | Capturing speech while the user records | Background listening (capture runs only between start and stop) |
| Accessibility | Placing text at the cursor and sending ⌘V to the focused app | Reading screen content, monitoring keystrokes |

Input Monitoring, Screen Recording, Contacts, Calendar, Location, Camera and Full Disk Access are
not requested. The application refuses to insert text while macOS secure input is active
(password fields).

## 7. Security

- Runs as the user, no privileged helper, no network listener.
- Hardened Runtime enabled; signed with a local certificate for the developer's Mac. Distribution
  builds are to be signed with an SAP Developer ID and notarized.
- Dependencies: WhisperKit (Argmax, MIT), FluidAudio (Apache-2.0), swift-argument-parser (Apple).
  Reviewed for network use: only the model download endpoints above.
- Source: SAP-internal GitHub (`I314819/sap-jarvis`), with a public mirror that contains no SAP
  data, credentials or personal recordings (personal audio fixtures are git-ignored).

## 8. Data subject rights

All data is on the user's own device and under the user's control; there is no processor, no
central storage and no way for SAP or the developer to access a user's recordings or text.
Deleting the application, its preferences and the models folder removes everything.

## 9. Open points for the review

- Confirm classification of transient voice processing on-device (no storage) for the PET.
- Decide whether Hugging Face as the model source needs an approved mirror (Artifactory) for
  managed distribution.
- Add a threat-model note once the signed distribution pipeline exists.
