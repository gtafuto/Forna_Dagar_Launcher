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
- L'accesso avviene tramite una **GitHub App** con il solo permesso di **lettura dei contenuti**: il token non puo mai modificare i repository, nemmeno per un utente che ne e collaboratore con diritto di scrittura.
- Ogni versione va in una cartella propria (`%LOCALAPPDATA%\FornaDagarLauncher\apps\<gioco>\<versione>\`): si puo aggiornare anche a gioco aperto e la versione precedente resta per il ripristino ("Torna alla ...").
- Mazzi e impostazioni non stanno in quelle cartelle (i giochi li salvano in Documenti): un aggiornamento non li tocca.
- Lo zip scaricato viene verificato (dimensione e SHA-256) prima dell'installazione.
- Il token di accesso e salvato **cifrato con la protezione di Windows**: e leggibile solo dallo stesso utente sullo stesso PC.
- Nessuna dipendenza oltre a Flutter.

## Impostazione una tantum (per chi gestisce il progetto)

### 1. La GitHub App
GitHub, foto profilo, **Settings > Developer settings > GitHub Apps > New GitHub App**:

| Campo | Valore |
|---|---|
| GitHub App name | Forna Dagar Launcher |
| Homepage URL | l'indirizzo di questo repository |
| Callback URL | vuoto (se richiesto: `http://localhost`) |
| Expire user authorization tokens | **senza spunta** (altrimenti l'accesso scade ogni 8 ore) |
| Enable Device Flow | **con spunta** |
| Webhook, Active | senza spunta |
| Repository permissions > Contents | **Read-only** |
| Where can this GitHub App be installed | Only on this account |

Poi, dalla pagina dell'app:
1. Copia il **Client ID** (inizia per `Iv`): non e un segreto. E gia impostato in `lib/config.dart` (`githubClientId`); si puo cambiare con `--dart-define=GITHUB_CLIENT_ID=...`. **Non generare** ne il Client secret ne la Private key: non servono.
2. **Install App** > Install sul tuo account > *Only select repositories* > i 3 repository (`Forna_Dagar_Card_Game`, `Card_Game`, `Forna_Dagar_Launcher`).

### 2. Invitare gli amici
In **ognuno dei 3 repository** (Settings > Collaborators > Add people). Su un account personale GitHub non offre il ruolo "Read": i collaboratori hanno accesso normale, ma il token del launcher resta in sola lettura grazie alla GitHub App. Chi ha accesso vede anche il codice sorgente.

Ognuno deve avere un account GitHub (gratuito) e **accettare gli inviti** (arrivano per email).

## Pubblicare una versione

Da un repository (gioco o launcher), sul commit che si vuole pubblicare:

```
git tag v0.1.1
git push origin v0.1.1
```

La build parte da sola (10-15 minuti) e alla fine c'e una Release con lo zip e il manifest. In alternativa: scheda **Actions > Release Windows > Run workflow**.
Per una prova usa un tag di test, es. `v0.0.1-test1`. Non servono secret.

## Prima installazione per gli amici

Dopo aver accettato gli inviti, dalla pagina **Releases** di `Forna_Dagar_Launcher` scaricano `forna_dagar_launcher-windows.zip`, lo scompattano in una cartella qualsiasi e avviano `forna_dagar_launcher.exe`. Poi "Accedi con GitHub" e tutto il resto e automatico.

## Sviluppo

```
flutter pub get
flutter analyze
flutter test
flutter run -d windows
```

Per aggiungere un gioco: una voce in `lib/config.dart` (con il suo `repo`), il workflow `release-windows.yml` nel suo repository (con `APP_ID` uguale all'`id`) e l'app installata su quel repository.

## Limiti noti

- Il launcher non si aggiorna da solo (per ora): va ridistribuito a mano se cambia.
- Le build non sono firmate: se Windows SmartScreen avvisa per il launcher, "Ulteriori informazioni > Esegui comunque". I giochi scaricati dal launcher non hanno il contrassegno di provenienza web e di norma non mostrano l'avviso.
- Solo Windows. Android non e coperto.
- Il salvataggio cifrato del token usa PowerShell di Windows: non e verificabile fuori da Windows.
- Se l'opzione "Expire user authorization tokens" resta attiva, l'accesso scade dopo 8 ore e il launcher chiede di accedere di nuovo.
