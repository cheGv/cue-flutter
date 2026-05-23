// Phase B — STG numbering ("{ltg_seq}.{stg_letter}", e.g. "1.A", "2.B").
//
// LTG sequence = position of the parent LTG among the client's LTGs ordered by
// created_at ascending (first LTG = 1). STG letter = position of the STG within
// its parent LTG's STGs ordered by created_at ascending (first = A). Beyond 26
// STGs in one LTG, the letter falls back to a number. An orphan STG (parent LTG
// not in the list) renders without the numeric prefix.
import '../models/short_term_goal.dart';

String stgNumber(
  ShortTermGoal stg,
  List<ShortTermGoal> allStgs,
  List<Map<String, dynamic>> ltgs,
) {
  final sortedLtgs = [...ltgs]
    ..sort((a, b) => _ts(a['created_at']).compareTo(_ts(b['created_at'])));
  final ltgIndex = sortedLtgs
      .indexWhere((l) => l['id']?.toString() == stg.longTermGoalId);

  final siblings = allStgs
      .where((s) => s.longTermGoalId == stg.longTermGoalId)
      .toList()
    ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  final letter = _letter(siblings.indexWhere((s) => s.id == stg.id));

  // Orphan — parent LTG not found: skip the numeric prefix.
  if (ltgIndex < 0) return letter;
  return '${ltgIndex + 1}.$letter';
}

String _letter(int index) {
  if (index < 0) return '?';
  if (index < 26) return String.fromCharCode(65 + index); // A..Z
  return '${index + 1}'; // beyond Z → numeric fallback
}

DateTime _ts(dynamic v) =>
    DateTime.tryParse(v?.toString() ?? '') ??
    DateTime.fromMillisecondsSinceEpoch(0);
