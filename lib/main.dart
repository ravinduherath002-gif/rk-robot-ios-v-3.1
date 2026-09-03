
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'wifi_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  runApp(const RKRobotApp());
}

enum Profile { eco, normal, sport }

class RKRobotApp extends StatelessWidget {
  const RKRobotApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.light,
        useMaterial3: true,
        fontFamily: 'Roboto',
      ),
      home: const RKDashboard(),
    );
  }
}

class RKDashboard extends StatefulWidget {
  const RKDashboard({super.key});

  @override
  State<RKDashboard> createState() => _RKDashboardState();
}

class _RKDashboardState extends State<RKDashboard> {
  static const ip = '192.168.4.1';
  static const port = 8080;

  static const blue = Color(0xFF119CE5);
  static const blue2 = Color(0xFF59C8FF);
  static const green = Color(0xFF2DBD67);
  static const red = Color(0xFFE83343);
  static const orange = Color(0xFFF39B20);
  static const yellow = Color(0xFFFFC93C);
  static const purple = Color(0xFF8A55E8);
  static const ink = Color(0xFF142033);
  static const muted = Color(0xFF657387);
  static const darkPanel = Color(0xFF071019);
  static const darkPanel2 = Color(0xFF111C27);
  static const silver = Color(0xFFE8EDF3);
  static const silver2 = Color(0xFFF8FAFC);

  final wifi = WifiService();
  StreamSubscription<bool>? connectionSub;
  Timer? moveTimer;
  Timer? uptimeTimer;
  Timer? danceTimer;

  bool connected = false;
  bool connecting = false;

  bool front = false;
  bool rear = false;
  bool flash = false;
  bool turbo = false;
  bool horn = false;
  bool siren = false;
  bool dance = false;
  bool safety = true;
  bool autoMode = false;
  bool leftSignal = false;
  bool rightSignal = false;
  bool hazard = false;

  bool forwardHeld = false;
  bool backwardHeld = false;
  bool leftHeld = false;
  bool rightHeld = false;

  double speed = 179;
  Profile profile = Profile.normal;
  String lastCommand = 'S';
  String driveCommand = 'S';
  int uptimeSeconds = 0;

