import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'models.dart';

class LocalStore {
  static const _planKey = 'active_plan';
  static const _installationKey = 'installation_id';

  Future<String> installationId() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(_installationKey);
    if (existing != null) return existing;
    final created = const Uuid().v4();
    await prefs.setString(_installationKey, created);
    return created;
  }

  Future<LocalPlan?> loadPlan() async {
    final prefs = await SharedPreferences.getInstance();
    final source = prefs.getString(_planKey);
    return source == null ? null : decodePlan(source);
  }

  Future<void> savePlan(LocalPlan plan) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_planKey, encodePlan(plan));
  }

  Future<void> clearPlan() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_planKey);
  }
}
