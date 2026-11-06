import 'dart:async';
import 'package:flutter/material.dart';
import '../accounts/account_controller.dart';
import '../accounts/account_profile.dart';
import '../accounts/account_api.dart';
import '../accounts/account_widgets.dart';
import '../notifications/notification_settings.dart';
import '../widgets.dart';
import 'home_controller.dart';
import 'social_models.dart';
import 'social_screens.dart';
import 'story_screens.dart';

class ActivityPage extends StatefulWidget {
  const ActivityPage({
    super.key,
    required this.accounts,
    this.initialActivityId,
  });
  final String? initialActivityId;
  final AccountController accounts;
  @override
  State<ActivityPage> createState() => _ActivityPageState();
}

class _ActivityPageState extends State<ActivityPage> {
  final scheduled = <String>{};
  bool opening = false;
  @override
  void initState() {
    super.initState();
    unawaited(widget.accounts.home.loadActivity());
    if (widget.initialActivityId != null) unawaited(openInitial());
  }

  Future<void> openInitial() async {
    try {
      final d = await widget.accounts.chatRequest(
        'GET',
        '/v1/activity/${widget.initialActivityId}',
      );
      if (mounted)
        await open(ActivityItem((d['item'] as Map).cast<String, dynamic>()));
    } on AccountFailure catch (f) {
      if (mounted) showNote(context, f.message);
    } catch (_) {
      if (mounted) showNote(context, 'تعذّر فتح الإشعار.');
    }
  }

  Future<void> open(ActivityItem item) async {
    if (opening) return;
    opening = true;
    try {
      await widget.accounts.home.markRead([item]);
      if (!mounted) return;
      if (item.kind == 'follow') {
        await Navigator.push(
          context,
          MaterialPageRoute<void>(
            builder: (_) => UserAccountPage(
              accounts: widget.accounts,
              initialUser: item.actor,
            ),
          ),
        );
      } else {
        final d = await widget.accounts.chatRequest(
          'GET',
          '/v1/posts/${item.targetId}',
        );
        if (!mounted) return;
        await Navigator.push(
          context,
          MaterialPageRoute<void>(
            builder: (_) => SocialPostPage(
              accounts: widget.accounts,
              showComments: item.kind == 'comment',
              initialPost: SocialPost.fromJson(
                d['post'] as Map<String, dynamic>,
              ),
            ),
          ),
        );
      }
    } on AccountFailure catch (e) {
      if (mounted) showNote(context, e.message);
    } finally {
      opening = false;
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: socialBackground,
    appBar: AppBar(
      backgroundColor: socialBackground,
      title: const Text('الإشعارات'),
      actions: [
        IconButton(
          tooltip: 'إعدادات الإشعارات',
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (_) =>
                  NotificationSettingsPage(controller: widget.accounts.push),
            ),
          ),
          icon: const Icon(Icons.settings_outlined),
        ),
      ],
    ),
    body: AnimatedBuilder(
      animation: widget.accounts.home,
      builder: (c, _) {
        final h = widget.accounts.home;
        final unread = h.activity
            .where((x) => !x.read && !scheduled.contains(x.id))
            .toList();
        if (unread.isNotEmpty) {
          scheduled.addAll(unread.map((x) => x.id));
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted)
              unawaited(
                h.markRead(unread).catchError((Object _) {
                  scheduled.removeAll(unread.map((x) => x.id));
                }),
              );
          });
        }
        return RefreshIndicator(
          onRefresh: h.loadActivity,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              for (final item in h.activity)
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  leading: StoryAvatar(
                    user: item.actor,
                    size: 48,
                    hasStory: item.actor.hasStory,
                    onTap: () =>
                        openStoryAvatar(context, widget.accounts, item.actor),
                  ),
                  title: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: '${item.actor.username} ',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        TextSpan(text: item.label),
                      ],
                    ),
                  ),
                  subtitle: Text(relativeTime(item.createdAt)),
                  trailing: Icon(
                    item.kind == 'follow'
                        ? Icons.person_add_outlined
                        : item.kind == 'like'
                        ? Icons.favorite_border
                        : Icons.mode_comment_outlined,
                    size: 21,
                  ),
                  onTap: () => open(item),
                ),
              if (h.loadingActivity) const LinearProgressIndicator(),
              if (h.activityError != null) ...[
                AccountErrorMessage(h.activityError!),
                TextButton(
                  onPressed: h.loadActivity,
                  child: const Text('إعادة المحاولة'),
                ),
              ],
              if (h.activity.isEmpty &&
                  !h.loadingActivity &&
                  h.activityError == null)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 90, horizontal: 24),
                  child: Column(
                    children: [
                      Icon(Icons.favorite_border_rounded, size: 48),
                      SizedBox(height: 15),
                      Text(
                        'راح تظهر هنا المتابعات والإعجابات والتعليقات الجديدة.',
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              if (h.nextActivity != null)
                TextButton(
                  onPressed: h.loadingActivity
                      ? null
                      : () => h.loadActivity(more: true),
                  child: const Text('إشعارات أقدم'),
                ),
            ],
          ),
        );
      },
    ),
  );
}
