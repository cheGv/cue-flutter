// lib/screens/timeline_route.dart
//
// Phase 5.3 B.3 stub — host route for the full vertical timeline,
// reachable from TimelineStrip's "See all N events →" link.
//
// Per Phase 4A Decision 3: entries arrive via Navigator constructor
// args (Option 1). No re-query. onRefresh is a no-op — staleness
// limitation: if user archives a session inside this route, the row
// stays visible until they pop and re-enter via the link from Profile.
// Acceptable for a stub; Phase 5.4 redesign of timeline-as-pattern-
// surface will rewire data flow.
//
// Body wraps FullTimelineView in Center > ConstrainedBox(maxWidth: 760)
// > SingleChildScrollView per Phase 4C Point 1 — comfortable reading
// width on a dedicated screen, wider than Profile's 680 _capped because
// timeline route is the sole content of its screen.

import 'package:flutter/material.dart';

import '../models/timeline_entry.dart';
import '../widgets/profile/full_timeline_view.dart';

class TimelineRoute extends StatelessWidget {
  final String clientId;
  final String clientName;
  final List<TimelineEntry> entries;

  const TimelineRoute({
    super.key,
    required this.clientId,
    required this.clientName,
    required this.entries,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Timeline · $clientName'),
        // Back button auto-rendered by AppBar when route is pushed.
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: SingleChildScrollView(
            child: FullTimelineView(
              entries:    entries,
              clientId:   clientId,
              clientName: clientName,
              // B.3 stub — see header comment for staleness rationale.
              onRefresh:  () {},
            ),
          ),
        ),
      ),
    );
  }
}
