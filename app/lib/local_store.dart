import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'models.dart';

class LocalStore {
  static const _planKey = 'active_plan';
  static const _plansKey = 'study_plans_v2';
  static const _installationKey = 'installation_id';

  Future<String> installationId() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(_installationKey);
    if (existing != null) return existing;
    final created = const Uuid().v4();
    await prefs.setString(_installationKey, created);
    return created;
  }

  Future<List<LocalPlan>> loadPlans() async {
    final prefs = await SharedPreferences.getInstance();
    final plansSource = prefs.getString(_plansKey);
    if (plansSource != null) return decodePlans(plansSource);

    // One-time migration from the original single-book storage.
    final source = prefs.getString(_planKey);
    if (source == null) return [];
    final legacyPlan = decodePlan(source);
    await prefs.setString(_plansKey, encodePlans([legacyPlan]));
    await prefs.remove(_planKey);
    return [legacyPlan];
  }

  Future<void> savePlans(List<LocalPlan> plans) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_plansKey, encodePlans(plans));
  }
}
