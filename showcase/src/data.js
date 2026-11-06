// Project content. Values still marked TODO need the real course details.

export const links = {
  customerApk: '/downloads/kesor-bank.apk',
  merchantApk: '/downloads/kesor-merchant.apk',
  github: 'https://github.com/Chips-beans/AiDigitalBankingApp.git',
  figma: 'https://www.figma.com/design/Mkhqgqnt1SQoq4pn9INLY5/Kesor-Bank?node-id=0-1&t=ppdiwUKRES7w9SYc-1',
};

export const customerFeatures = [
  {
    name: 'Home & balances',
    screen: 'c-home',
    text: 'Riel and dollar totals at a glance, three quick actions, favourite recipients and the latest activity. Money stays masked until the PIN is entered.',
  },
  {
    name: 'Wallets',
    screen: 'c-wallet',
    text: 'A KHR and a USD wallet are opened automatically at sign-up, each with its own account number and history.',
  },
  {
    name: 'Transfers',
    screen: 'c-transfer',
    text: 'Look up a recipient by account, pick the wallet, review the fixed 1 USD = 4,000 KHR conversion and confirm with a 4-digit PIN.',
  },
  {
    name: 'QR pay',
    screen: 'c-scan',
    text: 'Scan a Kesor shop QR, see the verified shop name before paying, or show your own QR with a requested amount.',
  },
  {
    name: 'Analytics',
    screen: 'c-analytics',
    text: 'A monthly overview of money in and money out, with a daily chart and the categories that moved the most.',
  },
  {
    name: 'AI assistant',
    screen: 'c-ai',
    text: 'A read-only assistant that answers questions about your own spending in English or Khmer and never moves money.',
  },
];

export const merchantFeatures = [
  {
    name: 'Shop home',
    screen: 'm-home',
    text: "Today's collections in riel and dollars, the shop's status and both business wallets on one screen.",
  },
  {
    name: 'Collect',
    screen: 'm-amount',
    text: 'Type an amount, choose the currency and a payment request with its own QR is ready for the customer.',
  },
  {
    name: 'Shop QR',
    screen: 'm-qr',
    text: 'A permanent QR for the counter, so customers can pay any amount without a request.',
  },
  {
    name: 'Sales',
    screen: 'm-sales',
    text: 'Every payment received, searchable, with a receipt for each one.',
  },
  {
    name: 'Reports',
    screen: 'm-reports',
    text: 'Daily and monthly totals per currency, so the owner knows how the shop is doing.',
  },
  {
    name: 'Owner transfer',
    screen: 'm-transfer',
    text: 'Move takings to the owner’s personal wallet, approved in the Customer App with the owner’s PIN.',
  },
];

// How it works: one payment of 12,000 riel at a coffee shop.
// active: which actor does the work in this stage.
export const stages = [
  {
    name: 'Request',
    clause: 'The shop asks for 12,000 riel',
    active: 'merchant',
    customer: 'c-home',
    merchant: 'm-waiting',
    log: ['POST /api/merchant/payment-requests  201', '  amount 12000 KHR · expires in 5 min'],
  },
  {
    name: 'Scan',
    clause: 'The customer scans the shop QR',
    active: 'customer',
    customer: 'c-pay',
    merchant: 'm-waiting',
    log: ['GET  /api/qr/resolve  200', '  shop "Kesor Coffee" · verified'],
  },
  {
    name: 'Confirm',
    clause: 'The customer confirms with a PIN',
    active: 'customer',
    customer: 'c-pin',
    merchant: 'm-waiting',
    log: ['POST /api/auth/pin/proof  200', '  proof issued · valid 60 s'],
  },
  {
    name: 'Settle',
    clause: 'The backend moves the money',
    active: 'backend',
    customer: 'c-pin',
    merchant: 'm-waiting',
    log: [
      'POST /api/payments  201',
      '  debit  KHR wallet ···7890   -12,000',
      '  credit shop wallet ···4521  +12,000',
      '  transaction TX-2611-0412 committed',
    ],
  },
  {
    name: 'Paid',
    clause: 'Both apps show it is paid',
    active: 'merchant',
    customer: 'c-receipt',
    merchant: 'm-received',
    log: ['PUSH payment.received → shop', 'PUSH transfer.sent → customer'],
  },
];

// Audited against the repo: backend/digital-banking/pom.xml, both pubspec.yaml files,
// the backend Dockerfile, application.properties (Gmail API OTP, JWT) and the AI
// gateway (Groq, OpenAI-compatible). icon: a simple-icons key, or 'groq' (custom mark).
export const stack = [
  {
    group: 'Mobile',
    items: [
      { name: 'Flutter', icon: 'siFlutter' },
      { name: 'Dart', icon: 'siDart' },
      { name: 'Android', icon: 'siAndroid' },
    ],
  },
  {
    group: 'Backend',
    items: [
      { name: 'Spring Boot', icon: 'siSpringboot' },
      { name: 'Java 21', icon: 'siOpenjdk' },
      { name: 'Spring Security', icon: 'siSpringsecurity' },
      { name: 'Spring Data JPA', icon: 'siHibernate' },
      { name: 'JWT', icon: 'siJsonwebtokens' },
      { name: 'Maven', icon: 'siApachemaven' },
      { name: 'OpenAPI', icon: 'siSwagger' },
    ],
  },
  {
    group: 'Database',
    items: [
      { name: 'PostgreSQL', icon: 'siPostgresql' },
      { name: 'Flyway', icon: 'siFlyway' },
    ],
  },
  {
    group: 'Tools',
    items: [
      { name: 'GitHub', icon: 'siGithub' },
      { name: 'Figma', icon: 'siFigma' },
      { name: 'Docker', icon: 'siDocker' },
      { name: 'Railway', icon: 'siRailway' },
      { name: 'JUnit 5', icon: 'siJunit5' },
      { name: 'Gmail API', icon: 'siGmail' },
      { name: 'Telegram', icon: 'siTelegram' },
      { name: 'Groq', icon: 'groq' },
    ],
  },
];

// Roles and contributions supplied by the project owner; the third profile is retained.
// Avatars: DiceBear "Avataaars" (artwork by Pablo
// Stanley, free for personal and commercial use), saved locally.
export const team = [
  {
    name: 'Seng Sovanreach',
    role: 'Back-end Developer · Flutter Developer · UX/UI Designer',
    duties: 'Product direction, the Figma designs, both Flutter apps and the Spring Boot backend. Also responsible for DevOps, hosting and deployment.',
    photo: '/team/member-1-male.svg',
  },
  {
    name: 'Say Kokann',
    role: 'Back-end Developer · QA Tester',
    duties: 'Back-end development and app testing across the Customer and Merchant apps.',
    photo: '/team/member-2-male.svg',
  },
  {
    name: 'Som Chhorpornrangsey',
    role: 'Developer',
    duties: 'Building and testing features across the Customer and Merchant apps.',
    photo: '/team/member-3-female.svg',
  },
];

// AI tools shown in the team dome. The files have neutral names on purpose:
// some ad-blocker filter lists block image URLs containing AI product names.
export const aiTools = [
  { src: '/team/tool-1.webp', alt: 'Gemini' },
  { src: '/team/tool-2.webp', alt: 'Claude' },
  { src: '/team/tool-3.webp', alt: 'Codex' },
];

// TODO real course details
export const project = {
  university: 'Royal University of Example',
  course: 'Senior Project · Mobile & Web Development',
  year: 'Academic year 2025–2026',
  city: 'Phnom Penh',
};
