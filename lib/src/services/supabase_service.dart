import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/coverage.dart';
import '../models/crisis_report.dart';
import '../models/data_story.dart';
import '../models/fact_check.dart';
import '../models/fact_check_v2.dart';
import '../models/govt_promise.dart';
import '../models/pinned_statistic.dart';
import '../models/public_event.dart';
import '../models/science_research.dart';
import '../models/slow_crisis.dart';

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

  Future<List<GovtPromise>> fetchGovtPromises() async {
    final rows = await _client.from('govt_promises').select().order('last_updated', ascending: false);
    return rows.map((row) => GovtPromise.fromJson(row)).toList();
  }

  Future<GovtPromise?> fetchGovtPromiseById(String id) async {
    final row = await _client.from('govt_promises').select().eq('id', id).maybeSingle();
    if (row == null) return null;
    return GovtPromise.fromJson(row);
  }

  Future<List<PromiseEvidence>> fetchPromiseEvidence(String promiseId) async {
    final rows = await _client
        .from('promise_evidence')
        .select()
        .eq('promise_id', promiseId)
        .order('observed_at', ascending: false);
    return rows.map((row) => PromiseEvidence.fromJson(row)).toList();
  }

  Future<List<ScienceResearchReport>> fetchScienceResearchReports() async {
    final rows = await _client.from('science_research_reports').select().order('processed_at', ascending: false);
    return rows.map((row) => ScienceResearchReport.fromJson(row)).toList();
  }

  Future<List<DataStory>> fetchDataStories() async {
    final rows = await _client.from('data_stories').select().order('published_at', ascending: false);
    return rows.map((row) => DataStory.fromJson(row)).toList();
  }

  Future<List<SlowCrisis>> fetchSlowCrises() async {
    final rows = await _client.from('slow_crises').select().order('title');
    return rows.map((row) => SlowCrisis.fromJson(row)).toList();
  }

  Future<SlowCrisis?> fetchSlowCrisisById(String id) async {
    final row = await _client.from('slow_crises').select().eq('id', id).maybeSingle();
    if (row == null) return null;
    return SlowCrisis.fromJson(row);
  }

  Future<List<CrisisDataPoint>> fetchCrisisDataPoints(String crisisId) async {
    final rows = await _client
        .from('crisis_data_points')
        .select()
        .eq('crisis_id', crisisId)
        .order('recorded_date', ascending: true);
    return rows.map((row) => CrisisDataPoint.fromJson(row)).toList();
  }

  Future<List<CrisisNarrativeUpdate>> fetchCrisisNarrativeUpdates(String crisisId) async {
    final rows = await _client
        .from('crisis_narrative_updates')
        .select()
        .eq('crisis_id', crisisId)
        .order('generated_at', ascending: false);
    return rows.map((row) => CrisisNarrativeUpdate.fromJson(row)).toList();
  }

  /// Manually curated national stats banner atop Crisis Tracker — see
  /// supabase/migrations/0011_crisis_expansion.sql.
  Future<List<PinnedStatistic>> fetchPinnedStatistics() async {
    final rows = await _client
        .from('pinned_statistics')
        .select()
        .eq('active', true)
        .order('display_order');
    return rows.map((row) => PinnedStatistic.fromJson(row)).toList();
  }
}
