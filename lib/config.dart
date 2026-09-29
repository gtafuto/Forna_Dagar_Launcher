/// Client ID pubblico dell'OAuth App registrata su GitHub (Settings, Developer
/// settings, OAuth Apps, con "Enable Device Flow" attivo). Non e un segreto:
/// identifica solo l'app, l'utente autorizza comunque con il proprio account.
///
/// Si puo passare alla build senza modificare il codice:
/// `flutter build windows --dart-define=GITHUB_CLIENT_ID=...`
const githubClientId = String.fromEnvironment(
  'GITHUB_CLIENT_ID',
  defaultValue: 'INSERISCI_QUI_IL_CLIENT_ID',
);

/// Falso finche non e stato inserito il Client ID reale: il launcher lo dice
/// chiaramente invece di far fallire l'accesso con un errore di GitHub.
bool get githubClientIdConfigured => githubClientId.isNotEmpty && !githubClientId.startsWith('INSERISCI');

/// Permesso richiesto a GitHub. `repo` e l'unico che consente di leggere le
/// Release dei repository privati; chi ha il ruolo Read sul repository non puo
/// comunque modificarlo (il token non supera mai i permessi dell'utente).
const githubScope = 'repo';

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
