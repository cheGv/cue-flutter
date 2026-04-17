import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/cue_theme.dart';

class AddClientScreen extends StatefulWidget {
  const AddClientScreen({super.key});

  @override
  State<AddClientScreen> createState() => _AddClientScreenState();
}

class _AddClientScreenState extends State<AddClientScreen> {
  final _supabase            = Supabase.instance.client;
  final _nameController      = TextEditingController();
  final _ageController       = TextEditingController();
  final _diagnosisController = TextEditingController();
  final _modalityController  = TextEditingController();
  final _notesController     = TextEditingController();

  bool _usesAac  = false;
  bool _isSaving = false;

  @override
  void dispose() {
    _nameController.dispose();
    _ageController.dispose();
    _diagnosisController.dispose();
    _modalityController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name    = _nameController.text.trim();
    final ageText = _ageController.text.trim();

    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Full name is required')),
      );
      return;
    }
    if (ageText.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Age is required')),
      );
      return;
    }

    final userId = _supabase.auth.currentUser?.id;
    setState(() => _isSaving = true);
    try {
      await _supabase.from('clients').insert({
        'name': name,
        'age': int.tryParse(ageText) ?? 0,
        'diagnosis': _diagnosisController.text.trim(),
        'uses_aac': _usesAac,
        'communication_modality': _modalityController.text.trim(),
        'additional_notes': _notesController.text.trim(),
        'total_sessions': 0,
        if (userId != null) 'clinician_id': userId,
      });
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error adding client: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CueColors.softWhite,
      appBar: AppBar(
        title: Text('Add Client',
            style: GoogleFonts.dmSans(
                color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600)),
        backgroundColor: CueColors.inkNavy,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CueTheme.sectionLabel('Required'),
            const SizedBox(height: 12),
            TextField(
              controller: _nameController,
              decoration: CueTheme.inputDecoration('Full Name *'),
              textCapitalization: TextCapitalization.words,
              style: GoogleFonts.dmSans(fontSize: 15, color: CueColors.inkNavy),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _ageController,
              decoration: CueTheme.inputDecoration('Age *'),
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: GoogleFonts.dmSans(fontSize: 15, color: CueColors.inkNavy),
            ),
            const SizedBox(height: 28),

            CueTheme.sectionLabel('Clinical Details'),
            const SizedBox(height: 12),
            TextField(
              controller: _diagnosisController,
              decoration: CueTheme.inputDecoration('Diagnosis'),
              textCapitalization: TextCapitalization.sentences,
              style: GoogleFonts.dmSans(fontSize: 15, color: CueColors.inkNavy),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _modalityController,
              decoration: CueTheme.inputDecoration(
                'Primary Communication Modality',
                hint: 'e.g. Verbal, AAC device, PECS, Sign',
              ),
              style: GoogleFonts.dmSans(fontSize: 15, color: CueColors.inkNavy),
            ),
            const SizedBox(height: 12),

            // AAC toggle
            Container(
              decoration: BoxDecoration(
                color: CueColors.surfaceWhite,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: CueColors.inkNavy.withOpacity(0.2)),
              ),
              child: SwitchListTile(
                title: Text('Uses AAC Device',
                    style: GoogleFonts.dmSans(
                        fontSize: 15, color: CueColors.inkNavy)),
                subtitle: Text(
                  _usesAac ? 'Yes' : 'No',
                  style: GoogleFonts.dmSans(
                    fontSize: 13,
                    color: _usesAac ? CueColors.signalTeal : CueColors.textMid,
                  ),
                ),
                value: _usesAac,
                onChanged: (v) => setState(() => _usesAac = v),
                activeColor: CueColors.signalTeal,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 28),

            CueTheme.sectionLabel('Additional Notes'),
            const SizedBox(height: 12),
            TextField(
              controller: _notesController,
              decoration: CueTheme.inputDecoration('Notes'),
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
              style: GoogleFonts.dmSans(fontSize: 15, color: CueColors.inkNavy),
            ),
            const SizedBox(height: 36),

            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton(
                onPressed: _isSaving ? null : _save,
                style: FilledButton.styleFrom(
                  backgroundColor: CueColors.inkNavy,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                child: _isSaving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2),
                      )
                    : Text(
                        'Save Client',
                        style: GoogleFonts.dmSans(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: Colors.white),
                      ),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
