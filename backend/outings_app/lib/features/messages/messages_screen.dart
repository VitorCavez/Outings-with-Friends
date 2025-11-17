// lib/features/messages/messages_screen.dart
import 'package:flutter/material.dart';
import '../../screens/messages/contacts_list_screen.dart';
import 'widgets/recent_chats_list.dart';
import 'package:outings_app/theme/app_theme.dart'; // for BrandColors

class MessagesScreen extends StatelessWidget {
  const MessagesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final brand = Theme.of(context).extension<BrandColors>()!;
    final tabTextStyle = Theme.of(context).textTheme.labelLarge;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Messages'),
          bottom: PreferredSize(
            // Give the bar enough vertical room; TabBar will size itself.
            preferredSize: const Size.fromHeight(64),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Container(
                // ❌ removed hardcoded height: 44 (this caused overflow)
                // ✅ ensure a comfortable minimum instead:
                constraints: const BoxConstraints(minHeight: 48),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: scheme.outlineVariant),
                ),
                child: TabBar(
                  padding: const EdgeInsets.all(4),
                  indicatorSize: TabBarIndicatorSize.tab,
                  labelPadding: EdgeInsets.zero,
                  dividerColor: Colors.transparent, // cleaner M3 look
                  indicator: BoxDecoration(
                    gradient: brand.primaryGradient,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  labelColor: scheme.onPrimary,
                  unselectedLabelColor: scheme.onSurfaceVariant,
                  labelStyle: tabTextStyle,
                  tabs: const [
                    Tab(icon: Icon(Icons.chat_bubble_outline), text: 'Chats'),
                    Tab(icon: Icon(Icons.contacts_outlined), text: 'Contacts'),
                  ],
                ),
              ),
            ),
          ),
        ),
        body: const TabBarView(
          children: [RecentChatsList(), ContactsListScreen()],
        ),
      ),
    );
  }
}
