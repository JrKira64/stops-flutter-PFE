import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:url_launcher/url_launcher.dart';

import '../main.dart';
import '../utils/database_utils.dart';
import 'fetch_data_dialog.dart';

class SettingsPage extends StatefulWidget {
  static const String _kThemeLabelSystem = 'System';
  static const String _kThemeLabelLight = 'Light';
  static const String _kThemeLabelDark = 'Dark';

  @override
  State createState() {
    return SettingsPageState();
  }
}

class SettingsPageState extends State<SettingsPage> {
  ThemeMode _themeMode;

  @override
  void initState() {
    super.initState();
    getThemeMode().then((ThemeMode themeMode) {
      setState(() {
        _themeMode = themeMode;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: ListView(
        children: <Widget>[
          _buildThemeTile(),
          _buildRefreshDataTile(),
          _buildAboutTile(),
        ],
      ),
    );
  }

  Widget _buildThemeTile() {
    return ListTile(
      title: const Text('Theme'),
      subtitle: Text(_getThemeLabel(_themeMode)),
      leading: const Icon(Icons.brush),
      onTap: () {
        showDialog<ThemeMode>(
            context: context,
            builder: (BuildContext context) {
              return AlertDialog(
                title: const Text('Choose theme'),
                contentPadding: const EdgeInsets.symmetric(vertical: 16.0),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    RadioListTile<ThemeMode>(
                      title: Text(_getThemeLabel(ThemeMode.system)),
                      value: ThemeMode.system,
                      groupValue: _themeMode,
                      onChanged: _onThemeModeChanged,
                    ),
                    RadioListTile<ThemeMode>(
                      title: const Text(SettingsPage._kThemeLabelLight),
                      value: ThemeMode.light,
                      groupValue: _themeMode,
                      onChanged: _onThemeModeChanged,
                    ),
                    RadioListTile<ThemeMode>(
                      title: const Text(SettingsPage._kThemeLabelDark),
                      value: ThemeMode.dark,
                      groupValue: _themeMode,
                      onChanged: _onThemeModeChanged,
                    ),
                  ],
                ),
              );
            }
        );
      },
    );
  }

  Widget _buildAboutTile() {
    return ListTile(
      title: const Text('About'),
      leading: const Icon(Icons.info_outline),
      onTap: () {
        showAboutDialog(
          context: context,
          applicationIcon: Image.asset(
            'assets/images/icon/icon_squircle.png',
            width: IconTheme.of(context).size * 2,
            height: IconTheme.of(context).size * 2,
          ),
          applicationName: 'Stops',
          applicationVersion: '0.6.3',
          children: <Widget>[
            RichText(
              text: TextSpan(
                text: 'Made by ',
                style: Theme.of(context).textTheme.bodyText2,
                children: <TextSpan>[
                  TextSpan(
                    text: 'Jeff Sieu',
                    style: TextStyle(color: Theme.of(context).colorScheme.secondary),
                    recognizer: TapGestureRecognizer()..onTap = () async {
                      const String url = 'https://github.com/jeffsieu';
                      if (await canLaunch(url)) {
                        await launch(
                          url,
                          forceSafariVC: false,
                        );
                      }
                    },
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildRefreshDataTile() {
    return ListTile(
      title: const Text('Refresh cached data'),
      subtitle: const Text('Select if there are missing stops/services'),
      leading: const Icon(Icons.update),
      onTap: () {
        showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (BuildContext context) {
            return const FetchDataDialog(isSetup: false);
          },
        );
      },
    );
  }

  String _getThemeLabel(ThemeMode themeMode) {
    switch (themeMode) {
      case ThemeMode.system:
        final Brightness brightness = MediaQuery.of(context).platformBrightness;
        final String brightnessLabel = brightness == Brightness.light ? SettingsPage._kThemeLabelLight : SettingsPage._kThemeLabelDark;
        return '${SettingsPage._kThemeLabelSystem} ($brightnessLabel)';
      case ThemeMode.light:
        return SettingsPage._kThemeLabelLight;
      case ThemeMode.dark:
        return SettingsPage._kThemeLabelDark;
      default:
        return SettingsPage._kThemeLabelSystem;
    }
  }

  Future<void> _onThemeModeChanged(ThemeMode themeMode) async {
    await setThemeMode(themeMode);
    Navigator.pop(context);
    final StopsAppState appState = StopsApp.of(context);
    appState.setState(() {
      appState.themeMode = themeMode;
    });
    setState(() {
      _themeMode = themeMode;
    });
  }
}