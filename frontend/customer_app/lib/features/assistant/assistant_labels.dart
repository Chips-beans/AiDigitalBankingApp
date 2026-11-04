import 'package:flutter/widgets.dart';

import '../../app/app_labels.dart';
import '../../app/app_preferences.dart';

String aiText(BuildContext context, String english) =>
    AppPreferences.maybeOf(context)?.isKhmer == true
    ? (_khmer[english] ?? tx(context, english))
    : english;
const _khmer = <String, String>{
  'AI Assistant': 'ជំនួយការ AI',
  'How can I help you today?': 'តើខ្ញុំអាចជួយអ្នកអ្វីបានថ្ងៃនេះ?',
  'Ask about your spending, transfers or account security.':
      'សួរអំពីចំណាយ ការផ្ទេរ ឬសុវត្ថិភាពគណនីរបស់អ្នក។',
  'Try asking': 'សាកល្បងសួរ',
  'How much have I spent this month?': 'តើខ្ញុំបានចំណាយអស់ប៉ុន្មានក្នុងខែនេះ?',
  'Can you show my recent transfers?':
      'តើអ្នកអាចបង្ហាញការផ្ទេរថ្មីៗរបស់ខ្ញុំបានទេ?',
  'How can I keep my account secure?':
      'តើខ្ញុំអាចរក្សាសុវត្ថិភាពគណនីបានយ៉ាងដូចម្តេច?',
  'Ask Kesor Assistant…': 'សួរជំនួយការ Kesor…',
  'Never share your PIN, password or OTP.':
      'កុំចែករំលែក PIN ពាក្យសម្ងាត់ ឬ OTP របស់អ្នក។',
  'Your question and only the figures needed to answer it are sent to the AI service; names and account numbers are not. General answers are information, not financial advice. Conversations are kept for 30 days.': 'សំណួររបស់អ្នក និងតួលេខចាំបាច់សម្រាប់ការឆ្លើយតបប៉ុណ្ណោះ ត្រូវបានផ្ញើទៅសេវាកម្ម AI ឈ្មោះ និងលេខគណនីមិនត្រូវបានផ្ញើទេ។ ចម្លើយទូទៅគ្រាន់តែជាព័ត៌មាន មិនមែនជាដំបូន្មានហិរញ្ញវត្ថុទេ។ ការសន្ទនាត្រូវបានរក្សាទុករយៈពេល ៣០ ថ្ងៃ។',
  'AI-written general information': 'ព័ត៌មានទូទៅដែល AI សរសេរ',
  'AI-written general information · Account figures are verified':
      'ព័ត៌មានទូទៅដែល AI សរសេរ · តួលេខគណនីត្រូវបានផ្ទៀងផ្ទាត់',
  'Compare this month with last month': 'ប្រៀបធៀបខែនេះនឹងខែមុន',
  'How much did I spend this week?':
      'តើខ្ញុំបានចំណាយអស់ប៉ុន្មានក្នុងសប្តាហ៍នេះ?',
  'How can I build an emergency fund?':
      'តើខ្ញុំអាចបង្កើតមូលនិធិសង្គ្រោះបន្ទាន់បានយ៉ាងដូចម្តេច?',
  'Ask about your accounts, your spending, how to use Kesor, or money in general.':
      'សួរអំពីគណនី ការចំណាយ របៀបប្រើ Kesor ឬប្រាក់ជាទូទៅ។',
  'Ask about your spending, your accounts, or money in general.':
      'សួរអំពីការចំណាយ គណនីរបស់អ្នក ឬប្រាក់ជាទូទៅ។',
  'This request key belongs to a different assistant request.':
      'សោសំណើនេះជារបស់សំណើជំនួយការផ្សេង។',
  'AI assistant': 'ជំនួយការ AI',
  'Your Kesor assistant': 'ជំនួយការ Kesor របស់អ្នក',
  'Understand your money. Find the details.':
      'យល់អំពីប្រាក់របស់អ្នក និងស្វែងរកព័ត៌មាន។',
  'Show my balances': 'បង្ហាញសមតុល្យរបស់ខ្ញុំ',
  'Summarize this month': 'សង្ខេបសកម្មភាពខែនេះ',
  'Find recent transfers': 'ស្វែងរកការផ្ទេរថ្មីៗ',
  'How do I receive money by QR?': 'តើខ្ញុំទទួលប្រាក់តាម QR យ៉ាងដូចម្តេច?',
  'New conversation': 'ការសន្ទនាថ្មី',
  'Conversation history': 'ប្រវត្តិសន្ទនា',
  'Conversations expire after 30 days. You can delete them earlier.':
      'ការសន្ទនាផុតកំណត់បន្ទាប់ពី ៣០ ថ្ងៃ។ អ្នកអាចលុបមុនពេលនោះ។',
  'No conversations yet.': 'មិនទាន់មានការសន្ទនាទេ។',
  'Load more conversations': 'ផ្ទុកការសន្ទនាបន្ថែម',
  'Load earlier messages': 'ផ្ទុកសារមុនៗ',
  'Rename conversation': 'ប្តូរឈ្មោះការសន្ទនា',
  'Conversation title': 'ចំណងជើងការសន្ទនា',
  'Delete conversation': 'លុបការសន្ទនា',
  'Delete this conversation?': 'លុបការសន្ទនានេះ?',
  'This removes the conversation from your history.':
      'វានឹងលុបការសន្ទនានេះចេញពីប្រវត្តិរបស់អ្នក។',
  'Rename': 'ប្តូរឈ្មោះ',
  'Delete': 'លុប',
  'Save': 'រក្សាទុក',
  'Cancel': 'បោះបង់',
  'Close': 'បិទ',
  'Refresh conversations': 'ផ្ទុកការសន្ទនាឡើងវិញ',
  'Ask Kesor a question': 'សួរសំណួរទៅ Kesor',
  'Send question': 'ផ្ញើសំណួរ',
  'Thinking…': 'កំពុងគិត…',
  'Read-only assistant · You confirm all payments in the transfer flow.':
      'ជំនួយការសម្រាប់មើលព័ត៌មាន · អ្នកបញ្ជាក់ការផ្ញើប្រាក់ក្នុងមុខងារផ្ទេរ។',
  'Never share PINs, OTPs or passwords.': 'កុំចែករំលែក PIN OTP ឬពាក្យសម្ងាត់។',
  'The assistant is unavailable. Your banking services remain available.':
      'ជំនួយការមិនអាចប្រើបានទេ។ សេវាធនាគាររបស់អ្នកនៅតែអាចប្រើបាន។',
  'Retry assistant setup': 'ព្យាយាមរៀបចំជំនួយការឡើងវិញ',
  'Retry secure setup': 'ព្យាយាមរៀបចំសុវត្ថិភាពឡើងវិញ',
  'The saved question could not be read or saved. Sending is blocked.':
      'មិនអាចអាន ឬរក្សាទុកសំណួរបានទេ។ ការផ្ញើត្រូវបានផ្អាក។',
  'The assistant response could not be verified.':
      'មិនអាចផ្ទៀងផ្ទាត់ចម្លើយរបស់ជំនួយការបានទេ។',
  'Do not send PINs, OTPs, passwords or authentication tokens.':
      'កុំផ្ញើ PIN OTP ពាក្យសម្ងាត់ ឬសោផ្ទៀងផ្ទាត់អត្តសញ្ញាណ។',
  'Enter a question of up to 2,000 characters.':
      'បញ្ចូលសំណួរមិនលើសពី ២,០០០ តួអក្សរ។',
  'Saved question': 'សំណួរដែលបានរក្សាទុក',
  'The request failed. Retry sends a new assistant request.':
      'សំណើបានបរាជ័យ។ ការសាកល្បងម្តងទៀតនឹងផ្ញើសំណើថ្មី។',
  'No saved result was found. An explicit retry uses the original request key.':
      'មិនរកឃើញលទ្ធផលដែលបានរក្សាទុកទេ។ ការសាកល្បងម្តងទៀតប្រើសោសំណើដើម។',
  'The result is not confirmed yet. Checking status does not resend your question.':
      'មិនទាន់បញ្ជាក់លទ្ធផលបានទេ។ ការពិនិត្យស្ថានភាពមិនផ្ញើសំណួរឡើងវិញទេ។',
  'Retry saved question': 'សាកល្បងសំណួរដែលបានរក្សាទុក',
  'Check status': 'ពិនិត្យស្ថានភាព',
  'Dismiss saved question': 'បិទសំណួរដែលបានរក្សាទុក',
  'Stop recovering this question?': 'ឈប់ស្ដារសំណួរនេះ?',
  'A question already sent may still finish and appear in server history. This does not cancel provider processing.': 'សំណួរដែលបានផ្ញើអាចបញ្ចប់ ហើយបង្ហាញក្នុងប្រវត្តិម៉ាស៊ីនមេ។ វាមិនបោះបង់ដំណើរការរបស់អ្នកផ្តល់សេវាទេ។',
  'Verified bank data': 'ទិន្នន័យធនាគារដែលបានផ្ទៀងផ្ទាត់',
  'Data as of': 'ទិន្នន័យគិតត្រឹម',
  'AI explanation': 'ការពន្យល់ដោយ AI',
  'AI explanation unavailable · Verified figures shown':
      'ការពន្យល់ AI មិនមាន · បង្ហាញទិន្នន័យដែលបានផ្ទៀងផ្ទាត់',
  'View account': 'មើលគណនី',
  'View accounts': 'មើលគណនីទាំងអស់',
  'View receipt': 'មើលបង្កាន់ដៃ',
  'Open Analytics': 'បើកការវិភាគ',
  'Open screen': 'បើកទំព័រ',
  'More transactions': 'ប្រតិបត្តិការបន្ថែម',
  'Already loaded': 'បានផ្ទុករួចហើយ',
  'Assistant request limit reached. Try again later.':
      'បានដល់កំណត់សំណើជំនួយការ។ សូមព្យាយាមនៅពេលក្រោយ។',
  'The assistant is busy. Try again shortly.':
      'ជំនួយការកំពុងរវល់។ សូមព្យាយាមម្ដងទៀត។',
  'The assistant timed out. Check the saved request before retrying.':
      'ជំនួយការអស់ពេលរង់ចាំ។ ពិនិត្យសំណើដែលបានរក្សាទុកមុនសាកល្បងឡើងវិញ។',
  'This assistant request was interrupted. Retry explicitly to ask again.':
      'សំណើជំនួយការនេះត្រូវបានរំខាន។ សូមសាកល្បងដោយផ្ទាល់ដើម្បីសួរឡើងវិញ។',
};
