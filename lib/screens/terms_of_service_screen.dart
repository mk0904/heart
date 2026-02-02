import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class TermsOfServiceScreen extends StatelessWidget {
  const TermsOfServiceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundLight,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            _buildHeader(context),
            
            // Content
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppTheme.spacingLG),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(AppTheme.spacingLG),
                      decoration: BoxDecoration(
                        color: AppTheme.white,
                        borderRadius: BorderRadius.circular(AppTheme.radiusBase),
                        border: Border.all(color: AppTheme.borderLight, width: 0.5),
                        boxShadow: AppTheme.shadowSM,
                      ),
                      child: const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Terms of Service',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.text,
                            ),
                          ),
                          SizedBox(height: AppTheme.spacingMD),
                          Text(
                            'Last Updated: January 2026\n\n'
                            'Please read these Terms of Service ("Terms") carefully before using the HEART Nagaland mobile application.\n\n'
                            '1. Acceptance of Terms\n'
                            'By accessing or using our app, you agree to be bound by these Terms. If you disagree with any part of these terms, you may not access the service.\n\n'
                            '2. Use of Service\n'
                            'You agree to use the app only for lawful purposes and in accordance with these Terms. You agree not to:\n'
                            '• Violate any applicable laws or regulations\n'
                            '• Infringe upon the rights of others\n'
                            '• Transmit any harmful or malicious code\n'
                            '• Attempt to gain unauthorized access to the system\n\n'
                            '3. User Accounts\n'
                            'You are responsible for maintaining the confidentiality of your account credentials. You agree to notify us immediately of any unauthorized use.\n\n'
                            '4. Attendance and Biometric Data\n'
                            'By using the face recognition attendance feature, you consent to the collection and processing of your biometric data for attendance purposes.\n\n'
                            '5. Intellectual Property\n'
                            'All content, features, and functionality of the app are owned by HEART Nagaland and are protected by copyright and other intellectual property laws.\n\n'
                            '6. Limitation of Liability\n'
                            'We shall not be liable for any indirect, incidental, special, or consequential damages arising out of or in connection with your use of the app.\n\n'
                            '7. Changes to Terms\n'
                            'We reserve the right to modify these Terms at any time. Your continued use of the app after such modifications constitutes acceptance of the updated Terms.\n\n'
                            '8. Contact Information\n'
                            'For questions about these Terms, please contact us at nititechnologies1@gmail.com',
                            style: TextStyle(
                              fontSize: 14,
                              color: AppTheme.text,
                              height: 1.6,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppTheme.spacingXL),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.spacingLG,
        vertical: AppTheme.spacingBase,
      ),
      decoration: BoxDecoration(
        color: AppTheme.background,
        border: Border(
          bottom: BorderSide(color: AppTheme.borderLight, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: AppTheme.text, size: 22),
            onPressed: () => Navigator.pop(context),
          ),
          const Expanded(
            child: Center(
              child: Text(
                'Terms of Service',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.text,
                ),
              ),
            ),
          ),
          const SizedBox(width: 48),
        ],
      ),
    );
  }
}