  @override
  void initState() {
    super.initState();

    connectionSub = wifi.connectionStream.listen((value) {
      if (!mounted) return;
      setState(() {
        connected = value;
        connecting = false;
        if (!value) {
          _resetDriveState();
          turbo = false;
          horn = false;
          autoMode = false;
          siren = false;
        }
      });
    });

    uptimeTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => uptimeSeconds++);
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      connect(showMessage: false);
    });
  }

  @override
  void dispose() {
    moveTimer?.cancel();
    danceTimer?.cancel();
    uptimeTimer?.cancel();
    connectionSub?.cancel();
    wifi.dispose();
    super.dispose();
  }

  int get percent => ((speed / 255.0) * 100).round();

  String get profileName => switch (profile) {
        Profile.eco => 'ECO',
        Profile.normal => 'NORMAL',
        Profile.sport => 'SPORT',
      };

  String get motionName => switch (driveCommand) {
        'F' => 'FORWARD',
        'B' => 'BACKWARD',
        'L' => 'LEFT',
        'R' => 'RIGHT',
        'FL' => 'FWD LEFT',
        'FR' => 'FWD RIGHT',
        'BL' => 'REV LEFT',
        'BR' => 'REV RIGHT',
        _ => autoMode ? 'AUTO ACTIVE' : 'STOPPED',
      };

  String get uptimeText {
    final h = uptimeSeconds ~/ 3600;
    final m = (uptimeSeconds % 3600) ~/ 60;
    final s = uptimeSeconds % 60;
    return '${h.toString().padLeft(2, '0')}:'
        '${m.toString().padLeft(2, '0')}:'
        '${s.toString().padLeft(2, '0')}';
  }

  Future<void> connect({bool showMessage = true}) async {
    if (connected || connecting) return;

    setState(() => connecting = true);
    final ok = await wifi.connect(ip, port);

    if (!mounted) return;

    setState(() {
      connected = ok;
      connecting = false;
      if (ok) lastCommand = 'LINK';
    });

    if (ok) {
      wifi.send('V${speed.round()}');
      wifi.send(safety ? 'M' : 'm');
      _sendProfile();
      if (showMessage) _toast('RK ROBOT connected');
    } else if (showMessage) {
      _toast('Connect iPhone to RK_ROBOT Wi-Fi');
    }
  }

  Future<void> disconnect() async {
    moveTimer?.cancel();
    danceTimer?.cancel();

    if (connected) {
      for (final command in [
        'a', 'S', 'h', 't', 'z', 'd', 'y', 'q', 'w'
      ]) {
        wifi.send(command);
      }
    }

    await wifi.disconnect();

    if (!mounted) return;
    setState(() {
      connected = false;
      connecting = false;
      _resetDriveState();
      autoMode = false;
      turbo = false;
      horn = false;
      siren = false;
      dance = false;
      hazard = false;
      leftSignal = false;
      rightSignal = false;
      lastCommand = 'OFF';
    });
  }

  void _toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(text),
          duration: const Duration(milliseconds: 850),
        ),
      );
  }

  bool send(String command, {bool warn = true}) {
    if (!connected) {
      if (warn) _toast('Robot not connected');
      return false;
    }

    final ok = wifi.send(command);
    if (mounted) setState(() => lastCommand = command);
    return ok;
  }

  void _resetDriveState() {
    moveTimer?.cancel();
    moveTimer = null;
    forwardHeld = false;
    backwardHeld = false;
    leftHeld = false;
    rightHeld = false;
    driveCommand = 'S';
  }

  String _desiredDriveCommand() {
    if (forwardHeld) {
      if (leftHeld && !rightHeld) return 'FL';
      if (rightHeld && !leftHeld) return 'FR';
      return 'F';
    }

    if (backwardHeld) {
      if (leftHeld && !rightHeld) return 'BL';
      if (rightHeld && !leftHeld) return 'BR';
      return 'B';
    }

    if (leftHeld && !rightHeld) return 'L';
    if (rightHeld && !leftHeld) return 'R';
    return 'S';
  }

  void _refreshDrive() {
    if (autoMode) return;

    final next = _desiredDriveCommand();
    if (next == driveCommand && moveTimer != null) return;

    moveTimer?.cancel();
    moveTimer = null;

    setState(() => driveCommand = next);
    send(next, warn: false);

    if (next != 'S') {
      moveTimer = Timer.periodic(
        const Duration(milliseconds: 120),
        (_) => send(next, warn: false),
      );
    }
  }

  void _setHold(String control, bool held) {
    if (autoMode) return;

    setState(() {
      switch (control) {
        case 'F':
          forwardHeld = held;
          if (held) backwardHeld = false;
          break;
        case 'B':
          backwardHeld = held;
          if (held) forwardHeld = false;
          break;
        case 'L':
          leftHeld = held;
          if (held) rightHeld = false;
          break;
        case 'R':
          rightHeld = held;
          if (held) leftHeld = false;
          break;
      }
    });

    _refreshDrive();
  }

  void _applyProfile(Profile next) {
    final newSpeed = switch (next) {
      Profile.eco => 102.0,
      Profile.normal => 179.0,
      Profile.sport => 217.0,
    };

    setState(() {
      profile = next;
      speed = newSpeed;
    });

    _sendProfile();
    send('V${newSpeed.round()}', warn: false);
  }

  void _sendProfile() {
    send(
      switch (profile) {
        Profile.eco => 'E',
        Profile.normal => 'N',
        Profile.sport => 'P',
      },
      warn: false,
    );
  }

  void _toggleAuto() {
    moveTimer?.cancel();
    moveTimer = null;

    final enable = !autoMode;

    setState(() {
      autoMode = enable;
      _resetDriveState();
    });

    if (enable) {
      send('S', warn: false);
      send('A', warn: false);
    } else {
      send('a', warn: false);
      send('S', warn: false);
    }
  }

  void _toggleDance() {
    if (!dance) {
      setState(() => dance = true);
      send('D', warn: false);

      danceTimer?.cancel();
      danceTimer = Timer(const Duration(seconds: 30), () {
        if (!mounted) return;
        send('d', warn: false);
        setState(() => dance = false);
      });
    } else {
      danceTimer?.cancel();
      send('d', warn: false);
      setState(() => dance = false);
    }
  }

  void _toggleLeftSignal() {
    final next = !leftSignal;
    setState(() {
      leftSignal = next;
      if (next) {
        rightSignal = false;
        hazard = false;
      }
    });

    send(next ? 'Q' : 'q', warn: false);
    if (next) {
      send('w', warn: false);
      send('y', warn: false);
    }
  }

  void _toggleRightSignal() {
    final next = !rightSignal;
    setState(() {
      rightSignal = next;
      if (next) {
        leftSignal = false;
        hazard = false;
      }
    });

    send(next ? 'W' : 'w', warn: false);
    if (next) {
      send('q', warn: false);
      send('y', warn: false);
    }
  }

  void _toggleHazard() {
    final next = !hazard;
    setState(() {
      hazard = next;
      if (next) {
        leftSignal = false;
        rightSignal = false;
      }
    });

    send(next ? 'Y' : 'y', warn: false);
    if (next) {
      send('q', warn: false);
      send('w', warn: false);
    }
  }

  BoxDecoration silverBox({double radius = 18, bool dark = false}) {
    return BoxDecoration(
      gradient: dark
          ? const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF17222E), Color(0xFF071019)],
            )
          : const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFFDFEFF), Color(0xFFDDE4EC)],
            ),
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(
        color: dark ? const Color(0xFF425368) : const Color(0xFFAFBAC7),
        width: 1.3,
      ),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(dark ? .28 : .16),
          blurRadius: 10,
          offset: const Offset(0, 4),
        ),
        if (!dark)
          const BoxShadow(
            color: Colors.white,
            blurRadius: 3,
            offset: Offset(-1, -1),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: silver,
      body: SafeArea(
        child: Center(
          child: FittedBox(
            fit: BoxFit.contain,
            child: SizedBox(
              width: 1366,
              height: 720,
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  children: [
                    _topBar(),
                    const SizedBox(height: 8),
                    Expanded(
                      child: Row(
                        children: [
                          SizedBox(width: 340, child: _leftColumn()),
                          const SizedBox(width: 8),
                          Expanded(child: _centerColumn()),
                          const SizedBox(width: 8),
                          SizedBox(width: 330, child: _rightColumn()),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    _footer(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _topBar() {
    final linkColor = connected
        ? blue
        : connecting
            ? orange
            : red;

    return SizedBox(
      height: 68,
      child: Row(
        children: [
          InkWell(
            onTap: connected ? disconnect : () => connect(),
            borderRadius: BorderRadius.circular(18),
            child: Container(
              width: 305,
              padding: const EdgeInsets.symmetric(horizontal: 17),
              decoration: silverBox(),
              child: Row(
                children: [
                  Icon(
                    connected ? Icons.wifi_rounded : Icons.wifi_off_rounded,
                    color: linkColor,
                    size: 30,
                  ),
                  const SizedBox(width: 11),
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        connected
                            ? 'CONNECTED'
                            : connecting
                                ? 'CONNECTING...'
                                : 'TAP TO CONNECT',
                        style: TextStyle(
                          color: connected ? ink : linkColor,
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        '192.168.4.1:8080',
                        style: TextStyle(
                          color: ink,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Container(
              decoration: silverBox(dark: true),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    'RK ROBOT',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 29,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2.0,
                    ),
                  ),
                  Text(
                    'PRO ROBOT CONTROL  •  $profileName',
                    style: const TextStyle(
                      color: blue2,
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            width: 170,
            decoration: silverBox(dark: true),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.schedule_rounded, color: blue2, size: 25),
                const SizedBox(width: 8),
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text(
                      'UPTIME',
                      style: TextStyle(
                        color: Colors.white54,
                        fontSize: 9,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      uptimeText,
                      style: const TextStyle(
                        color: blue2,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          InkWell(
            onTap: _showSettings,
            borderRadius: BorderRadius.circular(18),
            child: Container(
              width: 150,
              decoration: silverBox(),
              alignment: Alignment.center,
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.settings_rounded, color: ink),
                  SizedBox(width: 8),
                  Text(
                    'SETTINGS',
                    style: TextStyle(
                      color: ink,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _leftColumn() {
    return Column(
      children: [
        SizedBox(height: 125, child: _driveModePanel()),
        const SizedBox(height: 8),
        SizedBox(height: 150, child: _speedPanel()),
        const SizedBox(height: 8),
        Expanded(child: _steeringPanel()),
      ],
    );
  }

  Widget _driveModePanel() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: silverBox(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionTitle(
            icon: Icons.speed_rounded,
            title: 'DRIVE MODE',
          ),
          const SizedBox(height: 9),
          Expanded(
            child: Column(
              children: [
                Expanded(
                  child: Row(
                    children: [
                _profileTile(Profile.eco, 'ECO', Icons.eco_rounded),
                const SizedBox(width: 8),
                _profileTile(Profile.normal, 'NORMAL', Icons.directions_car_rounded),
                const SizedBox(width: 8),
                _profileTile(Profile.sport, 'SPORT', Icons.rocket_launch_rounded),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _profileTile(Profile p, String label, IconData icon) {
    final active = profile == p;
    final color = p == Profile.eco
        ? green
        : p == Profile.normal
            ? blue
            : orange;

    return Expanded(
      child: InkWell(
        onTap: autoMode ? null : () => _applyProfile(p),
        borderRadius: BorderRadius.circular(13),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          decoration: BoxDecoration(
            color: active ? darkPanel : silver2,
            borderRadius: BorderRadius.circular(13),
            border: Border.all(
              color: active ? color : const Color(0xFFC2CBD6),
              width: active ? 2 : 1,
            ),
            boxShadow: active
                ? [
                    BoxShadow(
                      color: color.withOpacity(.35),
                      blurRadius: 12,
                    ),
                  ]
                : null,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: active ? color : ink, size: 26),
              const SizedBox(height: 5),
              Text(
                label,
                style: TextStyle(
                  color: active ? Colors.white : ink,
                  fontWeight: FontWeight.w900,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _speedPanel() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: silverBox(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionTitle(
            icon: Icons.tune_rounded,
            title: 'SPEED / PWM',
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Text(
                '${speed.round()}',
                style: const TextStyle(
                  color: Color(0xFF0C64A0),
                  fontSize: 35,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const Text(
                ' / 255',
                style: TextStyle(
                  color: ink,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Spacer(),
              Text(
                '$percent%',
                style: const TextStyle(
                  color: ink,
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: blue,
              inactiveTrackColor: const Color(0xFF18202B),
              thumbColor: const Color(0xFFF5F7FA),
              overlayColor: blue.withOpacity(.12),
              trackHeight: 5,
            ),
            child: Slider(
              min: 0,
              max: 255,
              divisions: 255,
              value: speed,
              onChanged: autoMode
                  ? null
                  : (value) {
                      setState(() => speed = value);
                      send('V${value.round()}', warn: false);
                    },
            ),
          ),
        ],
      ),
    );
  }

  Widget _steeringPanel() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: silverBox(dark: true),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionTitle(
            icon: Icons.open_with_rounded,
            title: 'STEERING • LEFT THUMB',
            dark: true,
          ),
          const SizedBox(height: 11),
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child: _holdDriveButton(
                    label: 'LEFT',
                    icon: Icons.chevron_left_rounded,
                    accent: blue2,
                    active: leftHeld,
                    onDown: () => _setHold('L', true),
                    onUp: () => _setHold('L', false),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _holdDriveButton(
                    label: 'RIGHT',
                    icon: Icons.chevron_right_rounded,
                    accent: blue2,
                    active: rightHeld,
                    onDown: () => _setHold('R', true),
                    onUp: () => _setHold('R', false),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 7),
          Text(
            autoMode
                ? 'AUTO MODE OWNS STEERING'
                : 'HOLD LEFT / RIGHT • RELEASE = CENTER',
            style: TextStyle(
              color: autoMode ? orange : Colors.white38,
              fontSize: 9,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _centerColumn() {
    return Column(
      children: [
        Expanded(child: _controlCore()),
        const SizedBox(height: 8),
        SizedBox(height: 95, child: _soundSpecial()),
        const SizedBox(height: 8),
        SizedBox(height: 105, child: _robotStatus()),
      ],
    );
  }

  Widget _controlCore() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: silverBox(dark: true),
      child: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _GridPainter(),
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            child: _darkChip(
              connected ? 'ONLINE' : 'OFFLINE',
              connected ? green : red,
              connected ? Icons.wifi_rounded : Icons.wifi_off_rounded,
            ),
          ),
          Positioned(
            top: 0,
            right: 0,
            child: _darkChip(
              safety ? 'SAFETY ON' : 'SAFETY OFF',
              safety ? green : red,
              Icons.shield_rounded,
            ),
          ),
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 118,
                  height: 118,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: blue.withOpacity(.5), width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: blue.withOpacity(.15),
                        blurRadius: 28,
                        spreadRadius: 7,
                      ),
                    ],
                  ),
                  child: Icon(
                    autoMode
                        ? Icons.smart_toy_rounded
                        : Icons.precision_manufacturing_rounded,
                    color: autoMode ? green : blue2,
                    size: 63,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  autoMode ? 'AUTONOMOUS NAVIGATION' : 'ROBOT CONTROL CORE',
                  style: TextStyle(
                    color: autoMode ? green : Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                    letterSpacing: 1.0,
                  ),
                ),
                const SizedBox(height: 5),
                const Text(
                  'NO CAMERA • CONTROL SYSTEM ACTIVE',
                  style: TextStyle(
                    color: Colors.white38,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: .8,
                  ),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: [
                    _coreTag('MOTION', motionName, blue2),
                    _coreTag('PWM', '${speed.round()}', blue2),
                    _coreTag('PROFILE', profileName, blue2),
                    _coreTag('HEARTBEAT', connected ? 'ON' : 'OFF',
                        connected ? green : red),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _darkChip(String label, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(.09),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(.5)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: turboStyle ? 12 : (big ? 10 : 9),
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _coreTag(String title, String value, Color color) {
    return Container(
      width: 112,
      height: 49,
      decoration: BoxDecoration(
        color: const Color(0xFF101B26),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: const Color(0xFF34485B)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white38,
              fontSize: 7,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _soundSpecial() {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: silverBox(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionTitle(icon: Icons.graphic_eq_rounded, title: 'SOUND & SPECIAL'),
          const SizedBox(height: 7),
          Expanded(
            child: Column(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Expanded(
                        child: Listener(
                          onPointerDown: (_) { setState(() => horn = true); send('H', warn: false); },
                          onPointerUp: (_) { setState(() => horn = false); send('h', warn: false); },
                          onPointerCancel: (_) { setState(() => horn = false); send('h', warn: false); },
                          child: _smallAction('HORN', Icons.campaign_rounded, purple, horn, big: true),
                        ),
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: _actionButton('SIREN', Icons.emergency_rounded, red, siren, () {
                          setState(() => siren = !siren);
                          send(siren ? 'Z' : 'z', warn: false);
                        }, big: true),
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Listener(
                          onPointerDown: (_) { setState(() => turbo = true); send('T', warn: false); },
                          onPointerUp: (_) { setState(() => turbo = false); send('t', warn: false); },
                          onPointerCancel: (_) { setState(() => turbo = false); send('t', warn: false); },
                          child: _smallAction('TURBO', Icons.bolt_rounded, orange, turbo, big: true, turboStyle: true),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 7),
                Expanded(
                  child: Row(
                    children: [
                      _actionButton('SAFETY', Icons.shield_rounded, green, safety, () {
                        setState(() => safety = !safety); send(safety ? 'M' : 'm', warn: false);
                      }, big: true),
                      const SizedBox(width: 7),
                      _actionButton('AUTO', Icons.smart_toy_rounded, blue, autoMode, _toggleAuto, big: true),
                      const SizedBox(width: 7),
                      _actionButton('DANCE', Icons.music_note_rounded, purple, dance, _toggleDance, big: true),
                      const SizedBox(width: 7),
                      _actionButton('FLASH', Icons.flash_on_rounded, orange, flash, () {
                        setState(() => flash = !flash); send(flash ? 'J' : 'j', warn: false);
                      }, big: true),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _robotStatus() {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: silverBox(dark: true),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionTitle(
            icon: Icons.monitor_heart_outlined,
            title: 'ROBOT STATUS',
            dark: true,
          ),
          const SizedBox(height: 7),
          Expanded(
            child: Row(
              children: [
                _statusCard(
                  'MOTION',
                  motionName,
                  Icons.directions_car_rounded,
                  blue2,
                ),
                const SizedBox(width: 8),
                _statusCard(
                  'LAST CMD',
                  lastCommand,
                  Icons.terminal_rounded,
                  yellow,
                ),
                const SizedBox(width: 8),
                _statusCard(
                  'HEARTBEAT',
                  connected ? 'ON' : 'OFF',
                  Icons.favorite_border_rounded,
                  connected ? green : red,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusCard(
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
    return Expanded(
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF0C1721),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF34485B)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Row(
          children: [
            Icon(icon, color: color, size: 27),
            const SizedBox(width: 9),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white38,
                    fontSize: 8,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                SizedBox(
                  width: 105,
                  child: Text(
                    value,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: color,
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _rightColumn() {
    return Column(
      children: [
        SizedBox(height: 260, child: _lightsSignals()),
        const SizedBox(height: 8),
        Expanded(child: _throttlePanel()),
      ],
    );
  }

  Widget _lightsSignals() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: silverBox(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionTitle(
            icon: Icons.lightbulb_rounded,
            title: 'LIGHTS & SIGNALS',
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _actionButton(
                'FRONT',
                Icons.lightbulb_rounded,
                blue,
                front,
                () {
                  setState(() => front = !front);
                  send(front ? 'I' : 'i', warn: false);
                },
              ),
              const SizedBox(width: 8),
              _actionButton(
                'REAR',
                Icons.highlight_rounded,
                red,
                rear,
                () {
                  setState(() => rear = !rear);
                  send(rear ? 'K' : 'k', warn: false);
                },
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _actionButton(
                'LEFT SIGNAL',
                Icons.turn_left_rounded,
                orange,
                leftSignal,
                _toggleLeftSignal,
              ),
              const SizedBox(width: 8),
              _actionButton(
                'RIGHT SIGNAL',
                Icons.turn_right_rounded,
                orange,
                rightSignal,
                _toggleRightSignal,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Expanded(
            child: InkWell(
              onTap: _toggleHazard,
              borderRadius: BorderRadius.circular(14),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                decoration: BoxDecoration(
                  color: hazard ? red.withOpacity(.12) : silver2,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: hazard ? red : const Color(0xFFBFC8D3),
                    width: hazard ? 2 : 1,
                  ),
                  boxShadow: hazard
                      ? [
                          BoxShadow(
                            color: red.withOpacity(.18),
                            blurRadius: 12,
                          ),
                        ]
                      : null,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      color: hazard ? red : ink,
                      size: 27,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'DOUBLE SIGNAL',
                      style: TextStyle(
                        color: hazard ? red : ink,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _throttlePanel() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: silverBox(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionTitle(
            icon: Icons.speed_rounded,
            title: 'THROTTLE • RIGHT THUMB',
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Column(
              children: [
                Expanded(
                  child: _holdThrottleButton(
                    'FORWARD',
                    Icons.keyboard_arrow_up_rounded,
                    blue,
                    forwardHeld,
                    () => _setHold('F', true),
                    () => _setHold('F', false),
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  height: 50,
                  decoration: BoxDecoration(
                    color: darkPanel,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFF647180)),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    autoMode ? 'AUTO CONTROL' : 'RELEASE = STOP',
                    style: TextStyle(
                      color: autoMode ? green : muted,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: _holdThrottleButton(
                    'BACKWARD',
                    Icons.keyboard_arrow_down_rounded,
                    blue,
                    backwardHeld,
                    () => _setHold('B', true),
                    () => _setHold('B', false),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _holdThrottleButton(
    String label,
    IconData icon,
    Color color,
    bool active,
    VoidCallback onDown,
    VoidCallback onUp,
  ) {
    return Listener(
      onPointerDown: autoMode ? null : (_) => onDown(),
      onPointerUp: autoMode ? null : (_) => onUp(),
      onPointerCancel: autoMode ? null : (_) => onUp(),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        decoration: BoxDecoration(
          color: active ? darkPanel2 : darkPanel,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: active ? color : const Color(0xFF586777),
            width: active ? 2 : 1,
          ),
          boxShadow: active
              ? [
                  BoxShadow(
                    color: color.withOpacity(.28),
                    blurRadius: 17,
                  ),
                ]
              : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color: autoMode ? Colors.white24 : color,
              size: 42,
            ),
            Text(
              label,
              style: TextStyle(
                color: autoMode ? Colors.white24 : color,
                fontWeight: FontWeight.w900,
                fontSize: 15,
              ),
            ),
            const Text(
              'HOLD',
              style: TextStyle(
                color: Colors.white38,
                fontSize: 8,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _holdDriveButton({
    required String label,
    required IconData icon,
    required Color accent,
    required bool active,
    required VoidCallback onDown,
    required VoidCallback onUp,
  }) {
    return Listener(
      onPointerDown: autoMode ? null : (_) => onDown(),
      onPointerUp: autoMode ? null : (_) => onUp(),
      onPointerCancel: autoMode ? null : (_) => onUp(),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        decoration: BoxDecoration(
          color: active ? const Color(0xFF172637) : const Color(0xFF0B151F),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: active ? accent : const Color(0xFF46586A),
            width: active ? 2 : 1,
          ),
          boxShadow: active
              ? [
                  BoxShadow(
                    color: accent.withOpacity(.25),
                    blurRadius: 18,
                  ),
                ]
              : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color: autoMode ? Colors.white24 : accent,
              size: 62,
            ),
            Text(
              label,
              style: TextStyle(
                color: autoMode ? Colors.white24 : accent,
                fontWeight: FontWeight.w900,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 2),
            const Text(
              'HOLD',
              style: TextStyle(
                color: Colors.white38,
                fontSize: turboStyle ? 12 : (big ? 11 : 10),
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _actionButton(
    String label,
    IconData icon,
    Color color,
    bool active,
    VoidCallback onTap,
    {bool big = false, bool turboStyle = false}
  ) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: _smallAction(label, icon, color, active, big: big, turboStyle: turboStyle),
      ),
    );
  }

  Widget _smallAction(
    String label,
    IconData icon,
    Color color,
    bool active,
    {bool big = false, bool turboStyle = false}
  ) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      constraints: BoxConstraints(minHeight: turboStyle ? 84 : (big ? 72 : 66)),
      padding: EdgeInsets.symmetric(horizontal: big ? 9 : 6, vertical: big ? 8 : 6),
      decoration: BoxDecoration(
        color: active ? darkPanel : silver2,
        borderRadius: BorderRadius.circular(turboStyle ? 16 : 12),
        border: Border.all(
          color: active ? color : const Color(0xFFBCC6D1),
          width: active ? 2 : 1,
        ),
        boxShadow: active
            ? [
                BoxShadow(
                  color: color.withOpacity(.25),
                  blurRadius: 10,
                ),
              ]
            : null,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: active ? color : ink, size: turboStyle ? 31 : (big ? 27 : 25)),
          const SizedBox(width: big ? 7 : 5),
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: active ? Colors.white : ink,
                fontSize: turboStyle ? 12 : (big ? 11 : 10),
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _footer() {
    return Container(
      height: 63,
      decoration: silverBox(),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        children: [
          _footerItem(
            Icons.shield_rounded,
            'SAFETY MODE',
            safety ? 'ON • Obstacle Stop' : 'OFF • Free Drive',
            safety ? green : red,
          ),
          _vLine(),
          _footerItem(
            Icons.smart_toy_rounded,
            'AUTO MODE',
            autoMode ? 'ACTIVE' : 'Ultrasonic Navigation',
            blue,
          ),
          _vLine(),
          _footerItem(
            Icons.speed_rounded,
            'SPEED PROFILES',
            'ECO • NORMAL • SPORT',
            purple,
          ),
          _vLine(),
          _footerItem(
            Icons.settings_input_component_rounded,
            'ALL CONTROLS',
            'Lights • Horn • Turbo • Signals',
            orange,
          ),
          _vLine(),
          _footerItem(
            Icons.wifi_rounded,
            'WI-FI CONTROL',
            '192.168.4.1:8080',
            connected ? green : blue,
          ),
          const SizedBox(width: 14),
          const Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'RK',
                style: TextStyle(
                  color: blue,
                  fontSize: 29,
                  fontWeight: FontWeight.w900,
                  fontStyle: FontStyle.italic,
                ),
              ),
              Text(
                'ROBOT',
                style: TextStyle(
                  color: ink,
                  fontSize: 9,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _footerItem(
    IconData icon,
    String title,
    String subtitle,
    Color color,
  ) {
    return Expanded(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(width: 8),
          Flexible(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: ink,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  subtitle,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: muted,
                    fontSize: 8,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _vLine() {
    return Container(
      width: 1,
      height: 40,
      margin: const EdgeInsets.symmetric(horizontal: 8),
      color: const Color(0xFFC8D0D8),
    );
  }

  void _showSettings() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('RK ROBOT PRO'),
        content: Text(
          'Silver Pro • No Camera\n'
          'Robot: $ip:$port\n'
          'Safety: ${safety ? 'ON' : 'OFF'}\n'
          'Auto: ${autoMode ? 'ON' : 'OFF'}\n'
          'Profile: $profileName\n'
          'PWM: ${speed.round()}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CLOSE'),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final IconData icon;
  final String title;
  final bool dark;

  const _SectionTitle({
    required this.icon,
    required this.title,
    this.dark = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = dark ? Colors.white : _RKDashboardState.ink;

    return Row(
      children: [
        Icon(
          icon,
          color: dark ? _RKDashboardState.blue2 : _RKDashboardState.ink,
          size: 18,
        ),
        const SizedBox(width: 7),
        Text(
          title,
          style: TextStyle(
            color: color,
            fontSize: 12,
            fontWeight: FontWeight.w900,
            letterSpacing: .6,
          ),
        ),
      ],
    );
  }
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = const Color(0xFF1B3448)
      ..strokeWidth = .7;

    for (double x = 0; x < size.width; x += 28) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), p);
    }

    for (double y = 0; y < size.height; y += 28) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
