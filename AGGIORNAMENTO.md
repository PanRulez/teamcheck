# Come installare e aggiornare TeamCheck sul telefono di babbo

## 0. Una volta sola: crea la chiave di firma

Ogni APK Android e' firmato con una chiave. **Android accetta un aggiornamento
solo se e' firmato con la STESSA chiave dell'app gia' installata.** Se la chiave
cambia, l'aggiornamento non si installa e l'unico modo e' disinstallare l'app,
perdendo tutte le presenze salvate.

Fino a ora il progetto usava la chiave di *debug* generata da Android Studio
(`C:\Users\panif\.android\debug.keystore`): non e' recuperabile, si perde se
reinstalli Android Studio o cambi PC. Quindi si crea una chiave tua, definitiva.

Il comando va lanciato in **un terminale tuo** (PowerShell o il prompt di
Windows), non da dentro un assistente: chiede la password in modo interattivo,
e cosi' la password non finisce scritta da nessuna parte.

```
mkdir "%USERPROFILE%\Documents\chiavi-teamcheck"
keytool -genkeypair -v -keystore "%USERPROFILE%\Documents\chiavi-teamcheck\teamcheck-release.jks" -keyalg RSA -keysize 2048 -validity 10000 -alias teamcheck
```

(su PowerShell al posto di `%USERPROFILE%` scrivi `$env:USERPROFILE`)

Ti chiede, in ordine:

1. **la password del keystore** (almeno 6 caratteri) e la conferma — mentre la
   digiti non si vede niente sullo schermo, e' normale;
2. nome e cognome, unita' organizzativa, organizzazione, citta', provincia,
   codice paese: sono dati che finiscono nel certificato e non li vede nessuno,
   puoi lasciarli vuoti battendo Invio, oppure mettere il tuo nome e `IT`;
3. una conferma finale tipo `Il valore di CN=... e' corretto?` — rispondi `si`
   (di default e' `no`).

Il keystore e' in formato PKCS12, quindi la password della chiave e quella del
keystore sono la stessa: nel file qui sotto la scrivi due volte.

Poi crea il file `android/key.properties` (c'e' il modello in
`android/key.properties.esempio`) con dentro:

```
storePassword=LA_TUA_PASSWORD
keyPassword=LA_TUA_PASSWORD
keyAlias=teamcheck
storeFile=C:/Users/panif/Documents/chiavi-teamcheck/teamcheck-release.jks
```

> Usa le barre in avanti `/` anche su Windows, e non mettere spazi attorno all'`=`.

**BACKUP OBBLIGATORIO**: copia il file `teamcheck-release.jks` e la password su Google Drive o
una chiavetta. Se li perdi, non potrai piu' aggiornare l'app installata su
quel telefono senza cancellare i dati.

Il file `key.properties` e il `.jks` sono gia' esclusi da git.

## 1. Compilare l'APK

```bash
flutter build apk --release --target-platform android-arm64
```

L'APK esce in `build/app/outputs/flutter-apk/app-release.apk` (~20 MB invece
dei 53 MB della versione universale).

Per controllare che sia firmato con la chiave giusta e non con quella di debug:

```bash
keytool -printcert -jarfile build/app/outputs/flutter-apk/app-release.apk
```

Deve comparire il nome che hai messo tu, non `CN=Android Debug`.

## 2. Prima installazione

1. Manda l'APK a babbo (WhatsApp, Telegram, Drive) oppure collega il telefono
   via USB e usa `flutter install --release`.
2. Sul telefono servira' autorizzare "Installa app sconosciute" per l'app da cui
   apre il file (WhatsApp / File / Chrome).
3. Se sul telefono c'e' gia' una versione firmata con la chiave di debug,
   **va disinstallata prima** (i dati vanno persi). Meglio farlo adesso che a
   stagione iniziata.

## 3. Ogni aggiornamento successivo

1. Alza il numero di versione in `pubspec.yaml`, per esempio:
   `version: 1.2.1+4` → il numero dopo il `+` deve sempre crescere.
2. `flutter build apk --release --target-platform android-arm64`
3. Manda l'APK; babbo lo apre e tocca "Aggiorna".
   **I dati restano**, perche' la firma e il nome pacchetto non cambiano.

## 4. Se vuoi che si aggiorni da solo (consigliato)

Cosi' non devi mandargli un file ogni volta:

1. Il repo git c'e' gia': pubblicalo su GitHub (anche privato) e carica ogni
   APK come **Release**.
2. Sul telefono di babbo installa **Obtainium** (open source, da F-Droid o
   GitHub) e aggiungi l'URL del repo.
3. Obtainium controlla le nuove release e gli propone l'aggiornamento con una
   notifica: lui deve solo toccare "Installa".

In alternativa, se non vuoi GitHub: carica l'APK sempre nello stesso file di
Google Drive e mandagli il link una volta sola.

> Prima di mandargli un aggiornamento importante, fai fare a babbo un backup
> da *Impostazioni e backup* → SALVA UNA COPIA.
