import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/crisis_report.dart';
import '../services/supabase_service.dart';

final crisisReportsProvider = FutureProvider<List<CrisisReport>>((ref) {
  return SupabaseService.instance.fetchCrisisReports();
});

final crisisReportByIdProvider = FutureProvider.family<CrisisReport?, String>((ref, id) {
  return SupabaseService.instance.fetchCrisisReportById(id);
});
