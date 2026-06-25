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
                            'Last Updated: June 2026\n\n'
                            'HEART Nagaland ("we", "our", or "us"), operated by NITI Technologies, is committed to protecting and respecting your privacy. This Privacy Policy explains how we collect, use, store, and safeguard your information when you use the HEART Nagaland mobile application ("App"). By using the App, you consent to the practices described in this policy.\n\n'
                            '1. Information We Collect\n\n'
                            'a) Information You Provide\n'
                            '• Account Information: Full name, email address, phone number.\n'
                            '• Professional Information: Designation, role, employment type, and college or institution affiliation.\n'
                            '• Profile Photo: An optional profile image you may upload.\n'
                            '• Communications: Messages, support tickets, and feedback you submit through the App.\n\n'
                            'b) Information Collected During Attendance\n'
                            '• Facial Images: Captured during face registration and at each check-in or check-out for identity verification.\n'
                            '• Location Coordinates: Your device\'s GPS coordinates are captured only at the exact moment you mark attendance (check-in or check-out). This is used solely to verify that you are within the authorised geographic boundary (geofence) of your institution. We do not track your location continuously, in the background, or at any time outside the attendance-marking process.\n'
                            '• Timestamp Data: The date and time of each attendance event, synchronised using network time protocols to prevent clock manipulation.\n\n'
                            'c) Automatically Collected Information\n'
                            '• Device Information: Device type, operating system version, and app version for compatibility and troubleshooting.\n'
                            '• Usage Data: General interaction patterns within the App to improve user experience.\n\n'
                            '2. Facial Recognition & Biometric Data\n\n'
                            'How We Use Facial Data:\n'
                            '• Face Registration: When you first set up attendance, you register your face by capturing a reference image. This creates a secure digital representation used exclusively for identity matching.\n'
                            '• Attendance Verification: At each check-in and check-out, your face is captured and compared against your registered reference to confirm your identity.\n'
                            '• On supported devices, initial face detection (such as detecting whether a face is present in the camera frame) is performed entirely on your device. Your live camera feed is never streamed or transmitted to external servers.\n\n'
                            'What We Do NOT Do With Your Face Data:\n'
                            '• We do not use facial data for advertising, marketing, or user profiling.\n'
                            '• We do not sell, rent, or share facial data with any third party for their independent use.\n'
                            '• We do not use facial data for any purpose other than attendance identity verification.\n\n'
                            '3. Location Data — Detailed Explanation\n\n'
                            'We understand that location privacy is important to you. Here is exactly how we handle location data:\n\n'
                            'When Is Location Collected?\n'
                            'Your GPS coordinates are captured only at the precise moment you tap "Check In" or "Check Out" in the App. This is a single, point-in-time reading.\n\n'
                            'Why Is Location Collected?\n'
                            'Your institution defines a geographic boundary (geofence) around its premises. The App checks whether your coordinates fall within this boundary to verify physical presence. This is an integrity measure to prevent remote or off-site attendance marking.\n\n'
                            'What Happens After?\n'
                            'The coordinates captured at the time of attendance are recorded as part of your attendance log. The App does not continue to monitor, poll, or track your location after the attendance event. There is no background location tracking, no location history, and no continuous GPS monitoring.\n\n'
                            'Can I Deny Location Access?\n'
                            'Yes. However, without location access at the time of attendance marking, the App cannot verify your presence within the geofence, and you will be unable to mark attendance. Location permission is required only during the attendance process.\n\n'
                            '4. How We Use Your Information\n'
                            'We use the information we collect to:\n'
                            '• Verify your identity and process attendance records.\n'
                            '• Confirm your presence within your institution\'s geographic boundary.\n'
                            '• Deliver circulars, notifications, and announcements from your institution.\n'
                            '• Facilitate event management and project reporting.\n'
                            '• Provide technical support and respond to your enquiries.\n'
                            '• Maintain the security and integrity of the App.\n'
                            '• Comply with legal obligations and institutional policies.\n\n'
                            '5. Data Security\n'
                            'We take the security of your data seriously and implement multiple layers of protection:\n\n'
                            '• Encryption in Transit: All data transmitted between the App and our servers is encrypted using industry-standard TLS/SSL protocols.\n'
                            '• Encryption at Rest: Stored data, including biometric representations, is encrypted using robust encryption standards.\n'
                            '• Access Controls: Access to personal data is restricted to authorised personnel on a need-to-know basis. Administrative access is protected by role-based access controls and secure authentication.\n'
                            '• Infrastructure Security: Our backend infrastructure is hosted on enterprise-grade, ISO-certified cloud platforms that maintain stringent physical and logical security controls, regular security audits, and compliance certifications.\n'
                            '• Monitoring: We employ continuous monitoring and logging to detect and respond to potential security incidents.\n'
                            '• Incident Response: In the unlikely event of a data breach, we will notify affected users and relevant authorities in accordance with applicable laws and within the timeframes prescribed by law.\n\n'
                            '6. Data Sharing & Third Parties\n'
                            'We do not sell your personal data. We may share limited information only in the following circumstances:\n\n'
                            '• With Your Institution: Attendance records, project submissions, and related administrative data are shared with your affiliated institution as part of the service.\n'
                            '• Service Providers: We use trusted, industry-leading cloud infrastructure providers to host and operate the App. These providers are bound by strict confidentiality and data processing agreements and may only process data on our behalf and in accordance with our instructions.\n'
                            '• Legal Requirements: We may disclose your information if required by law, regulation, legal process, or governmental request.\n'
                            '• Protection of Rights: We may share information to protect the safety, rights, or property of NITI Technologies, our users, or the public.\n\n'
                            '7. Data Retention\n'
                            '• Account and attendance data is retained for as long as your account is active and as required by your institution\'s record-keeping policies.\n'
                            '• Facial registration data is retained for as long as the attendance service requires it. Upon account deletion or at your request, facial data will be permanently removed within 30 days, subject to any legal retention obligations.\n'
                            '• Attendance logs may be retained for a longer period as required by institutional or regulatory requirements.\n\n'
                            '8. Your Rights\n'
                            'Subject to applicable law, you have the right to:\n'
                            '• Access: Request a copy of the personal data we hold about you.\n'
                            '• Correction: Request correction of any inaccurate or incomplete personal data.\n'
                            '• Deletion: Request deletion of your personal data, including biometric data. You may initiate account deletion directly from the App.\n'
                            '• Withdraw Consent: Withdraw your consent for data processing at any time. Note that withdrawing consent may affect your ability to use certain features.\n'
                            '• Data Portability: Request your data in a structured, commonly used format where technically feasible.\n\n'
                            'To exercise any of these rights, please contact us using the details provided below.\n\n'
                            '9. Children\'s Privacy\n'
                            'The App is not intended for use by individuals under the age of 18. We do not knowingly collect personal data from children.\n\n'
                            '10. Changes to This Policy\n'
                            'We may update this Privacy Policy from time to time. Material changes will be communicated through the App. Your continued use of the App after changes are posted constitutes your acceptance of the updated policy.\n\n'
                            '11. Contact Us\n'
                            'If you have any questions, concerns, or requests regarding this Privacy Policy or our data practices, please contact:\n'
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
