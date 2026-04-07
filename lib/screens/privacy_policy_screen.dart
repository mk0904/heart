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
                            '• Attendance records, including biometric and face-related data described in Section 2\n'
                            '• Project submissions and event participation\n\n'
                            '2. Face Data and Biometric Attendance\n'
                            'This section describes collection, use, disclosure, storage, and retention of face-related information used for attendance.\n\n'
                            'What we collect:\n'
                            '• Camera input when you register your face or verify attendance.\n'
                            '• Cropped face images (still images), including a registration reference image and verification images when you mark attendance.\n'
                            '• On Android devices using the native attendance flow: on-device face detection results (such as face position and eye openness used only for liveness during attendance) and a numeric face embedding (a mathematical vector derived from your face image) used to match your identity. Face detection uses Google ML Kit on the device; embeddings are produced on the device by an on-device model.\n'
                            '• On iOS, face registration and check-in/check-out use an embedded web experience that accesses the camera; processing is performed as part of our service and stored through our backend as described below.\n\n'
                            'How we use face data:\n'
                            '• To register your face for attendance, verify your identity at check-in and check-out, and support accurate attendance records.\n'
                            '• On Android, liveness checks may use on-device signals (such as eye openness) only during that verification session.\n'
                            '• We do not use face data for advertising or for unrelated user profiling.\n\n'
                            'Storage, service providers, and sharing:\n'
                            '• Face-related information (such as images, embeddings where applicable, flags, timestamps, and linked attendance records) may be stored in Google Firebase, including Cloud Firestore and Cloud Storage, as part of operating the app. Google provides these services under applicable terms as a service provider.\n'
                            '• On Android, ML Kit face detection runs on your device; we do not send your camera stream to Google for that on-device detection step.\n'
                            '• The iOS embedded experience may be delivered through hosting we use; account and attendance data for your profile are stored in our Firebase project.\n'
                            '• We do not sell face data. We do not share it with third parties for their independent marketing purposes.\n\n'
                            'Retention:\n'
                            '• We retain face-related information for as long as your account is active and the attendance service requires it, unless the law requires a shorter period or we delete it sooner following account closure or a valid deletion or data request we honor.\n\n'
                            '3. How We Use Your Information\n'
                            'In addition to Section 2, we use the information we collect to:\n'
                            '• Provide and maintain our services\n'
                            '• Process attendance and manage records\n'
                            '• Communicate with you about your account\n'
                            '• Improve our services and user experience\n\n'
                            '4. Data Security\n'
                            'We implement appropriate technical and organizational measures to protect your personal information. However, no method of transmission over the internet is 100% secure.\n\n'
                            '5. Your Rights\n'
                            'You have the right to:\n'
                            '• Access your personal data\n'
                            '• Request correction of inaccurate data\n'
                            '• Request deletion of your data (including face-related data tied to your account, subject to legal or operational limits)\n'
                            '• Withdraw consent at any time\n\n'
                            '6. Contact Us\n'
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
