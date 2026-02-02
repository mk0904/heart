import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'edit_profile_screen.dart';

class CompleteProfileScreen extends StatelessWidget {
  const CompleteProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Use EditProfileScreen directly with isCompleteProfile flag
    return const EditProfileScreen(
      isCompleteProfile: true,
    );
  }
}
