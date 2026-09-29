/// Client ID pubblico della **GitHub App** "Forna Dagar Launcher" (GitHub,
/// Settings, Developer settings, GitHub Apps, con "Enable Device Flow" attivo).
/// Non e un segreto: identifica solo l'app, l'utente autorizza comunque con il
/// proprio account.
///
/// Si puo cambiare alla build senza modificare il codice:
/// `flutter build windows --dart-define=GITHUB_CLIENT_ID=...`
const githubClientId = String.fromEnvironment(
  'GITHUB_CLIENT_ID',
  defaultValue: 'Iv23liGNucuGKbpHSehi',
);

/// Falso se il Client ID manca o e ancora il segnaposto: il launcher lo dice
/// chiaramente invece di far fallire l'accesso con un errore di GitHub.
bool get githubClientIdConfigured => githubClientId.isNotEmpty && !githubClientId.startsWith('INSERISCI');

/// Permessi richiesti nell'accesso. Vuoto per una GitHub App: i permessi sono
/// quelli configurati sull'app (qui solo lettura dei contenuti dei repository
/// in cui e installata) e il token non puo mai fare di piu, nemmeno se l'utente
/// e collaboratore con diritto di scrittura. Con una OAuth App servirebbe
/// `repo`, che invece darebbe anche la scrittura.
const githubScope = '';

/// Un gioco che il launcher sa installare e avviare.
class GameEntry {
  /// Deve coincidere con `APP_ID` del workflow di release del gioco.
  final String id;
  final String title;
  final String description;

  /// Repository GitHub che pubblica le Release di questo gioco (`proprietario/nome`).
  final String repo;

  const GameEntry({
    required this.id,
    required this.title,
    required this.description,
    required this.repo,
  });
}

/// Elenco dei giochi mostrati nella schermata iniziale. Aggiungerne uno e
/// una riga qui (piu il workflow di release nel suo repository).
const games = <GameEntry>[
  GameEntry(
    id: 'forna_dagar_card_game',
    title: 'Forna Dagar',
    description: 'Deck Constructor e Tavolo da Gioco, con duello online.',
    repo: 'gtafuto/Forna_Dagar_Card_Game',
  ),
  GameEntry(
    id: 'card_game',
    title: 'Card Game',
    description: 'Card Generator, Deck Constructor e Tavolo da Gioco.',
    repo: 'gtafuto/Card_Game',
  ),
];
