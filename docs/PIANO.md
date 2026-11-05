# Piano tecnico

Approvato il 2026-11-05. Decisioni: si lavora sul Mac; il client è una pagina web in
Safari, con certificato locale installato una volta tramite codice QR.

## Cattura
- ScreenCaptureKit, `SCContentFilter(desktopIndependentWindow:)`: solo la finestra,
  anche coperta o su un altro Space.
- Elenco finestre con `onScreenWindowsOnly: false`; Capture One preselezionato.
- Finestra ridotta nel Dock: probabilmente nessun fotogramma. Da verificare con
  `Tools/CaptureProbe`.
- Piano B: display virtuale creato dall'app (API privata `CGVirtualDisplay`, adatta
  alla firma locale) su cui tenere il Live View; ripiego: Space dedicato.

## Codifica
- VideoToolbox H.264/HEVC, bassa latenza: niente B-frame, keyframe frequenti,
  bitrate modificabile a caldo. IOSurface da ScreenCaptureKit all'encoder senza copie.

## Trasporto
- Predefinito: WebCodecs (`VideoDecoder`) su WebSocket, rendering su canvas
  (zoom senza latenza aggiunta).
- Confronto: WebRTC. Ripiego: MSE con fMP4 brevi.
- Server integrato con Network.framework (HTTPS + WebSocket), Bonjour, QR.

## HTTPS
WebCodecs e Wake Lock richiedono un contesto sicuro. L'app genera una CA locale e un
certificato per il Mac; l'iPad scarica il profilo dal QR e lo abilita in
Impostazioni → Generali → Info → Impostazioni certificati.

## Misura della latenza
Timestamp per fase in ogni pacchetto (cattura, codifica, invio, ricezione,
decodifica, visualizzazione) con sincronizzazione degli orologi Mac/iPad, più un
orologio con i millisecondi sul Mac da fotografare insieme all'iPad.

## Fasi
1. Test di cattura (6 bis) — `Tools/CaptureProbe`
2. Prototipo minimo con misura della latenza
3. Confronto WebCodecs / WebRTC
4. Funzioni complete
5. Ottimizzazione
6. Prova di lunga durata
