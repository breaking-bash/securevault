import 'package:flutter/material.dart';

import 'vault_entry.dart';

/// How a field is edited and rendered.
enum FieldKind {
  text,
  url,
  email,
  date,
  otp,
  password,
  phone,
  multiline,
  number,
}

extension FieldKindInfo on FieldKind {
  String get label => switch (this) {
        FieldKind.text => 'Text',
        FieldKind.url => 'URL',
        FieldKind.email => 'Email address',
        FieldKind.date => 'Date',
        FieldKind.otp => 'One-time password',
        FieldKind.password => 'Password',
        FieldKind.phone => 'Phone',
        FieldKind.multiline => 'Multi-line text',
        FieldKind.number => 'Number',
      };

  IconData get icon => switch (this) {
        FieldKind.text => Icons.text_fields_rounded,
        FieldKind.url => Icons.link_rounded,
        FieldKind.email => Icons.alternate_email_rounded,
        FieldKind.date => Icons.event_rounded,
        FieldKind.otp => Icons.timer_rounded,
        FieldKind.password => Icons.lock_rounded,
        FieldKind.phone => Icons.phone_rounded,
        FieldKind.multiline => Icons.notes_rounded,
        FieldKind.number => Icons.pin_rounded,
      };

  TextInputType get keyboard => switch (this) {
        FieldKind.url => TextInputType.url,
        FieldKind.email => TextInputType.emailAddress,
        FieldKind.phone => TextInputType.phone,
        FieldKind.number => TextInputType.number,
        FieldKind.multiline => TextInputType.multiline,
        _ => TextInputType.text,
      };

  /// Values of this kind are masked until revealed.
  bool get isSecretByDefault =>
      this == FieldKind.password || this == FieldKind.otp;

  /// Kinds offered when adding a custom field.
  static const customKinds = [
    FieldKind.text,
    FieldKind.url,
    FieldKind.email,
    FieldKind.date,
    FieldKind.otp,
    FieldKind.password,
    FieldKind.phone,
  ];
}

class FieldSpec {
  final String key;
  final String label;
  final FieldKind kind;
  final bool secret;
  final bool mono;
  final int maxLines;
  const FieldSpec(
    this.key,
    this.label,
    this.kind, {
    this.secret = false,
    this.mono = false,
    this.maxLines = 1,
  });

  bool get masked => secret || kind.isSecretByDefault;
}

/// Describes one category of vault item: look, and the fields it has.
class ItemTemplate {
  final EntryType type;
  final String label;
  final IconData icon;
  final Color color;
  final List<FieldSpec> fields;
  final List<String> subtitleKeys;
  const ItemTemplate({
    required this.type,
    required this.label,
    required this.icon,
    required this.color,
    this.fields = const [],
    this.subtitleKeys = const [],
  });
}

class ItemTemplates {
  static const signInProviders = [
    'Google',
    'Apple',
    'Microsoft',
    'Facebook',
    'GitHub',
    'X (Twitter)',
    'Amazon',
    'LinkedIn',
    'Other',
  ];
  static const signInKey = 'signInWith';

