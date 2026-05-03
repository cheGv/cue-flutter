import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../widgets/app_layout.dart';

// TODO(phase-4.0.7.x): Add "Restore archived clients/sessions" surface.
//   Soft-delete shipped in 4.0.7.10 (clients.deleted_at, sessions.deleted_at
//   /deleted_by/delete_reason). Each archived row remains in the database
//   with the timestamp; this screen needs a section that lists them and
//   provides a single-tap restore that nulls deleted_at. Sessions need to
//   surface delete_reason for context in the restore picker.

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _supabase = Supabase.instance.client;
  final _formKey = GlobalKey<FormState>();

  final _nameController     = TextEditingController();
  final _rciController      = TextEditingController();
  final _clinicController   = TextEditingController();
  final _cityController     = TextEditingController();

  bool _loading = true;
  bool _saving  = false;
  String? _successMessage;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _rciController.dispose();
    _clinicController.dispose();
    _cityController.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    try {
      final userId = _supabase.auth.currentUser!.id;
      final res = await _supabase
          .from('clinic_profile')
          .select()
          .eq('id', userId)
          .maybeSingle();

      if (res != null && mounted) {
        _nameController.text   = res['clinician_name'] as String? ?? '';
        _rciController.text    = res['rci_number']     as String? ?? '';
        _clinicController.text = res['clinic_name']    as String? ?? '';
        _cityController.text   = res['city']           as String? ?? '';
      }
    } catch (e) {
      if (mounted) setState(() => _errorMessage = 'Failed to load profile: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _saving = true; _successMessage = null; _errorMessage = null; });

    try {
      final userId = _supabase.auth.currentUser!.id;
      await _supabase.from('clinic_profile').upsert({
        'id':              userId,
        'clinician_name':  _nameController.text.trim(),
        'rci_number':      _rciController.text.trim(),
        'clinic_name':     _clinicController.text.trim(),
        'city':            _cityController.text.trim(),
      });
      if (mounted) setState(() => _successMessage = 'Profile saved.');
    } catch (e) {
      if (mounted) setState(() => _errorMessage = 'Save failed: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppLayout(
      title: 'Settings',
      activeRoute: 'settings',
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 32),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Clinician Profile',
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF0E1C36),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'This information is used in generated reports and goal plans.',
                        style: const TextStyle(
                          fontSize: 13,
                          color: Color(0xFF6B7690),
                        ),
                      ),
                      const SizedBox(height: 32),

                      _buildField(
                        label: 'Clinician Name',
                        controller: _nameController,
                        hint: 'e.g. Dr. Priya Sharma',
                      ),
                      const SizedBox(height: 20),
                      _buildField(
                        label: 'RCI Number',
                        controller: _rciController,
                        hint: 'e.g. RCI-12345',
                      ),
                      const SizedBox(height: 20),
                      _buildField(
                        label: 'Clinic Name',
                        controller: _clinicController,
                        hint: 'e.g. Communicate Therapy Centre',
                      ),
                      const SizedBox(height: 20),
                      _buildField(
                        label: 'City',
                        controller: _cityController,
                        hint: 'e.g. Bengaluru',
                      ),
                      const SizedBox(height: 32),

                      if (_successMessage != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                              color: const Color(0xFFE8F5E9),
                              border: Border.all(color: const Color(0xFF81C784)),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              _successMessage!,
                              style: const TextStyle(fontSize: 13, color: Color(0xFF2E7D32)),
                            ),
                          ),
                        ),

                      if (_errorMessage != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFF0F0),
                              border: Border.all(color: const Color(0xFFEF9A9A)),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              _errorMessage!,
                              style: const TextStyle(fontSize: 13, color: Color(0xFFC0392B)),
                            ),
                          ),
                        ),

                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF2A8F84),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 15),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8)),
                            elevation: 0,
                          ),
                          onPressed: _saving ? null : _save,
                          child: _saving
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white)),
                                )
                              : const Text('Save', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  Widget _buildField({
    required String label,
    required TextEditingController controller,
    String? hint,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Color(0xFF0E1C36),
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          style: const TextStyle(fontSize: 14, color: Color(0xFF0E1C36)),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(fontSize: 14, color: Color(0xFF6B7690)),
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFFE6DDCA)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFFE6DDCA)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFF2A8F84), width: 1.5),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          ),
        ),
      ],
    );
  }
}
