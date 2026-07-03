import 'package:flutter/material.dart';

enum CrisisStatus { unresolved, partiallyResolved, resolved }

extension CrisisStatusLabel on CrisisStatus {
  String get label {
    switch (this) {
      case CrisisStatus.unresolved:
        return 'Unresolved';
      case CrisisStatus.partiallyResolved:
        return 'Partially Resolved';
      case CrisisStatus.resolved:
        return 'Resolved';
    }
  }
}

class TimelineEvent {
  final DateTime date;
  final String title;
  final String description;
  final Color statusColor;

  const TimelineEvent({
    required this.date,
    required this.title,
    required this.description,
    required this.statusColor,
  });

  factory TimelineEvent.fromJson(Map<String, dynamic> json) {
    return TimelineEvent(
      date: DateTime.parse(json['date'] as String),
      title: json['title'] as String,
      description: json['description'] as String,
      statusColor: colorFromHex(json['status_color'] as String? ?? '#EF4444'),
    );
  }
}

/// Parses a "#RRGGBB" hex string written by the ingestion pipeline into a
/// Flutter [Color]. See src/models/schemas.py::TimelineEvent.status_color.
Color colorFromHex(String hex) {
  final normalized = hex.replaceFirst('#', '');
  return Color(int.parse('FF$normalized', radix: 16));
}

enum EvidenceType { pdf, live, document }

EvidenceType evidenceTypeFromJson(String value) {
  switch (value) {
    case 'PDF':
      return EvidenceType.pdf;
    case 'LIVE':
      return EvidenceType.live;
    case 'DOCUMENT':
    default:
      return EvidenceType.document;
  }
}

class EvidenceItem {
  final String title;
  final String url;
  final EvidenceType type;

  const EvidenceItem({
    required this.title,
    required this.url,
    required this.type,
  });

  factory EvidenceItem.fromJson(Map<String, dynamic> json) {
    return EvidenceItem(
      title: json['title'] as String,
      url: json['url'] as String,
      type: evidenceTypeFromJson(json['type'] as String),
    );
  }
}

class CrisisReport {
  final String id;
  final String title;
  final CrisisStatus status;
  final DateTime eventStartDate;
  final int remedialActionsCount;
  final int rtiFilingsTotal;
  final int rtiFilingsAnswered;
  final List<TimelineEvent> timelineEvents;
  final List<EvidenceItem> evidenceItems;

  const CrisisReport({
    required this.id,
    required this.title,
    required this.status,
    required this.eventStartDate,
    required this.remedialActionsCount,
    required this.rtiFilingsTotal,
    required this.rtiFilingsAnswered,
    required this.timelineEvents,
    required this.evidenceItems,
  });

  int get daysSinceEvent => DateTime.now().difference(eventStartDate).inDays;

  factory CrisisReport.fromJson(Map<String, dynamic> json) {
    return CrisisReport(
      id: json['id'] as String,
      title: json['title'] as String,
      status: crisisStatusFromJson(json['status'] as String),
      eventStartDate: DateTime.parse(json['event_start_date'] as String),
      remedialActionsCount: json['remedial_actions_count'] as int,
      rtiFilingsTotal: json['rti_filings_total'] as int,
      rtiFilingsAnswered: json['rti_filings_answered'] as int,
      timelineEvents: (json['timeline_events'] as List<dynamic>? ?? [])
          .map((e) => TimelineEvent.fromJson(e as Map<String, dynamic>))
          .toList(),
      evidenceItems: (json['evidence_items'] as List<dynamic>? ?? [])
          .map((e) => EvidenceItem.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

/// Parses the UPPER_SNAKE_CASE status strings written by the ingestion
/// pipeline (see src/models/schemas.py::CrisisStatus).
CrisisStatus crisisStatusFromJson(String value) {
  switch (value) {
    case 'UNRESOLVED':
      return CrisisStatus.unresolved;
    case 'PARTIALLY_RESOLVED':
      return CrisisStatus.partiallyResolved;
    case 'RESOLVED':
      return CrisisStatus.resolved;
    default:
      return CrisisStatus.unresolved;
  }
}
