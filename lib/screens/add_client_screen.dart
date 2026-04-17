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
  final _supabase = Supabase.instance.client;
  final _nameController = TextEditingController();
  final _ageController = TextEditingController();
  final _diagnosisController = TextEditingController();
  final _modalityController = TextEditingController();
  final _notesController = TextEditingController();

  bool _usesAac = false;
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
    final name = _nameController.text.trim();
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
    final fieldStyle =
        GoogleFonts.inter(fontSize: 16, color: CueColors.inkPrimary);

    return Scaffold(
      backgroundColor: CueColors.background,
      appBar: AppBar(
        title: const Text('New Client'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 32, 24, 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CueTheme.sectionTitle('Profile'),
            const SizedBox(height: 20),
            TextField(
              controller: _nameController,
              textCapitalization: TextCapitalization.words,
              style: fieldStyle,
              decoration: const InputDecoration(labelText: 'Full name'),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _ageController,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: fieldStyle,
              decoration: const InputDecoration(labelText: 'Age'),
            ),
            const SizedBox(height: 40),

            CueTheme.sectionTitle('Clinical detail'),
            const SizedBox(height: 20),
            TextField(
              controller: _diagnosisController,
              textCapitalization: TextCapitalization.sentences,
              style: fieldStyle,
              decoration: const InputDecoration(labelText: 'Diagnosis'),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _modalityController,
              style: fieldStyle,
              decoration: const InputDecoration(
                labelText: 'Primary communication modality',
                hintText: 'Verbal, AAC device, PECS, Sign…',
              ),
            ),
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Uses AAC device',
                      style: GoogleFonts.inter(
                        fontSize: 15,
                        color: CueColors.inkPrimary,
                      ),
                    ),
                  ),
                  Switch(
                    value: _usesAac,
                    onChanged: (v) => setState(() => _usesAac = v),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 40),

            CueTheme.sectionTitle('Notes'),
            const SizedBox(height: 20),
            TextField(
              controller: _notesController,
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
              style: fieldStyle,
              decoration: const InputDecoration(
                labelText: 'Additional notes',
              ),
            ),
            const SizedBox(height: 48),

            SizedBox(
              height: 52,
              child: FilledButton(
                onPressed: _isSaving ? null : _save,
                child: _isSaving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2),
                      )
                    : const Text('Save Client'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