  static const _all = <EntryType, ItemTemplate>{
    EntryType.login: ItemTemplate(
      type: EntryType.login,
      label: 'Login',
      icon: Icons.language_rounded,
      color: Color(0xFF0572EC),
    ),
    EntryType.card: ItemTemplate(
      type: EntryType.card,
      label: 'Credit Card',
      icon: Icons.credit_card_rounded,
      color: Color(0xFFE8710A),
      subtitleKeys: [EntryFields.cardNumber],
      fields: [
        FieldSpec(EntryFields.cardholder, 'Cardholder name', FieldKind.text),
        FieldSpec(EntryFields.cardNumber, 'Card number', FieldKind.number,
            secret: true),
        FieldSpec(EntryFields.expiry, 'Expiry (MM/YY)', FieldKind.text),
        FieldSpec(EntryFields.cvv, 'Security code (CVV)', FieldKind.number,
            secret: true),
        FieldSpec(EntryFields.pin, 'PIN', FieldKind.number, secret: true),
      ],
    ),
    EntryType.ssh: ItemTemplate(
      type: EntryType.ssh,
      label: 'SSH Key',
      icon: Icons.terminal_rounded,
      color: Color(0xFF455A64),
      subtitleKeys: [EntryFields.fingerprint],
      fields: [
        FieldSpec(EntryFields.publicKey, 'Public key', FieldKind.multiline,
            mono: true, maxLines: 3),
        FieldSpec(EntryFields.privateKey, 'Private key', FieldKind.multiline,
            secret: true, mono: true, maxLines: 6),
        FieldSpec(EntryFields.fingerprint, 'Fingerprint', FieldKind.text),
        FieldSpec(
            EntryFields.passphrase, 'Key passphrase (optional)', FieldKind.text,
            secret: true),
      ],
    ),
    EntryType.passkey: ItemTemplate(
      type: EntryType.passkey,
      label: 'Passkey',
      icon: Icons.key_rounded,
      color: Color(0xFF7B1FA2),
      subtitleKeys: [EntryFields.passkeyUser, EntryFields.rpId],
      fields: [
        FieldSpec(EntryFields.rpId, 'Website (e.g. example.com)', FieldKind.url),
        FieldSpec(EntryFields.passkeyUser, 'User name', FieldKind.text),
        FieldSpec(EntryFields.credentialId, 'Credential ID', FieldKind.text,
            mono: true),
        FieldSpec(EntryFields.privateKey, 'Private key', FieldKind.multiline,
            secret: true, mono: true, maxLines: 6),
      ],
    ),
    EntryType.identity: ItemTemplate(
      type: EntryType.identity,
      label: 'Identity',
      icon: Icons.person_rounded,
      color: Color(0xFF00897B),
      subtitleKeys: ['email', 'phone'],
      fields: [
        FieldSpec('firstName', 'First name', FieldKind.text),
        FieldSpec('lastName', 'Last name', FieldKind.text),
        FieldSpec('birthDate', 'Date of birth', FieldKind.date),
        FieldSpec('email', 'Email', FieldKind.email),
        FieldSpec('phone', 'Phone', FieldKind.phone),
        FieldSpec('company', 'Company', FieldKind.text),
        FieldSpec('jobTitle', 'Job title', FieldKind.text),
        FieldSpec('address', 'Address', FieldKind.multiline, maxLines: 3),
      ],
    ),
    EntryType.bank: ItemTemplate(
      type: EntryType.bank,
      label: 'Bank Account',
      icon: Icons.account_balance_rounded,
      color: Color(0xFF2E7D32),
      subtitleKeys: ['bankName'],
      fields: [
        FieldSpec('bankName', 'Bank name', FieldKind.text),
        FieldSpec('accountHolder', 'Account holder', FieldKind.text),
        FieldSpec('accountNumber', 'Account number', FieldKind.number,
            secret: true),
        FieldSpec('routing', 'Routing / sort code', FieldKind.number),
        FieldSpec('iban', 'IBAN', FieldKind.text, mono: true),
        FieldSpec('swift', 'SWIFT / BIC', FieldKind.text),
        FieldSpec('bankPin', 'PIN', FieldKind.number, secret: true),
        FieldSpec('bankPhone', 'Branch phone', FieldKind.phone),
      ],
    ),
    EntryType.wifi: ItemTemplate(
      type: EntryType.wifi,
      label: 'Wi-Fi Network',
      icon: Icons.wifi_rounded,
      color: Color(0xFF0097A7),
      subtitleKeys: ['ssid'],
      fields: [
        FieldSpec('ssid', 'Network name (SSID)', FieldKind.text),
        FieldSpec('wifiPassword', 'Password', FieldKind.password),
        FieldSpec('wifiSecurity', 'Security (WPA2, WPA3…)', FieldKind.text),
      ],
    ),
    EntryType.server: ItemTemplate(
      type: EntryType.server,
      label: 'Server',
      icon: Icons.dns_rounded,
      color: Color(0xFF5D4037),
      subtitleKeys: ['host'],
      fields: [
        FieldSpec('host', 'Host / IP', FieldKind.url),
        FieldSpec('serverUser', 'Username', FieldKind.text),
        FieldSpec('serverPassword', 'Password', FieldKind.password),
        FieldSpec('serverUrl', 'Admin URL', FieldKind.url),
      ],
    ),
    EntryType.database: ItemTemplate(
      type: EntryType.database,
      label: 'Database',
      icon: Icons.storage_rounded,
      color: Color(0xFF3949AB),
      subtitleKeys: ['dbHost'],
      fields: [
        FieldSpec('dbType', 'Type (PostgreSQL, MySQL…)', FieldKind.text),
        FieldSpec('dbHost', 'Host', FieldKind.url),
        FieldSpec('dbPort', 'Port', FieldKind.number),
        FieldSpec('dbName', 'Database', FieldKind.text),
        FieldSpec('dbUser', 'Username', FieldKind.text),
        FieldSpec('dbPassword', 'Password', FieldKind.password),
      ],
    ),
    EntryType.api: ItemTemplate(
      type: EntryType.api,
      label: 'API Credential',
      icon: Icons.vpn_key_rounded,
      color: Color(0xFFC62828),
      subtitleKeys: ['apiEndpoint'],
      fields: [
        FieldSpec('apiEndpoint', 'Endpoint / service', FieldKind.url),
        FieldSpec('apiKey', 'API key', FieldKind.password, mono: true),
        FieldSpec('apiSecret', 'API secret', FieldKind.password, mono: true),
        FieldSpec('apiExpires', 'Expires', FieldKind.date),
      ],
    ),
    EntryType.license: ItemTemplate(
      type: EntryType.license,
      label: 'Software License',
      icon: Icons.verified_rounded,
      color: Color(0xFF6A1B9A),
      subtitleKeys: ['vendor'],
      fields: [
        FieldSpec('vendor', 'Vendor / product', FieldKind.text),
        FieldSpec('licenseKey', 'License key', FieldKind.password, mono: true),
        FieldSpec('licensee', 'Licensed to', FieldKind.text),
        FieldSpec('licenseEmail', 'Registered email', FieldKind.email),
        FieldSpec('purchaseDate', 'Purchase date', FieldKind.date),
        FieldSpec('licenseExpires', 'Expires', FieldKind.date),
      ],
    ),
    EntryType.driver: ItemTemplate(
      type: EntryType.driver,
      label: "Driver's License",
      icon: Icons.directions_car_rounded,
      color: Color(0xFFEF6C00),
      subtitleKeys: ['licenseNumber'],
      fields: [
        FieldSpec('fullName', 'Full name', FieldKind.text),
        FieldSpec('licenseNumber', 'License number', FieldKind.text,
            secret: true),
        FieldSpec('dob', 'Date of birth', FieldKind.date),
        FieldSpec('issued', 'Issued', FieldKind.date),
        FieldSpec('expires', 'Expires', FieldKind.date),
        FieldSpec('issuer', 'State / country', FieldKind.text),
      ],
    ),
    EntryType.passport: ItemTemplate(
      type: EntryType.passport,
      label: 'Passport',
      icon: Icons.menu_book_rounded,
      color: Color(0xFF1565C0),
      subtitleKeys: ['country'],
      fields: [
        FieldSpec('fullName', 'Full name', FieldKind.text),
        FieldSpec('passportNumber', 'Passport number', FieldKind.text,
            secret: true),
        FieldSpec('country', 'Issuing country', FieldKind.text),
        FieldSpec('dob', 'Date of birth', FieldKind.date),
        FieldSpec('issued', 'Issued', FieldKind.date),
        FieldSpec('expires', 'Expires', FieldKind.date),
      ],
    ),
    EntryType.email: ItemTemplate(
      type: EntryType.email,
      label: 'Email Account',
      icon: Icons.email_rounded,
      color: Color(0xFFD81B60),
      subtitleKeys: ['emailAddress'],
      fields: [
        FieldSpec('emailAddress', 'Email address', FieldKind.email),
        FieldSpec('emailPassword', 'Password', FieldKind.password),
        FieldSpec('imapServer', 'Incoming (IMAP) server', FieldKind.url),
        FieldSpec('smtpServer', 'Outgoing (SMTP) server', FieldKind.url),
      ],
    ),
    EntryType.password: ItemTemplate(
      type: EntryType.password,
      label: 'Password',
      icon: Icons.password_rounded,
      color: Color(0xFF00897B),
      subtitleKeys: ['pwUsername'],
      fields: [
        FieldSpec('pwUsername', 'Username', FieldKind.text),
        FieldSpec('pwValue', 'Password', FieldKind.password),
      ],
    ),
    EntryType.document: ItemTemplate(
      type: EntryType.document,
      label: 'Document',
      icon: Icons.description_rounded,
      color: Color(0xFF3949AB),
      subtitleKeys: ['docType'],
      fields: [
        FieldSpec('docType', 'Document type', FieldKind.text),
        FieldSpec('docDate', 'Date', FieldKind.date),
      ],
    ),
    EntryType.crypto: ItemTemplate(
      type: EntryType.crypto,
      label: 'Crypto Wallet',
      icon: Icons.currency_bitcoin_rounded,
      color: Color(0xFFF57C00),
      subtitleKeys: ['walletName'],
      fields: [
        FieldSpec('walletName', 'Wallet name', FieldKind.text),
        FieldSpec('walletAddress', 'Wallet address', FieldKind.text,
            mono: true),
        FieldSpec('recoveryPhrase', 'Recovery phrase', FieldKind.password,
            secret: true, maxLines: 3),
        FieldSpec('walletPassword', 'Wallet password', FieldKind.password),
      ],
    ),
    EntryType.medical: ItemTemplate(
      type: EntryType.medical,
      label: 'Medical Record',
      icon: Icons.medical_services_rounded,
      color: Color(0xFFE53935),
      subtitleKeys: ['patient'],
      fields: [
        FieldSpec('patient', 'Patient', FieldKind.text),
        FieldSpec('provider', 'Doctor / provider', FieldKind.text),
        FieldSpec('insurer', 'Insurance company', FieldKind.text),
        FieldSpec('policyNo', 'Policy number', FieldKind.text),
        FieldSpec('bloodType', 'Blood type', FieldKind.text),
        FieldSpec('providerPhone', 'Provider phone', FieldKind.phone),
      ],
    ),
    EntryType.membership: ItemTemplate(
      type: EntryType.membership,
      label: 'Membership',
      icon: Icons.card_membership_rounded,
      color: Color(0xFF8E24AA),
      subtitleKeys: ['memberName'],
      fields: [
        FieldSpec('org', 'Organization', FieldKind.text),
        FieldSpec('memberName', 'Member name', FieldKind.text),
        FieldSpec('memberId', 'Member ID', FieldKind.text),
        FieldSpec('since', 'Member since', FieldKind.date),
        FieldSpec('memberExpires', 'Expiry date', FieldKind.date),
      ],
    ),
    EntryType.reward: ItemTemplate(
      type: EntryType.reward,
      label: 'Reward Program',
      icon: Icons.redeem_rounded,
      color: Color(0xFFC2185B),
      subtitleKeys: ['rewardCompany'],
      fields: [
        FieldSpec('rewardCompany', 'Company', FieldKind.text),
        FieldSpec('rewardNumber', 'Member number', FieldKind.text),
        FieldSpec('rewardPin', 'PIN', FieldKind.number, secret: true),
      ],
    ),
    EntryType.ssn: ItemTemplate(
      type: EntryType.ssn,
      label: 'Social Security Number',
      icon: Icons.badge_rounded,
      color: Color(0xFF546E7A),
      subtitleKeys: ['ssnName'],
      fields: [
        FieldSpec('ssnName', 'Name', FieldKind.text),
        FieldSpec('ssnNumber', 'Number', FieldKind.number, secret: true),
      ],
    ),
  };

  static ItemTemplate of(EntryType t) => _all[t]!;

  /// Order shown in the "New Item" picker.
  static const pickerOrder = [
    EntryType.login,
    EntryType.card,
    EntryType.identity,
    EntryType.bank,
    EntryType.wifi,
    EntryType.passkey,
    EntryType.ssh,
    EntryType.server,
    EntryType.database,
    EntryType.api,
    EntryType.license,
    EntryType.driver,
    EntryType.passport,
    EntryType.email,
    EntryType.password,
    EntryType.document,
    EntryType.crypto,
    EntryType.medical,
    EntryType.membership,
    EntryType.reward,
    EntryType.ssn,
  ];

  static const noteColor = Color(0xFFF9A825);
}
