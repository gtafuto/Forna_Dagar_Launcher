import 'dart:convert';
import 'dart:io';

/// Dove il launcher conserva il token di accesso a GitHub.
abstract class TokenStore {
  Future<String?> read();
  Future<void> write(String token);
  Future<void> clear();
}

/// Solo in memoria (test).
class MemoryTokenStore implements TokenStore {
  String? _token;

  MemoryTokenStore([this._token]);

  @override
  Future<String?> read() async => _token;

  @override
  Future<void> write(String token) async => _token = token;

  @override
  Future<void> clear() async => _token = null;
}

/// Token cifrato con la protezione dei dati di Windows (DPAPI, tramite
/// PowerShell): il file salvato e leggibile **solo dallo stesso utente Windows
/// sullo stesso PC**. Copiarlo altrove non serve a nulla.
///
/// Il token passa a PowerShell dallo standard input, mai dalla riga di
/// comando (dove sarebbe visibile ad altri programmi).
class DpapiTokenStore implements TokenStore {
  final File file;

  DpapiTokenStore(this.file);

  static Future<ProcessResult> _powershell(String script, {String? stdin}) async {
    final process = await Process.start('powershell', ['-NoProfile', '-NonInteractive', '-Command', script]);
    if (stdin != null) process.stdin.write(stdin);
    await process.stdin.close();
    final out = process.stdout.transform(utf8.decoder).join();
    final err = process.stderr.transform(utf8.decoder).join();
    final code = await process.exitCode;
    return ProcessResult(process.pid, code, await out, await err);
  }

  @override
  Future<String?> read() async {
    try {
      if (!await file.exists()) return null;
      final blob = (await file.readAsString()).trim();
      if (blob.isEmpty) return null;
      final path = file.path.replaceAll("'", "''");
      final result = await _powershell(
        "\$s = ConvertTo-SecureString ((Get-Content -Raw -LiteralPath '$path').Trim()); "
        "[System.Net.NetworkCredential]::new('', \$s).Password",
      );
      if (result.exitCode != 0) return null;
      final token = (result.stdout as String).trim();
      return token.isEmpty ? null : token;
    } catch (_) {
      // File illeggibile o non decifrabile (es. copiato da un altro PC): come
      // se non ci fosse nessun accesso, l'utente rifara il login.
      return null;
    }
  }

  @override
  Future<void> write(String token) async {
    final result = await _powershell(
      r"$t = [Console]::In.ReadToEnd().Trim(); ConvertTo-SecureString $t -AsPlainText -Force | ConvertFrom-SecureString",
      stdin: token,
    );
    final blob = (result.stdout as String).trim();
    if (result.exitCode != 0 || blob.isEmpty) {
      throw Exception('Impossibile salvare l\'accesso in modo sicuro: ${result.stderr}');
    }
    await file.parent.create(recursive: true);
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(blob);
    await tmp.rename(file.path);
  }

  @override
  Future<void> clear() async {
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {
      // Best effort.
    }
  }
}
