import '../experience/share_code_page.dart';
import '../social/social_models.dart' show newRequestId;
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../accounts/account_controller.dart';
import '../roulette/live_controller.dart';
import 'csharp_asset_server.dart';
import 'game_controller.dart';
import 'game_invite_sheet.dart';
import 'game_models.dart';
import 'package:flutter/services.dart';

/// The app hosts the compiled Blazor UI; native controllers own authentication,
/// revision fencing, durable request IDs, retry and wallet updates.
class CSharpGamesPage extends StatefulWidget {
  const CSharpGamesPage({
    super.key,
    required this.accounts,
    this.visible = true,
    this.initialCode,
  });
  final AccountController accounts;
  final bool visible;
  final String? initialCode;
  @override
  State<CSharpGamesPage> createState() => _CSharpGamesPageState();
}

class _CSharpGamesPageState extends State<CSharpGamesPage>
    with WidgetsBindingObserver {
  late final GamesController games = GamesController(
    widget.accounts,
    visible: widget.visible,
    autoPoll: widget.accounts.realtimeEnabled,
  );
  LiveRouletteController? roulette;
  CSharpAssetServer? assets;
  WebViewController? web;
  Timer? clock;
  bool ready = false,
      disposed = false,
      sending = false,
      dirty = false,
      resumed = true,
      processing = false,
      wheelActive = false,
      started = false;
  String? failure, closedMatchId, lastStateFrame;
  bool get foreground => widget.visible && resumed && games.current;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    games.addListener(changed);
    if (widget.initialCode != null) unawaited(openInvitation());
    if (widget.visible) unawaited(start());
  }

  Future<void> openInvitation() async {
    await games.ready;
    if (!disposed && foreground) await games.join(widget.initialCode!);
  }

  Future<void> start() async {
    if (started || disposed || !widget.visible) return;
    started = true;
    try {
      final server = await CSharpAssetServer.start();
      if (disposed) {
        await server.close();
        return;
      }
      assets = server;
      final controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setBackgroundColor(const Color(0xFF0B121B))
        ..addJavaScriptChannel(
          'TomiHost',
          onMessageReceived: (message) => unawaited(receive(message.message)),
        )
        ..setNavigationDelegate(
          NavigationDelegate(
            onNavigationRequest: (request) =>
                server.allows(Uri.parse(request.url))
                ? NavigationDecision.navigate
                : NavigationDecision.prevent,
            onWebResourceError: (error) {
              if (error.isForMainFrame == true && mounted)
                setState(
                  () => failure = 'تعذّر تشغيل واجهة C#. أعد فتح قسم الألعاب.',
                );
            },
          ),
        );
      web = controller;
      await controller.loadRequest(server.entry);
      if (!mounted) return;
      clock = Timer.periodic(const Duration(milliseconds: 250), (_) {
        if (foreground && roulette != null && wheelActive) {
          unawaited(send({'clock': true, 'rouletteNow': roulette!.serverNow}));
        }
      });
      setState(() {});
    } catch (_) {
      if (mounted)
        setState(
          () => failure =
              'ملفات ألعاب C# غير جاهزة. حدّث التطبيق أو أعد فتح القسم.',
        );
    }
  }

  void changed() {
    if (!disposed) {
      dirty = true;
      unawaited(push());
    }
  }

  Map<String, dynamic> snapshot({String? ack}) => {
    'current': games.current,
    'canAct': games.canAct,
    'busy': games.busy,
    'pending': games.pending != null,
    'error': games.error,
    'summary': games.summary,
    'match': games.match?['id'] == closedMatchId ? null : games.match,
    'serverNow': games.serverNow,
    'roulette': roulette?.state,
    'rouletteNow': roulette?.serverNow,
    'canBet': roulette?.canBet ?? false,
    'rouletteBusy': roulette?.busy ?? false,
    'roulettePending': roulette?.pending != null,
    'rouletteError': roulette?.error,
    'denomination': roulette?.denomination ?? 20,
    if (ack != null) 'ack': ack,
  };
  Future<void> push({String? ack}) async {
    if (disposed || !ready || web == null) return;
    // Acknowledgements must be sent even if another state update is in flight.
    if (ack != null) {
      await send(snapshot(ack: ack));
      return;
    }
    if (sending) return;
    sending = true;
    try {
      while (dirty && !disposed && ready) {
        dirty = false;
        await send(snapshot());
      }
    } finally {
      sending = false;
    }
  }

  Future<void> send(Map<String, dynamic> value) async {
    try {
      if (value['clock'] != true) {
        final comparable = Map<String, dynamic>.from(value)
          ..remove('ack')
          ..remove('serverNow')
          ..remove('rouletteNow');
        final frame = jsonEncode(comparable);
        if (value['ack'] == null && frame == lastStateFrame) return;
        lastStateFrame = frame;
      }
      await web?.runJavaScript(
        'window.tomiNative.receive(${jsonEncode(value)});',
      );
    } catch (_) {
      /* A disposed or navigating WebView cannot accept a state frame. */
    }
  }

  Future<void> receive(String raw) async {
    if (disposed || raw.length > 16384) return;
    Map<String, dynamic> message;
    try {
      message = (jsonDecode(raw) as Map).cast<String, dynamic>();
    } catch (_) {
      return;
    }
    final command = message['command'];
    if (command == 'ready') {
      ready = true;
      changed();
      return;
    }
    final id = message['id'];
    if (id is! String || !RegExp(r'^[a-f0-9]{32}$').hasMatch(id)) return;
    if (processing || !foreground) {
      await push(ack: id);
      return;
    }
    processing = true;
    try {
      final args = message['args'] is Map
          ? (message['args'] as Map).cast<String, dynamic>()
          : <String, dynamic>{};
      if (command == 'select') {
        wheelActive = args['kind'] == 'coins';
        if (wheelActive) {
          roulette ??= LiveRouletteController(widget.accounts, null)
            ..addListener(changed);
          roulette!.lifecycle(foreground);
        } else {
          roulette?.lifecycle(false);
        }
      } else if (command == 'copyCode' && games.match?['status'] == 'waiting') {
        await Clipboard.setData(
          ClipboardData(text: games.match!['code'] as String),
        );
      } else if (command == 'shareCode' &&
          games.match?['status'] == 'waiting') {
        await Navigator.push(
          context,
          MaterialPageRoute<void>(
            builder: (_) => ShareCodePage(
              url: 'tomi://game/${games.match!['code']}',
              title: 'دعوة لطاولة اللعبة',
            ),
          ),
        );
      } else if (command == 'invite' && games.match?['status'] == 'waiting') {
        final matchId = games.match!['id'],
            code = games.match!['code'],
            kind = games.match!['kind'];
        final uid = await showModalBottomSheet<String>(
          context: context,
          isScrollControlled: true,
          showDragHandle: true,
          builder: (_) => GameInviteSheet(accounts: widget.accounts),
        );
        if (uid != null &&
            foreground &&
            games.match?['id'] == matchId &&
            games.match?['status'] == 'waiting') {
          final owner = widget.accounts.draftOwnerId!,
              revision = widget.accounts.sessionRevision,
              key = 'native-game-invite-$matchId-$uid';
          bool valid() =>
              mounted &&
              widget.accounts.draftOwnerId == owner &&
              widget.accounts.sessionRevision == revision;
          final saved =
              await widget.accounts.draftStore.read(owner, key) ??
              {'requestId': newRequestId()};
          if (!await widget.accounts.draftStore.write(
            owner,
            key,
            saved,
            valid: valid,
          ))
            return;
          await widget.accounts.chatRequest(
            'POST',
            '/v1/me/invitations',
            body: {
              'requestId': saved['requestId'],
              'recipientId': uid,
              'kind': 'game',
              'targetId': matchId,
            },
          );
          if (!valid()) return;
          final conversation = await widget.accounts.chats.open(uid);
          final thread = widget.accounts.chats.thread(conversation);
          await thread.restored;
          if (foreground) {
            thread.enqueue(
              'دعوة للعب ${gameName(kind as String)} • كود الغرفة: $code\nافتح قسم الألعاب ثم انضم بكود الطاولة.',
              null,
              requestId: saved['requestId'] as String,
            );
            if (!await thread.persist())
              throw StateError('دعوة محفوظة تنتظر إعادة المحاولة');
            await widget.accounts.draftStore.write(
              owner,
              key,
              null,
              valid: valid,
            );
            if (mounted)
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('الدعوة قيد الإرسال في المحادثات'),
                ),
              );
          }
        }
      } else if ((command == 'search' || command == 'cancelSearch') &&
          const [
            'uno',
            'snakes',
            'jackaroo',
            'camel',
            'wheel',
          ].contains(args['kind'])) {
        await games.searchGame(
          args['kind'] as String,
          cancel: command == 'cancelSearch',
        );
      } else if (command == 'create' &&
          const [
            'uno',
            'snakes',
            'jackaroo',
            'camel',
            'wheel',
          ].contains(args['kind']) &&
          const ['practice', 'friends'].contains(args['mode'])) {
        await games.create(args['kind'] as String, args['mode'] as String);
      } else if (command == 'join' &&
          args['code'] is String &&
          RegExp(r'^[a-fA-F0-9]{8}$').hasMatch(args['code'] as String)) {
        await games.join(args['code'] as String);
      } else if (command == 'open' &&
          args['id'] is String &&
          games.activeMatches.any((m) => m['id'] == args['id'])) {
        closedMatchId = null;
        await games.open(args['id'] as String);
      } else if (command == 'recover') {
        await games.retryPending();
      } else if (command == 'closeTable') {
        // Closing the view never leaves a match or mutates its result.
        closedMatchId = games.match?['id'] as String?;
        await games.load(forceSummary: true);
      } else if (command == 'action' || command == 'choice') {
        if (message['matchId'] != games.match?['id'] ||
            message['revision'] != games.match?['revision']) {
          games.error = 'تغيّرت الطاولة؛ اختار الحركة من الحالة الجديدة.';
          await games.load();
        } else if (command == 'choice' && args['choice'] is String) {
          final choices = games.match?['choices'] as List? ?? [];
          if (choices.any((c) => c['id'] == args['choice']))
            await games.choose(
              args['choice'] as String,
              message['revision'] as int,
            );
        } else if (command == 'action') {
          final type = args['type'];
          if (const [
            'start',
            'leave',
            'draw',
            'pass',
            'roll',
            'spin',
          ].contains(type))
            await games.act(type as String);
          else if (type == 'play' && args['cardId'] is String) {
            final allowed = games.match?['playableCardIds'] as List? ?? [];
            if (allowed.contains(args['cardId']) &&
                (args['color'] == null ||
                    const [
                      'red',
                      'green',
                      'blue',
                      'yellow',
                    ].contains(args['color'])))
              await games.act('play', {
                'cardId': args['cardId'],
                if (args['color'] != null) 'color': args['color'],
                'uno': args['uno'] == true,
              });
          }
        }
      } else if (roulette != null && wheelActive) {
        final r = roulette!;
        if (command == 'denomination' && args['value'] is int)
          r.choose(args['value'] as int);
        else if (command == 'rouletteRecover')
          await r.submit();
        else if (message['roundId'] == r.state?['roundId']) {
          if (command == 'bet' && args['slot'] is int)
            await r.bet(args['slot'] as int);
          else if (command == 'repeatBet')
            await r.repeat();
        }
      }
    } catch (_) {
      if (games.current)
        games.error = 'تعذّر إكمال الحركة؛ تحقق من حالة الطاولة.';
    } finally {
      processing = false;
      await push(ack: id);
    }
  }

  @override
  void didUpdateWidget(covariant CSharpGamesPage old) {
    super.didUpdateWidget(old);
    games.setVisible(widget.visible);
    roulette?.lifecycle(foreground && wheelActive);
    if (widget.visible) {
      unawaited(start());
      changed();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    resumed = state == AppLifecycleState.resumed;
    roulette?.lifecycle(foreground && wheelActive);
    if (resumed) changed();
  }

  @override
  void dispose() {
    disposed = true;
    ready = false;
    clock?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    games.removeListener(changed);
    games.dispose();
    roulette?.removeListener(changed);
    roulette?.dispose();
    unawaited(assets?.close() ?? Future<void>.value());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // IndexedStack builds hidden tabs too. Do not animate or initialize a
    // WebView until the player actually opens games.
    if (!widget.visible && web == null) return const SizedBox.shrink();
    if (failure != null)
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(failure!, textAlign: TextAlign.center),
        ),
      );
    if (web == null) return const Center(child: CircularProgressIndicator());
    return WebViewWidget(controller: web!);
  }
}

bool get supportsCSharpGames =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
