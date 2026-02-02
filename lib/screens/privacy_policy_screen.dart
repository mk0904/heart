import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

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
                            'Privacy Policy',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.text,
                            ),
                          ),
                          SizedBox(height: AppTheme.spacingMD),
                          Text(
                            'Last Updated: January 2026\n\n'
                            'HEART Nagaland ("we", "our", or "us") is committed to protecting your privacy. This Privacy Policy explains how we collect, use, disclose, and safeguard your information when you use our mobile application.\n\n'
                            '1. Information We Collect\n'
                            'We collect information that you provide directly to us, including:\n'
                            '• Personal information (name, email, phone number)\n'
                            '• Profile information (role, college, designation)\n'
                            '• Attendance records and biometric data (face recognition)\n'
                            '• Project submissions and event participation\n\n'
                            '2. How We Use Your Information\n'
                            'We use the information we collect to:\n'
                            '• Provide and maintain our services\n'
                            '• Process attendance and manage records\n'
                            '• Communicate with you about your account\n'
                            '• Improve our services and user experience\n\n'
                            '3. Data Security\n'
                            'We implement appropriate technical and organizational measures to protect your personal information. However, no method of transmission over the internet is 100% secure.\n\n'
                            '4. Your Rights\n'
                            'You have the right to:\n'
                            '• Access your personal data\n'
                            '• Request correction of inaccurate data\n'
                            '• Request deletion of your data\n'
                            '• Withdraw consent at any time\n\n'
                            '5. Contact Us\n'
                            'If you have questions about this Privacy Policy, please contact us at nititechnologies1@gmail.com',
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
                'Privacy Policy',
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
