# FluidVoice – Ultra-Fast Offline Vocabulary Correction (≤ 50 ms)
**Scope:** Deterministische, lokale Korrektur von Tech-Vokabular ohne LLM.
**Ziel:** „cloutmd → CLAUDE.md“, „git hub → GitHub“, „a p i → API“ u. ä. in < 50 ms auf typischen Snippets (≤ 500 Wörter).

---

## 1) Anforderungen & Budgets
- **Latenz:** Ziel 5–15 ms, hartes Budget 50 ms (M-Chip, 200–500 Wörter).
- **Determinismus:** Keine Zeit-basierte Abbrüche; gleiche Eingabe → gleiche Ausgabe.
- **Offline/Privacy:** Kein Netzwerk, reine In-Memory-Datenstrukturen.
- **Skalierung:** 100–500 Kanon-Begriffe, je 1–10 Aliasse; Gesamtspeicher < 5–10 MB.
- **Kompatibilität:** DE/EN-Mix, Punkte/Hyphen/Underscore in Tokens.
- **Safety:** Minimierung von False Positives (Wortgrenzen, Code-Fencing, Prioritäten).

---

## 2) Datenmodell

### 2.1 Glossar-Datei (JSON)
```json
{
  "GitHub":    ["git hub", "github", "git-hub"],
  "CLAUDE.md": ["claude md", "cloutmd", "cloude.md", "claude.md"],
  "OAuth":     ["o auth", "oauth", "o-auth"],
  "TypeScript":["type script", "typescript", "type-script"],
  "API":       ["a p i", "api"],
  "gh create": ["g h create", "gh  create", "ghcreate"]
}
2.2 Regeln pro Kanon (optional)
json
Copy code
{
  "GitHub":    {"case":"mixed"},       // exakt "GitHub"
  "CLAUDE.md": {"case":"exact"},       // exakt "CLAUDE.md"
  "API":       {"case":"upper"},       // immer upper
  "TypeScript":{"case":"camel"},       // "TypeScript"
  "OAuth":     {"case":"exact"}        // exakt "OAuth"
}
3) Vorverarbeitung (bei Glossar-Änderung, nicht pro Lauf)
Normalisierungs-Alias-Map bauen

Für jeden Alias eine kanonische Ziel-Form bestimmen.

Alias casefolden (lower), Whitespace normalisieren (ein Space), standardisierte Punkt-/Hyphen-Varianten.

Aho-Corasick (AC) Automat konstruieren

Input: alle Aliasse (case-insensitiv) → AC-States, Failure-Links.

Payload pro Endzustand: targetCanonical, priority, len.

Priorität: längere/mehrwortige Ziele > einwortig (leftmost-longest Absicherung).

Guards vorbereiten

Wortgrenzen-Logik (s. 6.1): lightweight Klassifizierer isWordChar(c).

Code-Fence-Erkenner: Backticks/Triple-Backticks, Inline-Code.

4) Laufzeit-Pipeline (ein Pass je Phase)
4.1 Phase A – Normalisierung (Streaming, O(n))
Unicode NFKC, Trim, Mehrfach-Spaces → ein Space.

Letter-Spacing kleben: Sequenzen aus 2–5 Ein-Buchstaben-Tokens zusammenziehen (a p i → api).

Punkt/Hyphen/Dot-Varianz standardisieren:
claude md → claude.md, git hub → github, type script → typescript.

Implementierung: kleine Zustandsmaschine über UTF-8, kein Regex-Sturm.

4.2 Phase B – Multi-Pattern Replace (Aho-Corasick, O(n))
Ein einziger Scan über den normalisierten Text.

Leftmost-Longest: Bei überlappenden Matches das früheste und längste wählen; bei Gleichstand höchste Priorität (mehrwortig gewinnt).

Wortgrenzen prüfen (falls Alias Wortgrenzen verlangt).

Ersetzen in StringBuilder (Indices sammeln → am Ende schreiben), nicht replacingOccurrences in Schleife.

4.3 Phase C – Guards & Case-Finalisierung (O(n))
Bereiche in `code` / fences überspringen (keine Korrektur darin).

Case-Regeln anwenden: upper, camel, mixed, exact.

Optionales Trimming von doppelten Spaces, minimale Interpunktion (nur wenn sicher).

4.4 Optional Phase D – Fuzzy-Minifallback (strikt limitiert)
Nur wenn kein AC-Match und Token ∈ Whitelist kurzer Kritiker: api, ssh, oidc, url …

Kandidaten via Trigram-Index vorfiltern (gleiches Prefix/Suffix, Länge ±1).

Myers Bit-Parallel Edit Distance (ASCII) mit Distanz ≤ 1. Max 3 Tokens/Text.

Budget: +1–3 ms worst case.

5) AC-Automat – Details
5.1 Aufbau
Knoten: 26–64-Way (ASCII-freundliche Verzweigungen; optional Map für Non-ASCII).

Pro Endknoten: Liste möglicher Ziele (falls mehrere Aliasse enden), sortiert nach (length desc, priority desc).

Failure-Links nach Standard-AC.

5.2 Matching
Input casefolden (lower) für AC; Original-Slices für Replace behalten.

Bei jedem accepting state:

Check Wortgrenzen: links/rechts kein isWordChar, es sei denn Alias erlaubt . - _.

Leftmost-Longest & Priorität anwenden.

Match als (start, end, canonicalId) in Liste ablegen.

5.3 Ersetzen (stabil)
Matches sortieren (start asc, end desc), überlappende verwerfen zugunsten des längsten.

In einem Rutsch: builder.append(text[last:endOfPrev]); builder.append(canonicalForm); …

6) Guards
6.1 Wortgrenzen
isWordChar(c) = [A-Za-z0-9_] (erweiterbar).

Alias-Flag requiresWordBoundaries: true|false; für gh create true, für CLAUDE.md false (weil . enthalten ist).

6.2 Code-Bereiche ausnehmen
Inline: zwischen einzelnen Backticks `…`.

Fences: Zeilen, die mit ``` beginnen/enden.

