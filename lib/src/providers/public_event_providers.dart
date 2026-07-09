import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/public_event.dart';
import '../services/supabase_service.dart';

final publicEventsProvider = FutureProvider<List<PublicEvent>>((ref) {
  return SupabaseService.instance.fetchPublicEvents();
});

final publicEventByIdProvider = FutureProvider.family<PublicEvent?, String>((ref, id) {
  return SupabaseService.instance.fetchPublicEventById(id);
});
