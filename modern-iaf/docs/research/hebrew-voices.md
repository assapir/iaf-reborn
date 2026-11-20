# Hebrew radio voices — research

This page compares text-to-speech (TTS) services and models that speak Hebrew, for the sim's radio calls: the
tower, the player's own calls, the wingmen, the AWACS and perhaps the instructor. Today these voices are English
(Kokoro, [sound.md](../sound.md) §3, §5) with Hebrew subtitles; real IAF radio is in Hebrew. The user asked on
19 November 2026: "can we generate Hebrew for radio that doesn't sound like shit?", then "Send an agent to research.
Online is fine, we can download and save it on our repo so the setup just diploy it". Research date: 20 November
2026. The page changes no code or strings; the listening samples are on the Approvals page (§6).

**Terms:** G2P = grapheme to phoneme, the step that turns written words into sounds; IPA = the International Phonetic
Alphabet; nikud = the Hebrew vowel marks; particle = one word file of a radio phrase ([sound.md](../sound.md) §3);
Elo = a rating from pairwise votes, higher is better. "Inferred" marks our own reasoning; "open" means no source was
found; "second-hand" means a search engine's quote of a page our tool could not read.

## 1. What we need

- **Made once, shipped as files.** The clips are generated once, on a developer's machine, and committed as Ogg
  files, as the English clips are today: Kokoro runs only where the clips are made, and the setup copies them
  ([sound.md](../sound.md) §5.3). So a cloud service or a large model is used once, not at every setup, and its
  terms must allow shipping its output inside an open-source game repository.
- **Our volume.** The English radio set has 344 clips, 412 s of audio: the tower 119, the AWACS 97, the four-ship 43,
  the player 33, and 52 number, runway and roger particles. Its lines hold about 8,400 characters (Betty's 13 clips
  left out). The same set in Hebrew is about 7,500 characters per pass (inferred: the Hebrew take-off clearance in
  `voices.json` is 85 % of the length of the same call in English, and three short lines 55–90 %). Trying three voices with three takes each is about 70,000
  characters. The Hebrew clips would add about 3.5 MB to the repository (inferred: today's tower, AWACS, four-ship,
  player and Betty clips take 3.6 MB).
