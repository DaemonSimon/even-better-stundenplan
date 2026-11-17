import 'package:http/http.dart' as http;

/// Maximale Wartezeit pro HTTP-Request (Verbindung bzw. Antwort-Body),
/// damit schlechte Verbindungen schnell als Fehler enden statt endlos zu
/// hängen.
const Duration kHttpTimeout = Duration(seconds: 20);

/// Schickt [request] und liest die Antwort vollständig – beides mit
/// [timeout]. Wirft bei Überschreitung eine `TimeoutException`.
Future<http.Response> sendWithTimeout(
  http.Client client,
  http.BaseRequest request, {
  Duration timeout = kHttpTimeout,
}) async {
  final streamed = await client.send(request).timeout(timeout);
  return http.Response.fromStream(streamed).timeout(timeout);
}
