# TeamCheck

App Android per il registro presenze della scuola calcio San Frediano:
calendario degli allenamenti, appello, gestione delle classi e report mensile
da mandare via WhatsApp.

- Codice: [lib/main.dart](lib/main.dart)
- **Come compilare, installare e aggiornare l'APK sul telefono:
  [AGGIORNAMENTO.md](AGGIORNAMENTO.md)**

## Come funziona

- La stagione va da settembre a giugno e si aggiorna da sola ogni anno.
- Gli allenamenti abituali sono il **lunedì e il mercoledì**; ogni singolo
  allenamento si può annullare, spostare o aggiungere dal giorno del calendario.
- L'appello si può fare il giorno stesso o nei giorni passati, mai in anticipo.
- I dati stanno **solo dentro il telefono** (`SharedPreferences`, chiave
  `sanfrediano`). Da *Impostazioni e backup* si salva o si ripristina una copia
  in formato JSON: falla ogni tanto, e sempre prima di cambiare telefono.

## Sviluppo

```bash
flutter pub get
flutter run
flutter analyze
flutter test
```

Per riempire l'app di dati finti durante le prove:

```bash
flutter run --dart-define=LOAD_TEST_DATA=true
```
