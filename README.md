# Forna Dagar Launcher

Piccola app Windows che permette di scegliere tra **Forna Dagar** e **Card Game**, li scarica e li aggiorna da soli quando esce una nuova versione, senza passare lo zip a mano.

## Come funziona

```
tag v0.1.1 su un gioco --> GitHub Actions compila Windows --> Release di GitHub del repository
                                                                 |-- <gioco>-windows.zip
                                                                 '-- manifest.json (versione, SHA-256, dimensione)
Launcher --> "Accedi con GitHub" (una volta) --> legge l'ultima Release --> se la versione e diversa: "Aggiorna"
```

- I repository sono **privati**: il launcher scarica con l'accesso GitHub di ciascun utente (nessuna password passa dal launcher, e nessun token va copiato a mano).
- Ogni versione va in una cartella propria (`%LOCALAPPDATA%\FornaDagarLauncher\apps\<gioco>\<versione>\`): si puo aggiornare anche a gioco aperto e la versione precedente resta per il ripristino ("Torna alla ...").
- Mazzi e impostazioni non stanno in quelle cartelle (i giochi li salvano in Documenti): un aggiornamento non li tocca.
- Lo zip scaricato viene verificato (dimensione e SHA-256) prima dell'installazione.
- Il token di accesso e salvato **cifrato con la protezione di Windows**: e leggibile solo dallo stesso utente sullo stesso PC.
- Nessuna dipendenza oltre a Flutter.

## Impostazione una tantum (per chi gestisce il progetto)

### 1. Registrare l'OAuth App su GitHub
GitHub, in alto a destra la tua foto, **Settings > Developer settings > OAuth Apps > New OAuth App**:

| Campo | Valore |
|---|---|
| Application name | Forna Dagar Launcher |
| Homepage URL | l'indirizzo di questo repository |
| Authorization callback URL | `http://localhost` (non viene usato, ma il campo e obbligatorio) |

Dopo **Register application**:
1. Attiva **Enable Device Flow** (casella nella pagina dell'app) e salva.
2. Copia il **Client ID** (non e un segreto). **Non serve generare nessun Client secret.**
3. Inseriscilo in `lib/config.dart` (`githubClientId`), oppure passalo alla build con `--dart-define=GITHUB_CLIENT_ID=...`.

### 2. Invitare gli amici
In **ognuno dei 3 repository** (Settings > Collaborators > Add people), con ruolo **Read**:
`Forna_Dagar_Card_Game`, `Card_Game`, `Forna_Dagar_Launcher`.
Con il ruolo Read il token del launcher puo solo leggere, mai modificare. Attenzione: chi ha accesso in lettura vede anche il codice sorgente.

Ognuno deve avere un account GitHub (gratuito) e **accettare l'invito** (arriva per email).

## Pubblicare una versione

Da un repository (gioco o launcher), sul commit che si vuole pubblicare:

```
git tag v0.1.1
git push origin v0.1.1
```

La build parte da sola (10-15 minuti) e alla fine c'e una Release con lo zip e il manifest. In alternativa: scheda **Actions > Release Windows > Run workflow**.
Per una prova usa un tag di test, es. `v0.0.1-test1`. Non servono secret.

## Prima installazione per gli amici

Dopo aver accettato l'invito, dalla pagina **Releases** di `Forna_Dagar_Launcher` scaricano `forna_dagar_launcher-windows.zip`, lo scompattano in una cartella qualsiasi e avviano `forna_dagar_launcher.exe`. Poi "Accedi con GitHub" e tutto il resto e automatico.

## Sviluppo

```
flutter pub get
flutter analyze
flutter test
flutter run -d windows
```

Per aggiungere un gioco: una voce in `lib/config.dart` (con il suo `repo`) e il workflow `release-windows.yml` nel suo repository (con `APP_ID` uguale all'`id`).

## Limiti noti

- Il launcher non si aggiorna da solo (per ora): va ridistribuito a mano se cambia.
- Le build non sono firmate: se Windows SmartScreen avvisa per il launcher, "Ulteriori informazioni > Esegui comunque". I giochi scaricati dal launcher non hanno il contrassegno di provenienza web e di norma non mostrano l'avviso.
- Solo Windows. Android non e coperto.
- Il salvataggio cifrato del token usa PowerShell di Windows: non e verificabile fuori da Windows.
