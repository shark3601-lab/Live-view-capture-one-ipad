# Live View Mirror per Capture One su iPad

Mirroring a bassa latenza della finestra Live View di Capture One (Mac) verso un iPad,
in rete locale, senza internet. Il client è una pagina web in Safari.

Stato: **fase 1 — test di cattura** (sezione 6 bis della specifica). Il piano è in
[`docs/PIANO.md`](docs/PIANO.md).

## Fase 1: test di cattura con CaptureProbe

Serve a verificare, sul tuo Mac e con la tua versione di Capture One, se la finestra
del Live View si può catturare quando non è in primo piano.

Requisiti: macOS 14 o successivo, Xcode (o i Command Line Tools) installato.

```bash
cd Tools/CaptureProbe
swift run -c release CaptureProbe list     # elenca le finestre, anche quelle su altri Space
swift run -c release CaptureProbe watch    # osserva la finestra Live View di Capture One
```

Al primo avvio macOS chiede il permesso di **Registrazione schermo**: concedilo al
Terminale in Impostazioni di Sistema → Privacy e sicurezza → Registrazione schermo e
audio, poi riapri il Terminale e rilancia.

Con `watch` in esecuzione e il Live View attivo, prova uno scenario alla volta per
circa 10 secondi e annota cosa stampa:

| Scenario | Cosa guardare |
|---|---|
| 1. Finestra su un altro Space | `complete` circa 30 al secondo e `diversi` > 0 = funziona |
| 2. Finestra coperta da altre finestre | come sopra |
| 3. Finestra ridotta nel Dock | `nessun fotogramma` o `CONGELATO` = non catturabile |
| 4. Finestra su un altro display | come sopra |
| 5. Tu a schermo intero su un altro Space | come sopra |

Colonne: `complete` fotogrammi nuovi, `idle` nessun cambiamento, `blank`/`susp`
fotogrammi vuoti o sospesi, `diversi` quanti avevano pixel diversi dal precedente
(se resta 0 l'immagine è congelata).

Per osservare una finestra precisa: `watch <ID>`, con l'ID preso da `list`.
