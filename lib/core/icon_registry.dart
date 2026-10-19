import 'package:flutter/material.dart';

/// Material icons a category can use. The database stores only the name (software_categories.icon);
/// Flutter can't build an IconData from a string at runtime, so the allowed names are registered here.
const categoryIcons = <String, IconData>{
  'apps': Icons.apps,
  'work_outline': Icons.work_outline,
  'psychology_outlined': Icons.psychology_outlined,
  'shield_outlined': Icons.shield_outlined,
  'receipt_long_outlined': Icons.receipt_long_outlined,
  'code': Icons.code,
  'campaign_outlined': Icons.campaign_outlined,
  'groups_outlined': Icons.groups_outlined,
  'insights': Icons.insights,
  'cloud_outlined': Icons.cloud_outlined,
  'storage': Icons.storage,
  'dns_outlined': Icons.dns_outlined,
  'language': Icons.language,
  'mail_outline': Icons.mail_outline,
  'chat_bubble_outline': Icons.chat_bubble_outline,
  'shopping_cart_outlined': Icons.shopping_cart_outlined,
  'school_outlined': Icons.school_outlined,
  'health_and_safety_outlined': Icons.health_and_safety_outlined,
  'design_services_outlined': Icons.design_services_outlined,
  'settings_outlined': Icons.settings_outlined,
};

IconData categoryIcon(String? name) => categoryIcons[name] ?? Icons.apps;
