import 'package:flutter/material.dart';

import 'app_preferences.dart';

/// Labels for the built email continuation/onboarding screens.
String tx(BuildContext context, String english) =>
    AppPreferences.maybeOf(context)?.isKhmer == true
    ? _khmer[english] ?? english
    : english;

const _khmer = <String, String>{
  'Continue with email': 'បន្តជាមួយអ៊ីមែល',
  'Connect your email': 'ភ្ជាប់អ៊ីមែលរបស់អ្នក',
  'We’ll send a verification code. Your profile will be ready whether you’re new or returning.': 'យើងនឹងផ្ញើលេខកូដផ្ទៀងផ្ទាត់។ អ្នកថ្មី និងអ្នកត្រឡប់មកវិញអាចប្រើវិធីដូចគ្នា។',
  'Verify an email you control. If it already has a profile, we’ll help you use that profile.': 'ផ្ទៀងផ្ទាត់អ៊ីមែលរបស់អ្នក ដើម្បីប្រើប្រវត្តិរូបដែលមានស្រាប់ ឬបំពេញប្រវត្តិរូបថ្មី។',
  'Email address': 'អាសយដ្ឋានអ៊ីមែល',
  'Enter a valid email address.': 'សូមបញ្ចូលអាសយដ្ឋានអ៊ីមែលត្រឹមត្រូវ។',
  'Send verification code': 'ផ្ញើលេខកូដផ្ទៀងផ្ទាត់',
  'Check your email': 'ពិនិត្យអ៊ីមែលរបស់អ្នក',
  'Email code': 'លេខកូដអ៊ីមែល',
  '6 digits': '៦ ខ្ទង់',
  'Enter the 6-digit code.': 'សូមបញ្ចូលលេខកូដ ៦ ខ្ទង់។',
  'Verify and continue': 'ផ្ទៀងផ្ទាត់ ហើយបន្ត',
  'Resend code': 'ផ្ញើលេខកូដម្ដងទៀត',
  'Change your details': 'កែព័ត៌មានរបស់អ្នក',
  'A little about you': 'ព័ត៌មានអំពីអ្នក',
  'Your identity is verified. Complete your details to make this profile yours.': 'អត្តសញ្ញាណរបស់អ្នកត្រូវបានផ្ទៀងផ្ទាត់។ សូមបំពេញព័ត៌មានប្រវត្តិរូបរបស់អ្នក។',
  'First name': 'នាមខ្លួន',
  'Last name': 'នាមត្រកូល',
  'Continue to Kesor': 'បន្តទៅកេសរ',
  'Use at most 50 characters.': 'ប្រើមិនលើសពី ៥០ តួអក្សរ។',
  'Connect an existing email profile': 'ភ្ជាប់ប្រវត្តិរូបអ៊ីមែលដែលមានស្រាប់',
  'Use another identity': 'ប្រើអត្តសញ្ញាណផ្សេង',
  'This code has expired. Request a new one.':
      'លេខកូដផុតកំណត់។ សូមស្នើលេខកូដថ្មី។',
  'That code did not match. Check the latest email and try again.':
      'លេខកូដមិនត្រឹមត្រូវ។ សូមពិនិត្យអ៊ីមែលថ្មីបំផុត ហើយព្យាយាមម្ដងទៀត។',
  'Demo mode: use code 123456. No email is sent.':
      'មុខងារសាកល្បង៖ ប្រើលេខកូដ 123456។ មិនមានការផ្ញើអ៊ីមែលទេ។',
};
