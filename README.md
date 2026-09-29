# Forna Dagar Launcher

Piccola app Windows che permette di scegliere tra **Forna Dagar** e **Card Game**, li scarica e li aggiorna da soli quando esce una nuova versione, senza passare lo zip a mano.

## Come funziona

```
merge/tag su un gioco --> GitHub Actions compila Windows --> Supabase Storage (bucket app-releases)
                                                                 |-- <gioco>/<versione>/<gioco>-windows.zip
                                                                 '-- <gioco>/latest.json   (manifest)
Launcher --> legge latest.json --> se la versione e diversa da quella installata: "Aggiorna"
```

- Ogni versione va in una cartella propria (`%LOCALAPPDATA%\FornaDagarLauncher\apps\<gioco>\<versione>\`): si puo aggiornare anche a gioco aperto e la versione precedente resta per il ripristino ("Torna alla ...").
- Mazzi e impostazioni non stanno in quelle cartelle (i giochi li salvano in Documenti): un aggiornamento non li tocca.
- Il file scaricato viene verificato con SHA-256 prima dell'installazione.
- Nessuna dipendenza oltre a Flutter.

## Impostazione una tantum

### 1. Utente Supabase dedicato alle pubblicazioni
Dashboard Supabase, progetto `Card_Game`: **Authentication > Users > Add user** (con "Auto Confirm User"). Email e password a piacere: servono solo alla CI. Poi va aggiunta la policy che gli permette di scrivere **solo** nel bucket `app-releases` (gia creato).

### 2. Secret GitHub (in ognuno dei 3 repository)
Settings > Secrets and variables > Actions > New repository secret:

| Secret | Valore |
|---|---|
| `SUPABASE_URL` | `https://dibmgtxqxychdsazgodw.supabase.co` |
| `SUPABASE_ANON_KEY` | chiave anon/publishable (Supabase > Project Settings > API Keys) |
| `RELEASE_CI_EMAIL` | email dell'utente creato al punto 1 |
| `RELEASE_CI_PASSWORD` | la sua password |

## Pubblicare una versione

Da un repository (gioco o launcher), sul ramo che si vuole pubblicare:

```
git tag v0.1.1
git push origin v0.1.1
```

La build parte da sola (10-15 minuti) e alla fine il gioco e su Supabase. In alternativa: scheda **Actions > Release Windows > Run workflow**.
Per una prova usa un tag di test, es. `v0.0.1-test1`.

## Prima installazione per gli amici

Il launcher stesso si distribuisce una volta sola. Dopo la prima pubblicazione del launcher lo zip e a:

```
https://dibmgtxqxychdsazgodw.supabase.co/storage/v1/object/public/app-releases/forna_dagar_launcher/<versione>/forna_dagar_launcher-windows.zip
```

Si scompatta in una cartella qualsiasi e si avvia `forna_dagar_launcher.exe`.

## Sviluppo

```
flutter pub get
flutter analyze
flutter test
flutter run -d windows
```

Per aggiungere un gioco: una riga in `lib/config.dart` e il workflow `release-windows.yml` nel suo repository (con `APP_ID` uguale all'`id` in `config.dart`).

## Limiti noti

- Il launcher non si aggiorna da solo (per ora): va ridistribuito a mano se cambia.
- Le build non sono firmate: se Windows SmartScreen avvisa per il launcher, "Ulteriori informazioni > Esegui comunque". I giochi scaricati dal launcher non hanno il contrassegno di provenienza web e di norma non mostrano l'avviso.
- Solo Windows. Android non e coperto.
