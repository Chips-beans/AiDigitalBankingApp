import 'package:flutter/material.dart';

import 'app_preferences.dart';

/// Labels for the built email continuation/onboarding screens.
String tx(BuildContext context, String english) =>
    AppPreferences.maybeOf(context)?.isKhmer == true
    ? _khmer[english] ?? english
    : english;

const _khmer = <String, String>{
  'Send Code': 'ផ្ញើលេខកូដ',
  'Verification code': 'លេខកូដផ្ទៀងផ្ទាត់',
  'Enter the 6-digit code sent to': 'បញ្ចូលលេខកូដ ៦ ខ្ទង់ដែលបានផ្ញើទៅ',
  'Verify': 'ផ្ទៀងផ្ទាត់',
  'Didn’t receive the code?': 'មិនបានទទួលលេខកូដមែនទេ?',
  'Resend code in': 'ផ្ញើលេខកូដម្ដងទៀតក្នុង',
  'Create profile': 'បង្កើតប្រវត្តិរូប',
  'Let’s get to know you. Add your details to get started.':
      'សូមឱ្យយើងស្គាល់អ្នក។ បញ្ចូលព័ត៌មានរបស់អ្នកដើម្បីចាប់ផ្ដើម។',
  'First Name': 'នាមខ្លួន',
  'Last Name': 'នាមត្រកូល',
  'Your First Name': 'នាមខ្លួនរបស់អ្នក',
  'Your Last Name': 'នាមត្រកូលរបស់អ្នក',
  'Create Account': 'បង្កើតគណនី',
  'I agree to the Terms & Conditions and Privacy Policy':
      'ខ្ញុំយល់ព្រមនឹងលក្ខខណ្ឌប្រើប្រាស់ និងគោលការណ៍ឯកជនភាព',
  'Please agree to the terms and privacy policy to continue.':
      'សូមយល់ព្រមនឹងលក្ខខណ្ឌ និងគោលការណ៍ឯកជនភាពដើម្បីបន្ត។',
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
