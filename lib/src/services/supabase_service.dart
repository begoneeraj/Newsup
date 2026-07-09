import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/coverage.dart';
import '../models/crisis_report.dart';
import '../models/fact_check.dart';
import '../models/fact_check_v2.dart';
import '../models/public_event.dart';

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

  Future<List<OutletSource>> fetchOutletSources(String factCheckId) async {
    final rows = await _client
        .from('outlet_sources')
        .select()
        .eq('fact_check_id', factCheckId)
        .order('publish_time', ascending: true);
    return rows.map((row) => OutletSource.fromJson(row)).toList();
  }

  Future<CoverageAnalysis?> fetchCoverageAnalysis(String factCheckId) async {
    final row = await _client
        .from('coverage_analysis')
        .select()
        .eq('fact_check_id', factCheckId)
        .maybeSingle();
    if (row == null) return null;
    return CoverageAnalysis.fromJson(row);
  }

  Future<FactCheckV2?> fetchFactCheckV2(String factCheckId) async {
    final row = await _client
        .from('fact_checks_v2')
        .select()
        .eq('fact_check_id', factCheckId)
        .maybeSingle();
    if (row == null) return null;
    return FactCheckV2.fromJson(row);
  }

  /// Broad, always-populated feed (dual-written from fact_checks/
  /// crisis_reports/crises — see src/pipeline/public_events.py), unlike
  /// fetchCrisisReports() which only ever gets rows from the Reddit-sourced
  /// crisis-hunting fetcher and can be structurally empty.
  Future<List<PublicEvent>> fetchPublicEvents() async {
    final rows = await _client.from('public_events').select().order('last_updated', ascending: false);
    return rows.map((row) => PublicEvent.fromJson(row)).toList();
  }

  Future<PublicEvent?> fetchPublicEventById(String id) async {
    final row = await _client.from('public_events').select().eq('id', id).maybeSingle();
    if (row == null) return null;
    return PublicEvent.fromJson(row);
  }
}
