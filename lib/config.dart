/// Base pubblica del bucket `app-releases` (progetto Supabase condiviso con i
/// due giochi). Ogni gioco pubblica in `<base>/<id>/latest.json` il manifest
/// dell'ultima versione (vedi `.github/workflows/release-windows.yml` nei
/// repository dei giochi).
const releasesBaseUrl = 'https://dibmgtxqxychdsazgodw.supabase.co/storage/v1/object/public/app-releases';

/// Un gioco che il launcher sa installare e avviare. [id] deve coincidere con
/// `APP_ID` del workflow di release del gioco (e quindi con la cartella nel
/// bucket).
class GameEntry {
  final String id;
  final String title;
  final String description;

  const GameEntry({required this.id, required this.title, required this.description});
}

/// Elenco dei giochi mostrati nella schermata iniziale. Aggiungerne uno e
/// una riga qui (piu il workflow di release nel suo repository).
const games = <GameEntry>[
  GameEntry(
    id: 'forna_dagar_card_game',
    title: 'Forna Dagar',
    description: 'Deck Constructor e Tavolo da Gioco, con duello online.',
  ),
  GameEntry(
    id: 'card_game',
    title: 'Card Game',
    description: 'Card Generator, Deck Constructor e Tavolo da Gioco.',
  ),
];
