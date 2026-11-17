import 'iserv_offline_store.dart';
import 'iserv_session.dart';
import 'iserv_tasks.dart';

/// Meldet von IServ ab und löscht alle lokal gespeicherten IServ-Daten
/// (Aufgabenliste und offline gespeicherte Anhänge). Offene Ansichten
/// werden über [IservSession.logoutRevision] benachrichtigt.
Future<void> logoutFromIserv() async {
  final session = IservSession();
  await session.restore();
  await session.logout();
  await IservTaskCache().clear();
  await IservOfflineStore.instance.clear();
  IservSession.logoutRevision.value++;
}

/// Ist ein IServ-Login gespeichert?
Future<bool> isIservLoginStored() async {
  final session = IservSession();
  await session.restore();
  return session.hasCookies;
}