- **Radio speech.** Callsigns ("אלפא אחת"), numbers said digit by digit in the feminine counting forms ("שתיים
  חמש"), runway sides ("ימני", "שמאלי") and short urgent calls ("שתיים, נעילה!"). The game's radio chain filters every
  clip anyway ([sound.md](../sound.md) §5.2), so a clean studio voice is the input we want.

## 2. The options at a glance

| option | Hebrew voices | Hebrew quality: the evidence | terms for shipping generated clips | cost for our set | the user needs |
|---|---|---|---|---|---|
| **Google Gemini TTS** (Gemini 3.1 Flash TTS) | 30 named voices, 14 female, 16 male; he-IL in Preview[^g-gemini] | 1st of 12 in the Hebrew TTS arena: Elo 1584, 199 votes[^arena] | Google claims no ownership of the output; no attribution clause; no use to build competing models[^gemini-terms][^g-terms] | under 1 dollar a pass (§3.1) | a Google account and a Gemini API key (or a Cloud project with billing) |
| **Google Cloud TTS Chirp 3 HD** (also WaveNet, Standard) | 30 Chirp 3 HD voices (14 female, 16 male), 4 WaveNet, 4 Standard[^g-voices] | not in the arena; open | as Gemini TTS | free: inside the 1 million characters a month (second-hand)[^g-price] | a Cloud project with billing and the Text-to-Speech API enabled |
| **ElevenLabs** Eleven v3 | its voice library; Hebrew in v3 only[^el-lang] | 3rd in the arena: Elo 1545, 207 votes[^arena]; "good" in a March 2025 test[^rosehill] | the user keeps all rights in the output; commercial use only on a paid plan[^el-terms] | the Starter plan, 6 dollars a month (1 dollar the first month)[^el-price] | an account, the Starter plan, an API key |
| **Microsoft Azure** neural TTS | Hila (female), Avri (male)[^az-voices] | not in the arena; "good" (through Edge) in March 2025[^rosehill] | output use allowed on a paid tier (a community answer, not Microsoft's text)[^az-qa]; the TTS code of conduct applies[^az-coc] | the free tier covers the volume; the paid price did not show (open)[^az-price] | an Azure account and a Speech resource with its key |
| **OpenAI** gpt-4o-mini-tts, tts-1 | 13 voices, "optimized for English"[^oai-guide] | its three TTS models 10th–12th in the arena: Elo 1415–1451[^arena] | the user owns the output (second-hand); listeners must be told the voice is AI[^oai-terms][^oai-guide] | about 1 dollar for all takes[^oai-price] | an OpenAI account and an API key |
| **Amazon Polly** | none: Hebrew is not a Polly language[^polly] | — | — | — | — |
| **BlueTTS** (BlueV3, open) | 15 voices, 8 female, 7 male; a voice can be cloned from 10 s of speech[^blue] | 8th in the arena as Blue V2, the previous version: Elo 1476, 126 votes, above OpenAI's three TTS models[^arena] | MIT model, Apache-2.0 G2P, CC BY 4.0 voices, an OpenRAIL-M vocoder that claims no rights in the output[^blue-bundle] | free; about 1 s per call on this laptop (§6) | nothing: no account; his word on the 0.7 GB download (made, §6) |
| **Chatterbox Multilingual** (open) | none built in: a voice is cloned from a reference clip[^chatterbox] | "poor" in March 2025: the clone did not carry into Hebrew[^rosehill] | MIT; every clip carries Resemble's inaudible watermark[^chatterbox] | free | a reference clip we may use, and 1.5–3.2 GB of download |
| **Pocket TTS Hebrew** (open) | one bundled Hebrew voice, cloning[^pocket] | none found (open) | CC BY 4.0; the Hebrew adapter's training data is not stated (open)[^pocket] | free | about 0.25 GB of download |
| SASPEECH-, ILSpeech- and MMS-trained models (Piper `he_IL-saspeech`, Phonikud TTS, Robo-Shaul, MMS-TTS heb) | one to three speakers each | Piper's: stress errors (tested 2 November 2026, [sound.md](../sound.md) §5.4) | non-commercial licences[^saspeech][^phonikud][^mms] | — | — (not shippable as open data) |
| HebTTS / LoTHM (research) | voice prompts | research papers, no arena entry | no licence file in the HebTTS repository: all rights reserved by default (inferred)[^hebtts] | — | — |

Other services with Hebrew, their terms not checked (open): Deepdub dd-etts-3.3 (2nd in the arena, Elo 1577),
Soniox (4th, Elo 1543; its page offers character timestamps)[^soniox], Inworld (6th, 7th and 9th)[^arena], Cartesia
Sonic[^cartesia] and MiniMax ("best" for cloned voices in March 2025[^rosehill]).

## 3. Cloud services

### 3.1 Google: Gemini TTS and Cloud Text-to-Speech
- **Voices.** Cloud TTS lists 38 he-IL voices: 30 Chirp 3 HD (Achernar … Zubenelgenubi), WaveNet A–D and Standard
  A–D, female A and C, male B and D[^g-voices]. Gemini TTS uses the same 30 star names (14 female, 16 male)[^g-gemini].
- **Quality.** Gemini 3.1 Flash TTS leads the Hebrew TTS arena run by ivrit.ai, where listeners vote between two
  anonymous models on the same sentence[^arena]. Gemini 2.5 Flash TTS (Puck, Zephyr) was "good" in a March 2025
  test[^rosehill]. Chirp 3 HD has no Hebrew rating (open).
- **Delivery and pronunciation.** Gemini TTS takes a natural-language style prompt and markup tags such as
  `[extremely fast]`, `[shouting]` and pauses of 250, 500 and 1000 ms[^g-gemini]: a way to ask for a clipped,
  calm radio delivery (inferred). Chirp 3 HD takes a speaking rate of 0.25–2.0, but its pause markup and custom IPA
  pronunciations are not available in he-IL[^g-chirp]. Neither page mentions word timestamps.
- **Terms.** Google "won't claim ownership" of generated content; it may not be used to build competing models; an
  API client directed at people under 18 may not use the services[^gemini-terms]. The Cloud terms say the same for
  Generated Output (§17, §20)[^g-terms]. No clause asks for attribution or bars publishing the audio. The game calls
  no API: it ships files made once by a developer, so the under-18 clause does not reach its players (inferred; the
  user decides). On the unpaid Gemini tier Google may use the prompts and outputs to improve its products[^gemini-terms];
  our lines are not sensitive.
- **Cost.** Chirp 3 HD: 1 million characters free a month, then 30 dollars a million (second-hand)[^g-price]: our
  70,000 characters cost nothing. Gemini 3.1 Flash TTS: 20 dollars a million audio tokens at 25 tokens a second
  (second-hand)[^gemini-price]; one pass of 412 s is about 10,000 tokens, 0.21 dollars.
- **What the user does.** Gemini API: sign in to Google AI Studio and create an API key. Cloud TTS: create a Cloud
  project, enable billing and the Text-to-Speech API, and create a key or a service account. The key stays out of
  the repository (an environment variable on the machine that makes the clips).

### 3.2 ElevenLabs
- **Voices and quality.** Hebrew is in Eleven v3 only; Multilingual v2 and Flash v2.5 do not list it[^el-lang]. v3
  is 3rd in the arena[^arena]. In the March 2025 test v3 was "good" with the voices Adam, Bella and Rachel and needed
  `language_code: "he"`; Multilingual v2 was unintelligible[^rosehill].
- **Terms.** "As between you and ElevenLabs, you retain all rights in and to your Output"; free users may use the
  services only for non-commercial purposes, paid users for commercial ones[^el-terms]. A game given away free is
  still safest on a paid plan (inferred: "non-commercial" is not defined for an open-source release).
- **Cost.** Starter: 6 dollars a month (1 dollar the first month), 30,000 credits, the commercial licence[^el-price].
  v3 costs about one credit a character (second-hand)[^el-price]: about four passes of our set a month.
- **Cutting.** The dialogue endpoint with timestamps defaults to eleven_v3 and returns each character's
  time[^el-ts]: the joins can be cut at a word, as with Kokoro (§5).
- **What the user does.** Create an account, buy the Starter plan, create an API key.

### 3.3 Microsoft Azure
- **Voices and quality.** he-IL has two prebuilt voices, `he-IL-HilaNeural` (female) and `he-IL-AvriNeural`
  (male)[^az-voices]. The same voices through Microsoft Edge's reader were "good" in March 2025[^rosehill]. Azure is
  not in the arena.
- **Terms.** Microsoft's TTS code of conduct covers prebuilt voices[^az-coc]. Microsoft's own output-rights text
  was not found; a volunteer moderator's accepted answer says the Product Terms allow commercial use of the audio on
  a paid tier, bar using it to build a competing TTS service, and ask for disclosure of synthetic speech[^az-qa]
  (second-hand: a community answer).
- **Cost.** The free tier gives 0.5 million characters a month; the per-million prices did not show on the pricing
  page (open)[^az-price]. If the paid tier is needed for the output rights, the cost for 70,000 characters stays
  small (inferred).
- **Cutting.** The Speech SDK's WordBoundary event gives each word's audio offset[^az-wb].
- **What the user does.** Create an Azure account and a Speech resource (paid tier S0 for the output rights), and
  copy its key.

### 3.4 OpenAI
- **Voices and quality.** Hebrew is in the supported list; "Voices are currently optimized for English"; 13
  voices[^oai-guide]. The three OpenAI TTS models rank 10th–12th of 12 in the arena[^arena].
- **Terms.** The terms assign the output to the user (second-hand: openai.com refused our tool)[^oai-terms]; the
  usage policies require "a clear disclosure to end users that the TTS voice they are hearing is AI-generated"[^oai-guide].
- **Cost.** tts-1: 15 dollars a million characters; gpt-4o-mini-tts: 0.60 dollars a million text tokens and 12
  dollars a million audio tokens[^oai-price]: about 1 dollar for all takes.

## 4. Open and offline models

This laptop has 8 CPU cores, 31 GB of memory and an Intel Iris Xe (no CUDA), so a model must run on the CPU.

| model | licence | size | Hebrew text, nikud, terms | runs here |
|---|---|---|---|---|
| BlueTTS, BlueV3[^blue][^blue-bundle] | code and weights MIT; the RenikudPlus G2P Apache-2.0[^renikud]; the 15 voices CC BY 4.0 (LibriTTS-R speakers); the vocoder OpenRAIL-M | 0.5 GB used here (int8, no cloning encoder); the full bundle 3.5 GB | RenikudPlus reads unvocalised Hebrew and writes IPA with stress; it ignores nikud in the text; IPA can be given directly (`text_is_phonemes`) | yes: measured, §6 |
| Chatterbox Multilingual[^chatterbox] | MIT; output watermarked | 3.2 GB PyTorch (the model and the decoder), or about 1.5 GB as the community's 4-bit ONNX | Hebrew is one of 23 languages; nikud not mentioned; a reference clip in another language carries its accent | CPU possible, slow (inferred: a 0.5 billion parameter model); not run |
| Pocket TTS Hebrew[^pocket] | CC BY 4.0 (the export); the Hebrew adapter's data not stated | 0.23 GB plus a 21 MB G2P | text with nikud is kept as typed; `[[...]]` takes IPA; unvocalised text goes through a G2P | yes (inferred: made for the CPU); not run |
| Phonikud TTS (Piper, StyleTTS2)[^phonikud] | checkpoints "non commercial (cc-nc)"; trained on SASPEECH and ILSpeech, both non-commercial | small (Piper voices) | Phonikud adds nikud and stress, then IPA; its G2P is CC BY 4.0 on PyPI, "other" on GitHub (second-hand)[^phonikud-g2p] | yes; not run |
| Piper `he_IL-saspeech-medium`[^piper] | SASPEECH: non-commercial, © Kan[^saspeech] | a Piper medium voice | stress on the last syllable of most words unless IPA is written by hand ([sound.md](../sound.md) §5.4) | yes; tested 2 November 2026 |
| Robo-Shaul (Tacotron 2 and others)[^roboshaul] | trained on SASPEECH: non-commercial | — | needs nikud | yes; not run |
| MMS-TTS heb[^mms] | CC-BY-NC 4.0 | 36.3 M parameters | reads the letters as written; the card says nothing on nikud | yes; not run |
| HebTTS, LoTHM[^hebtts] | HebTTS: no licence file; trained on HebDB (CC BY 4.0, podcasts) | a checkpoint on Google Drive | made for text without nikud | GPU code (inferred); not run |

**The training data.** BlueTTS does not state what its Hebrew was trained on (open); a third-party mirror tags a
Hebrew model of the same author with a dataset named after a podcast host (second-hand)[^lightblue]. The licences of the files we would
use are open ones; whether the training data limits the output is open for BlueTTS, Chatterbox and Pocket TTS alike,
as for most TTS models.

**Military terms and acronyms** through RenikudPlus (measured 20 November 2026): מכ"ם → makˈam, בד"ח → badˈaχ,
בינגו → bˈinɡo, ג'וקר → dʒˈokeʁ, רוג'ר → ʁˈodʒeʁ: as Hebrew speakers say them. חמש → χamˈeʃ (the formal stress; the
hand-written IPA in `voices.json` has the everyday χˈameʃ). אווקס → ʔavˈeks (check by ear). במקום depends on its
neighbours: "המתנה במקום" → bamakˈom (in place), but "אלפא שתיים, במקום" → bimkˈom ("instead"), wrong; nikud in the
text did not change it; the IPA line fixed it (sample 3b, §6).

## 5. Callsigns, numbers and runways: parts or whole calls

Today a call plays the longest run of its keys that has a joined clip; the training missions' calls are whole
clips, and other calls join a head ("Alpha, good morning, taxi to runway") and a runway ("two five right"). The head
and the runway are cut from one sentence at Kokoro's word times ([sound.md](../sound.md) §3). Hebrew keeps the same
structure (inferred):
- **The words.** Digits are said one by one in the counting forms, as `voices.json`'s Hebrew lines already do
  ("מסלול שתיים חמש ימני"), so a number never agrees with a noun. Prefixes join the next word (ל-, ב-: "למסלול"), so
  a cut falls between words, never inside one. A head ends on "מסלול", a runway is "שתיים חמש ימני".
- **Word times by engine.** Kokoro (today): yes, but no Hebrew. Azure: WordBoundary[^az-wb]. ElevenLabs v3: character
  times[^el-ts]. Soniox: character timestamps, by its page[^soniox]. Google Chirp 3 HD and Gemini TTS: none in their
  documents (open). OpenAI: none found (open). BlueTTS: none (inferred: its model predicts one length for the whole
  sentence).
- **Without word times.** Make each part as its own line (a head said alone ends falling, not rising: inferred), or
  cut at a pause: E1c cut Piper's sentences at a ";" found by the level and a third of the runways came out wrong
  ([sound.md](../sound.md) §2), or align the text to the audio with a forced aligner (inferred). The whole calls the
  training missions use stay whole clips in every engine.
- **Delivery.** Gemini TTS can be asked for a delivery in words and tags (§3.1); ElevenLabs v3's delivery controls were
  not checked (open); BlueTTS has no style control, its delivery comes from the voice and a speed setting[^blue].
  The radio chain's band-pass, compressor and hiss give every engine the same radio sound.

## 6. Listening samples (20 November 2026)

The user, 19 November 2026: "End with examples on the approval page". The Approvals page, section A73, has five
radio calls in Hebrew from BlueTTS, each clean and through the game's radio chain, the first call in all 15
BlueTTS voices, and the IPA fix of call 3. Files: the page only, not the repository.

| # | role, BlueTTS voice | call |
|---|---|---|
| 1 | tower, david | אלפא אחת, מגדל רמון, מסלול שתיים חמש ימני, רוח שקטה, מאושר להמראה. |
| 2 | the player, adam | מגדל רמון, אלפא אחת, בקשה להתנעה. |
| 3 | wingman, ariel | אלפא שתיים, במקום. (3b: the same from IPA, "bamakˈom") |
| 4 | AWACS, michael | אלפא אחת, מגע, כיוון שלוש שלוש אפס, טווח ארבעים מייל, גובה עשרים אלף רגל. |
| 5 | wingman, ariel | שתיים, נעילה! שבירה שמאלה! |

- **Measured, not heard by us:** 0.5–1.1 s to make each call (6.5 s of speech in 1.1 s), 0.9 s to load, 31 s for
  the whole run of 25 files (most of it the radio filter in plain Python); the radio version of call 1 at −19.8 LUFS, peak −2.9 dBFS, inside the game's range for radio clips
  ([sound.md](../sound.md) §8).
- **The radio chain** is a numpy copy of `sim_voices.rs` `radio()` with the key clicks (its noise from numpy's
  generator, not the Rust one); the page's files are 22050 Hz mono MP3.
- **Cloud samples were not made:** each service needs an account and a key. The page links public Hebrew samples
  instead: Azure's Avri and Hila (through Edge), ElevenLabs v3 and Gemini 2.5 Flash TTS from the March 2025
  test[^rosehill], and the arena, which needs a Hugging Face login to listen and vote[^arena]. No public sample of
  Gemini 3.1 Flash TTS or Chirp 3 HD in Hebrew was found (open).

**Downloaded for the samples** (the user, 19 November 2026: "Online is fine, we can download"), under
`~/.cache/hebrew-tts-eval/`, 0.71 GB in all, outside the repository:

| file | licence | size |
|---|---|---|
| `models/bluev3/onnx/vocoder.onnx` | OpenRAIL-M (a fine-tune of Supertone's Supertonic-3 vocoder) | 101.4 MB |
| `models/bluev3/onnx/vector_estimator.int8.onnx` | MIT | 66.1 MB |
| `models/bluev3/onnx/text_encoder.onnx` | MIT | 28.0 MB |
| `models/bluev3/onnx/duration_predictor_style.onnx` and the small `tts.json`, `vocab.json`, `stats.npz`, `uncond.npz`, `export_check.json` | MIT | 1.6 MB |
| `models/bluev3/voices/*.json` (15 voices) | CC BY 4.0 (LibriTTS-R) | 4.3 MB |
| `models/bluev3/LICENSES.md`, `LICENSE.OpenRAIL-M`, `README.md`, `MANIFEST.json` | — | 0.05 MB |
| `models/renikudplus/model_int8.onnx` and its `README.md` | Apache-2.0 | 311.6 MB |
| `src/BlueTTS/` (the code, git 91b1789) | MIT | 10.4 MB |
| `venv/` (Python 3.12: onnxruntime 1.29.0, numpy, soundfile, renikud-plus 0.5.0, num2words, hebrew-num2words, huggingface_hub and their dependencies) | MIT, BSD, Apache-2.0, LGPL (num2words) | 183.7 MB |

The folder can be deleted once a voice is chosen.

## 7. Recommendation

Try these three, in this order:
1. **Gemini 3.1 Flash TTS** (Google). The best-rated Hebrew in the arena; 30 voices; the delivery can be asked for
   in words; cents for our set; Google claims no ownership and asks for no attribution. Its weak points: Hebrew is
   in Preview, it gives no word times, and the under-18 clause is written for apps that call the API (§3.1).
   Chirp 3 HD, in the same Google account, is the generally available fallback with free volume.
2. **BlueTTS** (open). No account, no cost, runs on this laptop in about a second a call, open licences on every
   file we would use, IPA input for any word it misreads; its previous version already rates above OpenAI's three TTS
   models. Its weak points: no style control, no word times, the training data not stated, and voices made from
   English audiobook readers (listen for an accent).
3. **ElevenLabs v3.** 3rd in the arena, character times for the cuts, the user owns the output; it needs a paid plan
   (6 dollars a month).

Not recommended: Azure (two voices, its output rights found only in a community answer; a fallback), OpenAI (its TTS
models have the lowest Hebrew ratings; a disclosure rule), Polly (no Hebrew), Chatterbox (poor Hebrew in 2025, a licensed
reference clip needed) and every SASPEECH-, ILSpeech- or MMS-trained model (non-commercial).

**Our pick:** Gemini 3.1 Flash TTS for the quality, with BlueTTS as the choice if the user wants no account or
finds its samples good enough. Either way the clips are made once and committed, and the setup only copies them.

**Chosen: BlueTTS** (the user, 20 November 2026, after A73: "Voices you created are awesome. Pick some male some
female and have both"). Built in [sound.md](../sound.md) §3.1; the credits name the voices as machine-generated.

**What the user does:**
- Listen to section A73 and the linked cloud samples, and say which voice.
- For Gemini: a Google account and a Gemini API key from Google AI Studio (or a Cloud project with billing for
  Chirp 3 HD), given to the job as an environment variable, never committed.
- For ElevenLabs: an account, the Starter plan and an API key.
- His word on any further download (for example Chatterbox, 1.5–3.2 GB); the 0.71 GB of §6 is already on disk.
- The chosen voice's credit line goes into the credits ([docs/credits.md](../../../docs/credits.md), the setup
  wizard's attributions, the credits roll), with the note that the voices are machine-generated (OpenRAIL-M
  Attachment A (e)[^blue-bundle], OpenAI's and Microsoft's disclosure rules).

[^g-voices]: Google Cloud, "Supported voices and languages", read 20 November 2026 (he-IL: 30 Chirp 3 HD, WaveNet A–D,
    Standard A–D, with each voice's gender): https://docs.cloud.google.com/text-to-speech/docs/list-voices-and-types
[^g-chirp]: Google Cloud, "Chirp 3: HD voices" (SSML tags, speaking rate 0.25–2.0; pause control and custom
    pronunciations "not available" for he-IL): https://docs.cloud.google.com/text-to-speech/docs/chirp3-hd
[^g-gemini]: Google Cloud, "Gemini-TTS" (models gemini-3.1-flash-tts-preview, gemini-2.5-flash-tts, gemini-2.5-pro-tts;
    Hebrew he-IL in Preview; 30 voices; natural-language style prompts and markup tags; billing must be enabled, no
    charge under the free quota): https://docs.cloud.google.com/text-to-speech/docs/gemini-tts
[^g-price]: Google Cloud, "Text-to-Speech pricing": the page did not render for our tool; from search quotes of its
    French and Italian copies (second-hand): Chirp 3 HD 0–1 million characters free a month, then 30 dollars a million:
    https://cloud.google.com/text-to-speech/pricing
[^g-terms]: Google Cloud, "Service Specific Terms", last modified 2 April 2026 (§17 AI/ML restrictions; §20(a)
    "Google does not assert any ownership rights in any new intellectual property created in the Generated Output";
    §20(d) under-18 services): https://cloud.google.com/terms/service-terms
[^gemini-terms]: Google, "Gemini API Additional Terms of Service" ("Google won't claim ownership over that content"; no
    competing models; API clients for people under 18; unpaid services' data use):
    https://aistudio.google.com/docs/terms
[^gemini-price]: Gemini 3.1 Flash TTS prices, second-hand (search quotes of OpenRouter's listing and a developer guide:
    1 dollar a million text tokens, 20 dollars a million audio tokens, 25 audio tokens a second):
    https://openrouter.ai/google/gemini-3.1-flash-tts-preview
[^arena]: ivrit.ai, "TTS Arena Hebrew", leaderboard read 20 November 2026 (Gemini 3.1 Flash TTS 1584, Deepdub
    dd-etts-3.3 1577, ElevenLabs v3 1545, Soniox v1 1543, OpenAI Realtime 1.5 1503, Inworld TTS v1 1491, Inworld TTS-2
    1489, Blue V2 1476, Inworld TTS v1.5 MAX 1473, OpenAI GPT-4o Mini TTS 1451, TTS-1 HD 1447, TTS-1 1415) and its
    about page (blind pairwise votes, Elo, a Hugging Face login to vote):
    https://ivrit-ai-tts-arena-hebrew.hf.space/leaderboard, https://ivrit-ai-tts-arena-hebrew.hf.space/about
[^rosehill]: Daniel Rosehill, "Hebrew-TTS-Providers", a snapshot of 22 March 2025 (MiniMax best; Edge TTS Avri and
    Hila good; Gemini 2.5 Flash Preview TTS good; ElevenLabs v3 good, Multilingual v2 unintelligible; Chatterbox and
    Resemble poor), and its samples page: https://github.com/danielrosehill/Hebrew-TTS-Providers,
    https://danielrosehill-hebrew-tts-samples.static.hf.space/index.html
[^el-lang]: ElevenLabs, "What languages do you support?" (Hebrew in Eleven v3; Multilingual v2's 29 and Flash v2.5's
    32 languages without it): https://elevenlabs.io/docs/help-center/other/what-languages-do-you-support
[^el-terms]: ElevenLabs, "Terms of Service" (§1(c) free users non-commercial, paid users commercial; §4(c)(ii) the
    user retains all rights in the Output): https://elevenlabs.io/terms-of-use
[^el-price]: ElevenLabs, "Pricing" (Free 10,000 credits without a commercial licence; Starter 6 dollars, 1 dollar
    the first month, 30,000 credits, commercial licence): https://elevenlabs.io/pricing. Credits a character for v3,
    second-hand (third-party guides: about one): https://developer.puter.com/tutorials/elevenlabs-api-pricing/
[^el-ts]: ElevenLabs API, "Create dialogue with timestamps" (model_id defaults to eleven_v3; a timestamp for each
    character): https://elevenlabs.io/docs/api-reference/text-to-dialogue/convert-with-timestamps
[^az-voices]: Microsoft Learn, "Language and voice support for the Speech service" (he-IL: HilaNeural female,
    AvriNeural male): https://learn.microsoft.com/en-us/azure/ai-services/speech-service/language-support?tabs=tts
[^az-price]: Microsoft Azure, "Speech pricing" (0.5 million characters free a month; the per-million figures showed
    as "$-"): https://azure.microsoft.com/en-us/pricing/details/cognitive-services/speech-services/
[^az-coc]: Microsoft Learn, "Code of conduct for Azure AI Speech text to speech" (prebuilt, custom and avatar voices):
    https://learn.microsoft.com/en-us/legal/cognitive-services/speech-service/tts-code-of-conduct
[^az-qa]: Microsoft Q&A, "Can audio generated with Azure Text-to-Speech be publicly redistributed?", an accepted
    answer by a volunteer moderator, not Microsoft staff: https://learn.microsoft.com/answers/a/12933078
[^az-wb]: Microsoft Learn, "How to synthesize speech from text" (the WordBoundary event: each word's time offset from
    the start of the audio): https://learn.microsoft.com/en-us/azure/ai-services/speech-service/how-to-speech-synthesis
[^polly]: Amazon, "Languages in Amazon Polly" (no Hebrew):
    https://docs.aws.amazon.com/polly/latest/dg/supported-languages.html
[^oai-guide]: OpenAI, "Text to speech" guide (Hebrew in the list; "Voices are currently optimized for English"; 13
    voices; the disclosure rule): https://developers.openai.com/api/docs/guides/text-to-speech
[^oai-price]: OpenAI, model pages TTS-1 (15 dollars a million characters) and GPT-4o mini TTS (0.60 dollars a million
    text tokens, 12 dollars a million audio tokens): https://developers.openai.com/api/docs/models/tts-1,
    https://developers.openai.com/api/docs/models/gpt-4o-mini-tts
[^oai-terms]: OpenAI, "Terms of Use" ("you (a) retain your ownership rights in Input and (b) own the Output. We hereby
    assign to you all our right, title, and interest, if any, in and to Output"). Second-hand: the site answered our
    tool with HTTP 403, so the quote is a search engine's: https://openai.com/policies/row-terms-of-use/
[^soniox]: Soniox, Hebrew text to speech (voice cloning, character-level timestamps, price on request):
    https://soniox.com/text-to-speech/hebrew
[^cartesia]: Cartesia, Hebrew (Sonic models): https://cartesia.ai/languages/hebrew
[^blue]: BlueTTS, GitHub repository at 91b1789 (19 November 2026): MIT; Hebrew and six other languages; 15 voices;
    cloning from about 10 s; CPU through ONNX Runtime; no emotion or style control:
    https://github.com/maxmelichov/BlueTTS
[^blue-bundle]: BlueV3 ONNX bundle, its LICENSES.md (RenikudPlus Apache-2.0; voices from LibriTTS-R speakers, CC BY
    4.0; the vocoder fine-tuned from Supertonic-3, OpenRAIL-M) and LICENSE.OpenRAIL-M (§6 "Licensor claims no rights in
    the Output You generate"; Attachment A (e) content must be disclosed as machine generated):
    https://huggingface.co/notmax123/BlueV3-onnx
[^renikud]: RenikudPlus, model card (Apache-2.0; Hebrew text to IPA with stress; 93.3 % word accuracy on 126,000
    words of podcast speech, the authors' own figure; an int8 copy 4× smaller): https://huggingface.co/notmax123/RenikudPlus
[^chatterbox]: Resemble AI, Chatterbox model card (MIT; 23 languages with Hebrew; 0.5 B parameters; the PerTh
    watermark on every file; the accent of a reference clip in another language carries over) and file list:
    https://huggingface.co/ResembleAI/chatterbox/blob/main/README.md; the community ONNX export:
    https://huggingface.co/onnx-community/chatterbox-multilingual-ONNX
[^pocket]: thewh1teagle, pocket-tts-onnx (Kyutai's Pocket TTS on ONNX Runtime; CC BY 4.0; `pocket-tts-english-ipa.onnx`
    231 MB with the Hebrew IPA adapter and a Hebrew voice; renikud 21 MB; the usage notes on nikud and IPA):
    https://huggingface.co/thewh1teagle/pocket-tts-onnx, https://github.com/thewh1teagle/pocket-tts-onnx
[^phonikud]: Phonikud, "Explore" page (Phonikud-TTS "non-commercial license"; ILSpeech, two male speakers, about 2 h;
    SASpeech), the TTS checkpoints' card ("non commercial (cc-nc)") and ILSpeech's card ("Non commercial"):
    https://phonikud.github.io/explore.html, https://huggingface.co/Phonikud/phonikud-tts-checkpoints,
    https://huggingface.co/datasets/Phonikud/ILSpeech
[^phonikud-g2p]: Phonikud G2P licence, second-hand (search engine summaries of its PyPI page, "CC BY 4.0", and
    of its GitHub listing, "other"): https://pypi.org/project/phonikud/, https://github.com/thewh1teagle/phonikud
[^piper]: Piper voices, Hebrew folder (one voice, saspeech): https://huggingface.co/rhasspy/piper-voices/tree/main/he/he_IL
[^saspeech]: OpenSLR, "SASPEECH" (SLR134), the custom non-commercial licence: https://www.openslr.org/134/
[^lightblue]: niobures/LightBlue, a third-party mirror's model card with the dataset tag notmax123/RanLevi40h. Second-hand
    (a search engine's quote): https://huggingface.co/niobures/LightBlue/blob/main/README.md
[^roboshaul]: Robo-Shaul, Tacotron 2 on SASPEECH: https://github.com/maxmelichov/Text-To-speech
[^mms]: Meta, MMS-TTS Hebrew, model card (CC-BY-NC 4.0; VITS; 36.3 M parameters):
    https://huggingface.co/facebook/mms-tts-heb
[^hebtts]: HebTTS, GitHub (no licence file; trained on HebDB; checkpoint on Google Drive; a speaker prompt "shaul"):
    https://github.com/slp-rl/HebTTS; LoTHM: https://pages.cs.huji.ac.il/adiyoss-lab/LoTHM/; HebDB (CC BY 4.0, six
    podcast and archive sources, about 2,500 h): https://huggingface.co/datasets/SLPRL-HUJI/HebDB
