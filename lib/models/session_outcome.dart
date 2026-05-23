// Session outcome — clinician-affirming categorical state for a session.
// Mirrors the Postgres `session_outcome` enum (migration add_session_outcome).
//
// Language discipline: never "setback", "regression", or "failure".
//   progress     — clinical work moved forward
//   plan_revised — clinician revised the plan based on what the session revealed
//   holding      — session consolidated current state; no progress, no revision
enum SessionOutcome {
  progress,
  planRevised,
  holding;

  /// Parse the DB string. Unknown / null returns null (column is nullable).
  static SessionOutcome? fromString(String? s) => switch (s) {
        'progress' => SessionOutcome.progress,
        'plan_revised' => SessionOutcome.planRevised,
        'holding' => SessionOutcome.holding,
        _ => null,
      };

  String toDbValue() => switch (this) {
        SessionOutcome.progress => 'progress',
        SessionOutcome.planRevised => 'plan_revised',
        SessionOutcome.holding => 'holding',
      };

  String displayLabel() => switch (this) {
        SessionOutcome.progress => 'progress',
        SessionOutcome.planRevised => 'plan revised',
        SessionOutcome.holding => 'holding',
      };
}
