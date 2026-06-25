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
                            'Last Updated: June 2026\n\n'
                            'Please read these Terms of Service ("Terms") carefully before using the HEART Nagaland mobile application ("App"). By creating an account, accessing, or using the App, you acknowledge that you have read, understood, and agree to be bound by these Terms and our Privacy Policy.\n\n'
                            '1. Description of Service\n'
                            'HEART Nagaland is a workforce management platform designed for Higher Education institutions in Nagaland. The App provides attendance tracking with identity verification, institutional circulars and notifications, event management and coordination, project management and reporting, and administrative communication tools. '
                            'The App uses industry-standard methods including network time synchronisation, location-based geofence verification, and facial recognition to ensure the accuracy and integrity of attendance records.\n\n'
                            '2. Account Registration & Eligibility\n'
                            'To use the App, you must be a registered employee or staff member of a participating institution. You are responsible for maintaining the confidentiality of your login credentials and for all activities that occur under your account. '
                            'You agree to provide accurate and complete information during registration and to keep your profile information up to date. You must notify us immediately of any unauthorised use of your account.\n\n'
                            '3. Acceptable Use & Anti-Spoofing Policy\n'
                            'You agree to use the App only for its intended purpose and in compliance with all applicable laws. You strictly agree NOT to:\n'
                            '• Impersonate another individual or use another person\'s face, photograph, or identity to mark attendance.\n'
                            '• Use GPS spoofing tools, mock location apps, developer options, or any other means to falsify or manipulate your geographic position.\n'
                            '• Tamper with, manipulate, or alter your device\'s system clock or time zone settings to circumvent attendance time restrictions.\n'
                            '• Attempt to reverse engineer, decompile, disassemble, or extract the source code, algorithms, or APIs of the App.\n'
                            '• Interfere with or disrupt the integrity or performance of the App or its related systems.\n'
                            '• Share, transfer, or allow others to use your account credentials.\n\n'
                            'Violations of this policy may result in immediate suspension or permanent termination of your account. Violations may also be reported to your institution\'s administrative authority and may lead to disciplinary action as per your institution\'s policies.\n\n'
                            '4. Attendance Verification\n'
                            'The App uses a multi-factor verification process for attendance, which may include facial recognition for identity confirmation, geofence-based location verification to confirm presence within the designated institutional boundary, and network time synchronisation to ensure accurate timestamps.\n\n'
                            'By using the attendance feature, you acknowledge and consent to:\n'
                            '• The capture and processing of your facial image for identity verification purposes only.\n'
                            '• The collection of your device\'s geographic coordinates at the time of check-in and check-out to verify your presence within the authorised area.\n'
                            '• Automatic check-out if you do not manually check out by the end of the working day.\n\n'
                            'Location data is collected only at the specific moment of marking attendance and is not tracked continuously or in the background.\n\n'
                            '5. Biometric Data Consent\n'
                            'By using the facial recognition feature, you explicitly and voluntarily consent to the collection, processing, and secure storage of your biometric data (facial images and derived representations) solely for the purpose of attendance identity verification. '
                            'This data is processed in accordance with our Privacy Policy and applicable data protection laws. You may withdraw your consent at any time by contacting us, though this may limit your ability to use certain features of the App.\n\n'
                            '6. Intellectual Property\n'
                            'All content, design, graphics, logos, software, and other materials in the App are the property of NITI Technologies or its licensors and are protected by applicable intellectual property laws. You are granted a limited, non-exclusive, non-transferable licence to use the App for its intended purpose.\n\n'
                            '7. Disclaimers of Warranties\n'
                            'THE APP AND SERVICES ARE PROVIDED ON AN "AS-IS" AND "AS-AVAILABLE" BASIS WITHOUT WARRANTIES OF ANY KIND, EITHER EXPRESS OR IMPLIED. We do not warrant that the App will be uninterrupted, error-free, completely accurate, or entirely secure. '
                            'We are not responsible for your inability to mark attendance due to device malfunction, insufficient device permissions, poor network connectivity, GPS signal issues, or scheduled maintenance.\n\n'
                            '8. Limitation of Liability\n'
                            'TO THE MAXIMUM EXTENT PERMITTED BY APPLICABLE LAW, NITI TECHNOLOGIES AND ITS DIRECTORS, EMPLOYEES, PARTNERS, AND AFFILIATES SHALL NOT BE LIABLE FOR ANY INDIRECT, INCIDENTAL, SPECIAL, CONSEQUENTIAL, OR PUNITIVE DAMAGES, INCLUDING BUT NOT LIMITED TO LOSS OF DATA, LOSS OF PROFITS, LOSS OF EMPLOYMENT BENEFITS, OR ANY OTHER INTANGIBLE LOSSES ARISING FROM:\n'
                            '(a) Your access to, use of, or inability to access or use the App;\n'
                            '(b) Any conduct or content of any third party;\n'
                            '(c) Unauthorised access, use, or alteration of your data;\n'
                            '(d) Any errors, inaccuracies, or omissions in the attendance records.\n\n'
                            '9. Indemnification\n'
                            'You agree to indemnify and hold harmless NITI Technologies, its affiliates, officers, and employees from and against any claims, liabilities, damages, losses, and expenses arising out of your use of the App or violation of these Terms.\n\n'
                            '10. Termination\n'
                            'We reserve the right to suspend or terminate your access to the App at our sole discretion, at any time, for any reason, including but not limited to a breach of these Terms, without prior notice or liability. Upon termination, your right to use the App will cease immediately.\n\n'
                            '11. Governing Law & Dispute Resolution\n'
                            'These Terms shall be governed by and construed in accordance with the laws of India. Any disputes arising under these Terms shall be subject to the exclusive jurisdiction of the courts in Nagaland, India.\n\n'
                            '12. Changes to Terms\n'
                            'We reserve the right to modify these Terms at any time. Material changes will be communicated through the App. Your continued use of the App after such modifications constitutes your acceptance of the updated Terms.\n\n'
                            '13. Severability\n'
                            'If any provision of these Terms is found to be unenforceable or invalid, that provision will be limited or eliminated to the minimum extent necessary, and the remaining provisions will remain in full force and effect.\n\n'
                            '14. Contact Information\n'
                            'For any questions, concerns, or legal notices regarding these Terms, please contact:\n'
                            'NITI Technologies\n'
                            'Email: nititechnologies1@gmail.com',
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