Einfacher State: inInlineCode, inFenceCode (Fence-Marker merken).

6.3 Case-Finalisierung
upper: API

camel: TypeScript

mixed: exakt gespeicherte Ziel-Schreibweise

exact: 1:1 wie Kanon

7) API-Entwurf
7.1 Initialisierung
swift
Copy code
struct CanonRule { let caseMode: CaseMode /* upper|camel|mixed|exact */ }
struct Glossary {
  // canonical -> aliases[]
  let canonicalMap: [String: [String]]
  let rules: [String: CanonRule]
}

protocol VocabCorrector {
  mutating func load(glossary: Glossary)
  func correct(_ text: String) -> String
}
7.2 Integrationspunkt
Immer an im RAW-Pfad (kosten << 10 ms).

Vor ML-Glättung (falls aktiv), damit LLM nicht „ent-korrigiert“.

Pro App-Profil konfigurierbar: in IDE/Code „nur Dictionary, keine Punktuation“.

8) Pseudocode (vereinfachter Kern)
pseudo
Copy code
function buildAC(glossary):
    patterns = []
    for canonical, aliases in glossary.canonicalMap:
        for alias in aliases:
            norm = normalizeAlias(alias)        // lower, collapse spaces, std dots/hyphens
            patterns.append({norm, canonical, priority=score(canonical)})
    AC = buildAutomaton(patterns)               // create states + failure links
    return {AC, rules: glossary.rules}

function correct(text):
    normText, mapOrig = normalizeStream(text)   // produce normalized view + map to original indices
    matches = scanAC(AC, normText)              // leftmost-longest + priority + word-boundaries
    matches = filterOverlaps(matches)
    out = StringBuilder()
    idx = 0
    for m in matches:
        out.append(text[idx : m.startOrig])     // original slice
        out.append(applyCase(rules[m.canonical], m.canonical))
        idx = m.endOrig
    out.append(text[idx : end])
    final = applyGuards(out.toString())         // code-fences skip already handled during scan; optional final trims
    return final
Hinweis: normalizeStream liefert sowohl eine casefolded/standardisierte Sicht als auch Mapping auf Original-Indices (für korrektes Ersetzen ohne erneutes Scannen).

9) Performance-Instrumentierung
Messen (ns/ms): A-Normalisierung, B-AC-Scan, C-Replace, D-Fuzzy.

P50/P95 pro Phase loggen; Ziel: P95 < 30 ms, P50 < 10 ms.

Counter: matches_total, overlaps_dropped, code_ranges_skipped.

10) Tests (Auszug)
Positive:

"ich nutze git hub und a p i" → "ich nutze GitHub und API"

"cloutmd is great" → "CLAUDE.md is great"

"code with github api" in Backticks → unverändert

"gh create repo" → "gh create repo" oder (wenn gewünscht) "gh create" als Phrase schützen

Negative/Guards:

"capitol" enthält "api" → keine Korrektur

"typescripture" enthält "typescript" → keine Korrektur

Code-Fence-Block bleibt unangetastet

Overlaps:

"claude md" vs "claude" → "CLAUDE.md" gewinnt (länger/mehrwortig)

Case:

"API" bleibt upper, "TypeScript" CamelCase.

11) Edge-Cases & Entscheidungen
Mehrfach-Aliasse gleicher Start/Ende: wähle höchste Priorität.

Unicode jenseits ASCII: casefold per ICU; isWordChar ggf. erweitern (mindestens ASCII stabil halten).

Mehrsprachigkeit: Glossar-Einträge sind domänenspezifisch (Tech); Grammatik bleibt unberührt.

12) Implementationsnotizen (Swift-freundlich, generisch übertragbar)
UTF-8 iterieren, keine Character-Splits in Hot-Path; Indizes als Byte-Offsets, Mapping zur Original-String-Slice.

AC-Automat als struct mit flachen Arrays (cache-freundlich).

Builder: vorreservieren (reserveCapacity(text.count + delta)).

Keine globalen Regexe im Laufzeitpfad; Normalisierung per kleiner FSM.

13) Erweiterungen (optional)
User-UI: „Add to dictionary“ aus Auswahl → persistiert ins JSON, live-Rebuild des AC.

Per-App-Profile: IDE/Terminal: nur Dictionary; Mail/Chat: Dictionary + leichte Punktuation.

Export/Import: Glossar als JSON im App-Support-Ordner.

14) Akzeptanzkriterien
P95 < 30 ms, P50 < 10 ms bei 500-Wörter-Snippets, 500 Kanon-Begriffen × 3 Aliassen.

0 Netzwerkzugriffe, 0 Allokations-Explosion (keine O(#Regeln × n)-Regex-Pipelines).

Deterministische Ergebnisse; Golden-Tests grün; keine Korrekturen in Code-Blöcken.
