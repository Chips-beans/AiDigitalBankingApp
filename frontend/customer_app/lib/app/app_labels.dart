import 'package:flutter/material.dart';

import 'app_preferences.dart';

/// Labels for the built email continuation/onboarding screens.
String tx(BuildContext context, String english) =>
    AppPreferences.maybeOf(context)?.isKhmer == true
    ? _khmer[english] ?? english
    : english;

const _khmer = <String, String>{
  'Kesor Scan': 'កេសរ ស្កេន',
  'Flash': 'ពិល',
  'Upload QR': 'បញ្ចូលរូប QR',
  'Reading QR code…': 'កំពុងអានកូដ QR…',
  'Kesor account QR · USD / KHR': 'កូដ QR គណនីកេសរ · USD / KHR',
  'Transfer': 'ផ្ទេរប្រាក់',
  'Back': 'ត្រឡប់ក្រោយ',
  'Kesor Transfer': 'ការផ្ទេរប្រាក់ កេសរ',
  'Fast, secure wallet transfers': 'ផ្ទេរប្រាក់រហ័ស និងមានសុវត្ថិភាព',
  'Select your account': 'ជ្រើសរើសគណនីរបស់អ្នក',
  'US Dollar Wallet': 'កាបូបប្រាក់ដុល្លារ',
  'Khmer Riel Wallet': 'កាបូបប្រាក់រៀល',
  'Receiver account number': 'លេខគណនីអ្នកទទួល',
  'Enter the receiver’s Kesor account number.':
      'បញ្ចូលលេខគណនី Kesor របស់អ្នកទទួល។',
  'Transfer currency follows your selected wallet.':
      'រូបិយប័ណ្ណផ្ទេរតាមកាបូបប្រាក់ដែលអ្នកជ្រើសរើស។',
  'Add a note...': 'បន្ថែមកំណត់សម្គាល់...',
  'Remark (optional)': 'កំណត់សម្គាល់ (មិនបាច់ក៏បាន)',
  'Save to Favorites': 'រក្សាទុកក្នុងបញ្ជីពេញចិត្ត',
  'Quick access for future transfers': 'ងាយស្រួលសម្រាប់ការផ្ទេរប្រាក់លើកក្រោយ',
  'Continue to review': 'បន្តទៅពិនិត្យ',
  'Saved recipients': 'អ្នកទទួលដែលបានរក្សាទុក',
  'No saved recipients for this wallet yet.':
      'មិនទាន់មានអ្នកទទួលដែលបានរក្សាទុកសម្រាប់កាបូបនេះទេ។',
  'Remove saved recipient': 'លុបអ្នកទទួលដែលបានរក្សាទុក',
  'Save recipient': 'រក្សាទុកអ្នកទទួល',
  'Close': 'បិទ',
  'Retry saved recipients': 'សាកល្បងផ្ទុកអ្នកទទួលម្ដងទៀត',
  'Saved recipients could not be loaded. You can still enter an account number.':
      'មិនអាចផ្ទុកអ្នកទទួលដែលបានរក្សាទុកបានទេ។ អ្នកនៅតែអាចបញ្ចូលលេខគណនីបាន។',
  'Transfer confirmed. The recipient could not be saved.':
      'បានបញ្ជាក់ការផ្ទេរប្រាក់។ មិនអាចរក្សាទុកអ្នកទទួលបានទេ។',
  'Enter 10–20 digits.': 'បញ្ចូលលេខពី ១០ ដល់ ២០ ខ្ទង់។',
  'Enter an amount.': 'បញ្ចូលចំនួនប្រាក់។',
  'Remark must be 255 characters or fewer.':
      'កំណត់សម្គាល់មិនត្រូវលើសពី ២៥៥ តួអក្សរទេ។',
  'Choose an active source account.': 'ជ្រើសរើសគណនីដើមដែលសកម្ម។',
  'Enter a different destination account number with 10–20 digits.':
      'បញ្ចូលលេខគណនីអ្នកទទួលផ្សេងពីគណនីដើម ដែលមានពី ១០ ដល់ ២០ ខ្ទង់។',
  'Enter an amount with at most two decimal places.':
      'បញ្ចូលចំនួនប្រាក់ដែលមានខ្ទង់ទសភាគមិនលើសពីពីរខ្ទង់។',
  'Enter a whole KHR amount.': 'បញ្ចូលចំនួនប្រាក់រៀលជាលេខគត់។',
  'Enter an amount within the supported range.':
      'បញ្ចូលចំនួនប្រាក់ក្នុងដែនកំណត់ដែលអនុញ្ញាត។',
  'Amount must be greater than zero.': 'ចំនួនប្រាក់ត្រូវតែធំជាងសូន្យ។',
  'The amount exceeds the last known available balance. Refresh your account.': 'ចំនួនប្រាក់លើសពីសមតុល្យដែលអាចប្រើបាន។ សូមធ្វើបច្ចុប្បន្នភាពគណនីរបស់អ្នក។',
  'Retry transfer secure setup': 'ព្យាយាមផ្ទៀងផ្ទាត់សុវត្ថិភាពការផ្ទេរម្ដងទៀត',
  'Open an account from Home before making a transfer.':
      'សូមបើកគណនីពីទំព័រដើម មុនពេលផ្ទេរប្រាក់។',
  'Sending transfers is available in the native app with the real API. This preview does not send payments.': 'ការផ្ញើប្រាក់មានក្នុងកម្មវិធីដែលភ្ជាប់ API ពិតប្រាកដ។ ការមើលសាកល្បងនេះមិនផ្ញើប្រាក់ទេ។',
  'Open accounts': 'បើកគណនី',
  'Select account': 'ជ្រើសរើសគណនី',
  'View account details': 'មើលព័ត៌មានគណនី',
  'View recent activity': 'មើលប្រតិបត្តិការថ្មីៗ',
  'Account opening is unavailable. Try again later.':
      'មិនអាចបើកគណនីបានទេ។ សូមព្យាយាមម្ដងទៀតនៅពេលក្រោយ។',
  'Account type': 'ប្រភេទគណនី',
  'Savings': 'គណនីសន្សំ',
  'Checking': 'គណនីចរន្ត',
  'Payroll': 'គណនីប្រាក់បៀវត្ស',
  'Please wait…': 'សូមរង់ចាំ…',
  'This transfer may already have completed. Retry sends exactly the same transfer with the original request key. If it was not processed, retry may complete the transfer. A timeout alone does not establish failure.': 'ការផ្ទេរប្រាក់នេះអាចបានបញ្ចប់។ ការព្យាយាមម្ដងទៀតផ្ញើការផ្ទេរដដែលជាមួយលេខសំណើដើម។ ប្រសិនបើមិនទាន់ដំណើរការ វាអាចបញ្ចប់ការផ្ទេរប្រាក់។ ការអស់ពេលរង់ចាំមិនមានន័យថាបរាជ័យទេ។',
  'No transfer was posted.': 'មិនមានការផ្ទេរប្រាក់ត្រូវបានកត់ត្រាទេ។',
  'USD and KHR accounts': 'គណនីដុល្លារ និងរៀល',
  'Opening balances': 'សមតុល្យដំបូង',
  'Test funds for non-production transfer testing.':
      'ប្រាក់សាកល្បងសម្រាប់សាកល្បងការផ្ទេរប្រាក់។',
  'Confirm open accounts': 'បញ្ជាក់បើកគណនី',
  'Accounts opened': 'បានបើកគណនី',
  'Retry this exact opening request': 'សាកល្បងសំណើបើកគណនីដដែលម្ដងទៀត',
  'This request may have completed. Retry uses the original request and cannot create another pair.': 'សំណើនេះអាចបានបញ្ចប់។ ការសាកល្បងម្ដងទៀតប្រើសំណើដដែល ហើយមិនបង្កើតគណនីមួយគូទៀតទេ។',
  'Review the earlier account-opening request first.':
      'សូមពិនិត្យសំណើបើកគណនីមុនជាមុនសិន។',
  'Retry': 'ព្យាយាមម្ដងទៀត',
  'An account-opening request needs attention.':
      'សូមពិនិត្យសំណើបើកគណនីដែលបានរក្សាទុក។',
  'Account-opening safety could not be loaded.':
      'មិនអាចផ្ទុកសំណើបើកគណនីដែលបានរក្សាទុកបានទេ។',
  'Account-opening safety could not be saved.':
      'មិនអាចរក្សាទុកសំណើបើកគណនីដោយសុវត្ថិភាពបានទេ។',
  'The saved account-opening request could not be verified.':
      'មិនអាចផ្ទៀងផ្ទាត់សំណើបើកគណនីដែលបានរក្សាទុកបានទេ។',
  'Accounts opened. Refresh to obtain current balances.':
      'បានបើកគណនី។ សូមធ្វើបច្ចុប្បន្នភាពដើម្បីទទួលបានសមតុល្យបច្ចុប្បន្ន។',
  'QR could not be loaded. Try again.':
      'មិនអាចផ្ទុកកូដ QR បានទេ។ សូមព្យាយាមម្ដងទៀត។',
  'Payment status could not refresh.':
      'មិនអាចធ្វើបច្ចុប្បន្នភាពស្ថានភាពទូទាត់បានទេ។',
  'My QR': 'កូដ QR របស់ខ្ញុំ',
  'Scan QR': 'ស្កេនកូដ QR',
  'Receive money': 'ទទួលប្រាក់',
  'Choose an account': 'ជ្រើសរើសគណនី',
  'Choose an active account to receive money.':
      'ជ្រើសរើសគណនីដែលសកម្ម ដើម្បីទទួលប្រាក់។',
  'Reusable account QR': 'កូដ QR គណនីដែលអាចប្រើម្ដងទៀត',
  'Use this QR to receive Kesor internal transfers.':
      'ប្រើកូដ QR នេះដើម្បីទទួលការផ្ទេរប្រាក់ក្នុង Kesor។',
  'Request an amount': 'ស្នើសុំចំនួនប្រាក់',
  'Amount': 'ចំនួនប្រាក់',
  'Create amount request': 'បង្កើតសំណើចំនួនប្រាក់',
  'Show reusable QR': 'បង្ហាញកូដ QR ដែលអាចប្រើម្ដងទៀត',
  'Waiting for payment': 'កំពុងរង់ចាំការទូទាត់',
  'Payment received': 'បានទទួលប្រាក់',
  'This amount request can be paid once.':
      'សំណើចំនួនប្រាក់នេះអាចទូទាត់បានតែមួយដង។',
  'Load more accounts': 'ផ្ទុកគណនីបន្ថែម',
  'Open an account before receiving money.': 'សូមបើកគណនីមុនពេលទទួលប្រាក់។',
  'QR features require the API app.': 'មុខងារ QR ត្រូវការកម្មវិធីភ្ជាប់ API។',
  'Point your camera at a Kesor account QR.':
      'តម្រង់កាមេរ៉ាទៅកូដ QR គណនី Kesor។',
  'Choose QR image': 'ជ្រើសរើសរូបភាព QR',
  'Scan again': 'ស្កេនម្ដងទៀត',
  'Torch': 'ពិល',
  'Camera access is denied. Enable it in device settings, or choose a QR image.': 'មិនមានសិទ្ធិប្រើកាមេរ៉ា។ សូមបើកសិទ្ធិក្នុងការកំណត់ឧបករណ៍ ឬជ្រើសរើសរូបភាព QR។',
  'Camera is unavailable. Retry or choose a QR image.':
      'មិនអាចប្រើកាមេរ៉ាបាន។ សូមព្យាយាមម្ដងទៀត ឬជ្រើសរើសរូបភាព QR។',
  'Camera and image scanning are available in the Android and iOS app.':
      'ការស្កេនតាមកាមេរ៉ា និងរូបភាពមានក្នុងកម្មវិធី Android និង iOS។',
  'Choose a JPG or PNG containing one QR code, up to 5 MB.':
      'ជ្រើសរើស JPG ឬ PNG ដែលមានកូដ QR មួយ មិនលើស 5 MB។',
  'No QR code was found. Choose another image.':
      'រកមិនឃើញកូដ QR។ សូមជ្រើសរើសរូបភាពផ្សេង។',
  'Recipient': 'អ្នកទទួល',
  'Source account': 'គណនីដើម',
  'No active source account matches this currency.':
      'មិនមានគណនីដើមដែលសកម្ម និងមានរូបិយប័ណ្ណដូចគ្នាទេ។',
  'Review transfer': 'ពិនិត្យការផ្ទេរប្រាក់',
  'Confirm and send': 'បញ្ជាក់ និងផ្ញើប្រាក់',
  'Edit transfer': 'កែប្រែការផ្ទេរប្រាក់',
  'Transfer confirmed': 'បានបញ្ជាក់ការផ្ទេរប្រាក់',
  'Transfer rejected': 'ការផ្ទេរប្រាក់ត្រូវបានបដិសេធ',
  'Transfer outcome unknown': 'មិនទាន់ដឹងលទ្ធផលនៃការផ្ទេរប្រាក់',
  'FROM ACCOUNT': 'ពីគណនី',
  'TO ACCOUNT': 'ទៅគណនី',
  'Fee': 'កម្រៃ',
  'Total debit': 'ប្រាក់កាត់សរុប',
  'Remark': 'កំណត់សម្គាល់',
  'TRANSACTION REFERENCE': 'លេខយោងប្រតិបត្តិការ',
  'Status: SUCCESS': 'ស្ថានភាព៖ ជោគជ័យ',
  'Done — return to transfer entry': 'រួចរាល់ — ត្រឡប់ទៅការផ្ទេរប្រាក់',
  'Retry this exact transfer': 'សាកល្បងការផ្ទេរប្រាក់ដដែលម្ដងទៀត',
  'Check the recipient, account and amount before confirming.':
      'សូមពិនិត្យអ្នកទទួល គណនី និងចំនួនប្រាក់មុនពេលបញ្ជាក់។',
  'Only registered Kesor QR codes are supported.':
      'អាចប្រើបានតែកូដ QR ដែលបានចុះបញ្ជីក្នុង Kesor ប៉ុណ្ណោះ។',
  'This request has already been paid.': 'សំណើនេះត្រូវបានទូទាត់រួចហើយ។',
  'Enter a positive amount within the currency precision and supported range.':
      'សូមបញ្ចូលចំនួនប្រាក់វិជ្ជមានតាមខ្ទង់រូបិយប័ណ្ណ និងក្នុងដែនកំណត់។',
  'Both accounts must use the transfer currency.':
      'គណនីទាំងពីរត្រូវប្រើរូបិយប័ណ្ណដូចគ្នា។',
  'There are not enough funds in the source account.':
      'គណនីដើមមិនមានប្រាក់គ្រប់គ្រាន់ទេ។',
  'Both accounts must be active to make a transfer.':
      'គណនីទាំងពីរត្រូវសកម្មដើម្បីផ្ទេរប្រាក់។',
  'The amount does not match this QR request.':
      'ចំនួនប្រាក់មិនត្រូវនឹងសំណើ QR នេះទេ។',
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
