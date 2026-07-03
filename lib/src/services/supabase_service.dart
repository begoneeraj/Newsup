import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/crisis_report.dart';
import '../models/fact_check.dart';

/// Thin wrapper around the Supabase client for the two tables written by
/// the ingestion pipeline (src/database/supabase_client.py).
class SupabaseService {
  SupabaseService._();

  static final SupabaseService instance = SupabaseService._();

  SupabaseClient get _client => Supabase.instance.client;

  Future<List<FactCheck>> fetchFactChecks() async {
    final rows = await _client.from('fact_checks').select().order('created_at', ascending: false);
    return rows.map((row) => FactCheck.fromJson(row)).toList();
  }

  Future<FactCheck?> fetchFactCheckById(String id) async {
    final row = await _client.from('fact_checks').select().eq('id', id).maybeSingle();
    if (row == null) return null;
    return FactCheck.fromJson(row);
  }

  Future<List<CrisisReport>> fetchCrisisReports() async {
    final rows = await _client
        .from('crisis_reports')
        .select()
        .order('event_start_date', ascending: false);
    return rows.map((row) => CrisisReport.fromJson(row)).toList();
  }

  Future<CrisisReport?> fetchCrisisReportById(String id) async {
    final row = await _client.from('crisis_reports').select().eq('id', id).maybeSingle();
    if (row == null) return null;
    return CrisisReport.fromJson(row);
  }
}
