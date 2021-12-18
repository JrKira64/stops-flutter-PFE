import 'dart:async';

import 'package:auto_size_text/auto_size_text.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:rubber/rubber.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/bus_service.dart';
import '../models/bus_stop.dart';
import '../models/user_route.dart';
import '../routes/home_page.dart';
import '../routes/settings_page.dart';
import '../utils/bus_api.dart';
import '../utils/bus_service_arrival_result.dart';
import '../utils/bus_utils.dart';
import '../utils/database_utils.dart';
import '../widgets/bus_stop_legend_card.dart';
import '../widgets/bus_timing_row.dart';
import 'info_card.dart';

class BusStopDetailSheet extends StatefulWidget {
  BusStopDetailSheet(
      {Key? key, required TickerProvider vsync, required this.hasAppBar})
      : rubberAnimationController = RubberAnimationController(
          vsync: vsync,
          lowerBoundValue: AnimationControllerValue(percentage: 0),
          halfBoundValue: AnimationControllerValue(percentage: 0.5),
          upperBoundValue: AnimationControllerValue(percentage: 1),
          duration: const Duration(milliseconds: 200),
          springDescription: SpringDescription.withDampingRatio(
              mass: 1, ratio: DampingRatio.NO_BOUNCY, stiffness: Stiffness.LOW),
        ),
        scrollController = ScrollController(),
        super(key: key) {
    rubberAnimationController.addStatusListener((AnimationStatus status) {
      if (status == AnimationStatus.completed) {
        rubberAnimationController.halfBoundValue = null;
      }
    });
  }

  final ScrollController scrollController;
  final RubberAnimationController rubberAnimationController;
  final bool hasAppBar;
  static const Duration updateAnimationDuration = Duration(milliseconds: 1000);
  static const Duration editAnimationDuration = Duration(milliseconds: 250);
  static const double rowAnimationDuration = 0.4;
  static const double rowAnimationOffset = 0.075;
  static const double _launchVelocity = 5.0;
  final double titleFadeInDurationFactor = 0.5;
  final double _sheetHalfBoundValue = 0.5;

  static BusStopDetailSheetState? of(BuildContext context) =>
      context.findAncestorStateOfType<BusStopDetailSheetState>();

  @override
  State<StatefulWidget> createState() => BusStopDetailSheetState();
}

class BusStopDetailSheetState extends State<BusStopDetailSheet>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  BusStop? _busStop;
  UserRoute? _route;
  List<BusServiceArrivalResult>? _latestData;
  bool _isStarEnabled = false;
  bool _isEditing = false;
  bool _isAnimating = false;

  Stream<List<BusServiceArrivalResult>>? _busArrivalStream;

  late final AnimationController timingListAnimationController =
      AnimationController(
          duration: BusStopDetailSheet.updateAnimationDuration, vsync: this);

  BusStopChangeListener? _busStopListener;
  TextEditingController? textController;

  /*
   * Updates the bottom sheet with details of another bus stop
   *
   * Called externally from the parent containing this widget
   */
  Future<void> updateWith(BusStop? busStop, UserRoute? route) async {
    _busStop = busStop;
    _route = route;
    if (_busStop == null || _route == null) {
      setState(() {});
      return;
    }
    final bool starred = await isBusStopInRoute(busStop!, route!);
    setState(() {
      if (_busStopListener != null) {
        unregisterBusStopListener(_busStop!, _busStopListener!);
      }

      _isStarEnabled = starred;
      _isEditing = false;
      _busArrivalStream = BusAPI().busStopArrivalStream(busStop);
      _latestData = BusAPI().getLatestArrival(busStop);
      textController = TextEditingController(text: _busStop!.displayName);

      timingListAnimationController.forward(from: 0);
      widget.rubberAnimationController.halfBoundValue =
          AnimationControllerValue(percentage: widget._sheetHalfBoundValue);
      // Lock animation while animating, as pressing another bus stop item
      // before the animation ends will cause the bottom sheet to be "dragged"
      // to the finger
      if (!_isAnimating) {
        _isAnimating = true;
        widget.rubberAnimationController
            .launchTo(
          widget.rubberAnimationController.value,
          widget.rubberAnimationController.halfBound,
          velocity: BusStopDetailSheet._launchVelocity,
        )
            .whenCompleteOrCancel(() {
          _isAnimating = false;
        });
      }
    });

    _busStopListener = (BusStop busStop) {
      isBusStopInRoute(busStop, _route!).then((bool contains) {
        if (mounted) {
          setState(() {
            _busStop = busStop;
            _isStarEnabled = contains;
          });
        }
      });
    };
    registerBusStopListener(_busStop!, _busStopListener!);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance?.addObserver(this);
  }

  @override
  Future<void> didChangeAppLifecycleState(AppLifecycleState state) async {
    if (state == AppLifecycleState.resumed) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_busStop == null) return Container();

    final Widget scrollView = ListView(
      padding: const EdgeInsets.all(0),
      physics: const NeverScrollableScrollPhysics(),
      controller: widget.scrollController,
      children: <Widget>[
        _buildHeader(_busStop!),
        _buildServiceList(),
        _buildFooter(context),
      ],
    );

    return WillPopScope(
      onWillPop: _onWillPop,
      child: Material(
        type: MaterialType.card,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(16.0),
          topRight: Radius.circular(16.0),
        ),
        elevation: 16.0,
        child: Provider<UserRoute>(
          create: (_) => _route!,
          child: scrollView,
        ),
      ),
    );
  }

  @override
  void dispose() {
    timingListAnimationController.dispose();
    if (_busStop != null && _busStopListener != null) {
      unregisterBusStopListener(_busStop!, _busStopListener!);
    }
    WidgetsBinding.instance?.removeObserver(this);
    super.dispose();
  }

  Future<bool> _onWillPop() async {
    if (_isEditing) {
      setState(() {
        _isEditing = false;
      });
      return false;
    }

    if (widget.rubberAnimationController.value != 0) {
      widget.rubberAnimationController.animateTo(to: 0);
      return false;
    }

    return true;
  }

  Widget _buildHeader(BusStop busStop) {
    final double statusBarHeight = MediaQuery.of(context).padding.top;
    final double extraPadding = widget.hasAppBar ? 0 : statusBarHeight;

    return AnimatedBuilder(
      animation: widget.rubberAnimationController,
      builder: (BuildContext context, Widget? child) {
        final double completed = widget.rubberAnimationController.upperBound!;
        final double dismissed = widget.rubberAnimationController.lowerBound!;
        const double animationStart = 0.75;
        final double animationRange = completed - animationStart;
        final double animationStartBound =
            dismissed + (completed - dismissed) * animationStart;
        final double paddingHeightScale =
            ((widget.rubberAnimationController.value - animationStartBound) /
                    animationRange)
                .clamp(0.0, 1.0);
        return Container(
          padding: EdgeInsets.only(
            top: 48.0 + extraPadding * paddingHeightScale,
            left: 16.0,
            right: 16.0,
            bottom: 32.0,
          ),
          child: child,
        );
      },
      child: Stack(
        children: <Widget>[
          Center(
            child: Padding(
              padding: const EdgeInsets.only(left: 56.0, right: 56.0),
              child: AnimatedSize(
                alignment: Alignment.topCenter,
                duration: BusStopDetailSheet.updateAnimationDuration * 0.1,
                child: AnimatedSwitcher(
                  duration: BusStopDetailSheet.updateAnimationDuration *
                      widget.titleFadeInDurationFactor,
                  switchInCurve: const Interval(0.25, 1),
                  switchOutCurve: const Interval(0.75, 1),
                  layoutBuilder:
                      (Widget? currentChild, List<Widget> previousChildren) {
                    return Stack(
                      children: <Widget>[
                        ...previousChildren,
                        if (currentChild != null) currentChild,
                      ],
                      alignment: Alignment.topCenter,
                    );
                  },
                  transitionBuilder:
                      (Widget child, Animation<double> animation) {
                    final bool entering =
                        child.key == ValueKey<String>(busStop.code);
                    final Animatable<double> curve = CurveTween(
                        curve: entering ? Curves.easeOutCubic : Curves.linear);
                    return FadeTransition(
                      opacity: animation,
                      child: SlideTransition(
                        position: animation.drive(curve).drive(Tween<Offset>(
                            begin: Offset(0, 0.5 * (entering ? 1 : -1)),
                            end: Offset.zero)),
                        child: entering
                            ? child
                            : Align(
                                alignment: Alignment.topCenter,
                                heightFactor: 1 - animation.value,
                                child: child),
                      ),
                    );
                  },
                  child: Column(
                    key: Key(busStop.code),
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      AutoSizeText(
                        busStop.displayName,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headline5,
                        maxLines: 1,
                      ),
                      Text('${busStop.code} · ${busStop.road}',
                          textAlign: TextAlign.center,
                          style: Theme.of(context)
                              .textTheme
                              .subtitle2!
                              .copyWith(color: Theme.of(context).hintColor)),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Container(
            alignment: Alignment.centerRight,
            child: _buildHeaderOverflow(busStop),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderOverflow(BusStop busStop) {
    if (_isEditing) {
      return IconButton(
        tooltip: 'Save',
        icon: const Icon(Icons.done_rounded),
        color: Theme.of(context).colorScheme.secondary,
        onPressed: () {
          setState(() {
            _isEditing = false;
          });
        },
      );
    }
    return PopupMenuButton<_MenuOption>(
      icon: Icon(Icons.more_vert_rounded, color: Theme.of(context).hintColor),
      onSelected: (_MenuOption option) {
        switch (option) {
          case _MenuOption.edit:
            edit();
            break;
          case _MenuOption.rename:
            _showEditNameDialog();
            break;
          case _MenuOption.favorite:
            setState(() {
              _isStarEnabled = !_isStarEnabled;
            });
            if (_isStarEnabled) {
              addBusStopToRoute(_busStop!, _route!, context).then((_) {
                setState(() {});
                HomePage.of(context)?.refresh();
              });
            } else {
              removeBusStopFromRoute(_busStop!, _route!, context).then((_) {
                setState(() {});
                HomePage.of(context)?.refresh();
              });
            }
            break;
          case _MenuOption.googleMaps:
            launch(
                'geo:${busStop.latitude},${busStop.longitude}?q=${busStop.defaultName} ${busStop.code}');
            break;
        }
      },
      itemBuilder: (BuildContext context) => <PopupMenuEntry<_MenuOption>>[
        const PopupMenuItem<_MenuOption>(
          value: _MenuOption.rename,
          child: Text('Rename'),
        ),
        if (_isStarEnabled) const PopupMenuDivider(),
        if (_isStarEnabled)
          const PopupMenuItem<_MenuOption>(
            value: _MenuOption.edit,
            child: Text('Manage pinned services'),
          ),
        PopupMenuItem<_MenuOption>(
          value: _MenuOption.favorite,
          child: Text(_isStarEnabled
              ? _route == UserRoute.home
                  ? 'Unpin from home'
                  : 'Remove from route'
              : 'Pin to home'),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem<_MenuOption>(
          value: _MenuOption.googleMaps,
          child: Text('Open in Google Maps'),
        ),
      ],
    );
  }

  Widget _buildServiceList() {
    return Column(
      children: <Widget>[
        AnimatedSize(
          duration: BusStopDetailSheet.editAnimationDuration * 2,
          curve: Curves.easeInOutCirc,
          child: _isEditing
              ? Container(
                  padding: const EdgeInsets.only(
                      left: 32.0, right: 32.0, bottom: 8.0),
                  child: Column(
                    children: <Widget>[
                      Text(
                        'Pinned bus services',
                        style: Theme.of(context).textTheme.headline4,
                      ),
                      Text(
                        'Arrival times of pinned buses are displayed on the ${_route == UserRoute.home ? 'homepage' : 'route page'}',
                        textAlign: TextAlign.center,
                        style: Theme.of(context)
                            .textTheme
                            .bodyText2!
                            .copyWith(color: Theme.of(context).hintColor),
                      )
                    ],
                  ))
              : Container(),
        ),
        FutureBuilder<List<BusService>>(
            initialData: const <BusService>[],
            future: getServicesIn(_busStop!),
            builder: (BuildContext context,
                AsyncSnapshot<List<BusService>> snapshot) {
              return _buildTimingList(snapshot.data!);
            }),
      ],
    );
  }

  Widget _buildTimingList(List<BusService> allServices) {
    _latestData = BusAPI().getLatestArrival(_busStop!);
    return StreamBuilder<List<BusServiceArrivalResult>>(
      key: Key(_busStop!.code),
      initialData: _latestData,
      stream: _busArrivalStream,
      builder: (BuildContext context,
          AsyncSnapshot<List<BusServiceArrivalResult>> snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: InfoCard(
              icon: Icon(Icons.signal_wifi_connected_no_internet_4_rounded,
                  color: Theme.of(context).hintColor),
              title: Text(
                snapshot.error.toString(),
                style: Theme.of(context)
                    .textTheme
                    .subtitle1!
                    .copyWith(color: Theme.of(context).hintColor),
              ),
            ),
          );
        }
        switch (snapshot.connectionState) {
          case ConnectionState.none:
          // Should not happen.

          case ConnectionState.active:
          case ConnectionState.waiting:
            if (snapshot.data == null) {
              return const Center(child: CircularProgressIndicator());
            }
            continue done;
          done:
          case ConnectionState.done:
            if (snapshot.hasError) {
              return _messageBox('Error: ${snapshot.error}');
            }

            final List<BusServiceArrivalResult> buses = snapshot.data!;
            buses.sort((BusServiceArrivalResult a, BusServiceArrivalResult b) =>
                compareBusNumber(a.busService.number, b.busService.number));
            _latestData = snapshot.data;

            // Calculate the positions that the bus services will be displayed at
            // If the bus service has no arrival timings, it will not show and
            // will have a position of -1
            final List<int> displayedPositions =
                List<int>.generate(allServices.length, (int i) => -1);
            for (int i = 0, j = 0;
                i < allServices.length && j < buses.length;
                i++) {
              if (allServices[i] == buses[j].busService) {
                displayedPositions[i] = j;
                j++;
              }
            }

            return Stack(
              children: <Widget>[
                if (buses.isEmpty)
                  AnimatedOpacity(
                    duration: BusStopDetailSheet.editAnimationDuration,
                    opacity: _isEditing ? 0 : 1,
                    child: _buildStaggeredFadeInTransition(
                      position: 0,
                      child: Center(
                        child: InfoCard(
                          icon: Icon(Icons.bus_alert_rounded,
                              color: Theme.of(context).hintColor),
                          title: Text(
                            BusAPI.kNoBusesInServiceError,
                            style: Theme.of(context)
                                .textTheme
                                .subtitle1!
                                .copyWith(color: Theme.of(context).hintColor),
                          ),
                        ),
                      ),
                    ),
                  ),
                MediaQuery.removePadding(
                  context: context,
                  removeTop: true,
                  child: ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemBuilder: (BuildContext context, int position) {
                      final int displayedPosition =
                          displayedPositions[position];
                      final bool isDisplayed = displayedPosition != -1;

                      BusServiceArrivalResult? arrivalResult;
                      if (isDisplayed) arrivalResult = buses[displayedPosition];

                      final Widget item = BusTimingRow(
                        _busStop!,
                        allServices[position],
                        arrivalResult,
                        _isEditing,
                        key: Key(_busStop!.code + allServices[position].number),
                      );

                      // Animate if displayed
                      if (isDisplayed) {
                        return _buildStaggeredFadeInTransition(
                          child: item,
                          position: displayedPosition,
                        );
                      } else {
                        return item;
                      }
                    },
                    separatorBuilder: (BuildContext context, int position) {
                      // Checks if the item below the divider is shown, and not the first item
                      // If it is, then show the divider
                      final int displayedPositionBottom =
                          displayedPositions[position + 1];
                      final bool isBottomDisplayed =
                          displayedPositionBottom > 0;
                      final bool isDisplayed = _isEditing || isBottomDisplayed;
                      return isDisplayed
                          ? const Divider(height: 4.0)
                          : Container();
                    },
                    itemCount: allServices.length,
                  ),
                ),
              ],
            );
        }
      },
    );
  }

  // The transition for a row in the timing list
  Widget _buildStaggeredFadeInTransition(
      {Widget? child, required int position}) {
    final double startOffset =
        (position * BusStopDetailSheet.rowAnimationOffset).clamp(0.0, 1.0);
    final double endOffset = (position * BusStopDetailSheet.rowAnimationOffset +
            BusStopDetailSheet.rowAnimationDuration)
        .clamp(0.0, 1.0);
    final Animation<double> animation = timingListAnimationController
        .drive(CurveTween(
            curve: Interval(
                widget.titleFadeInDurationFactor -
                    BusStopDetailSheet.rowAnimationOffset,
                1))) // animate after previous code disappears
        .drive(CurveTween(
            curve: Interval(
                startOffset, endOffset))); // delay animation based on position

    return SlideTransition(
      position: animation
          .drive(CurveTween(curve: Curves.easeOutQuint))
          .drive(Tween<Offset>(
            begin: const Offset(0, 0.5),
            end: Offset.zero,
          )),
      child: FadeTransition(
        opacity: animation,
        child: child,
      ),
    );
  }

  Widget _messageBox(String text) {
    return Center(
      child: Text(text,
          style: Theme.of(context)
              .textTheme
              .subtitle1!
              .copyWith(color: Theme.of(context).hintColor)),
    );
  }

  Widget _buildFooter(BuildContext context) {
    final int rowCount = _latestData?.length ?? 0;
    final double startOffset =
        (rowCount * BusStopDetailSheet.rowAnimationOffset).clamp(0.0, 1.0);
    final double endOffset = (rowCount * BusStopDetailSheet.rowAnimationOffset +
            BusStopDetailSheet.rowAnimationDuration)
        .clamp(0.0, 1.0);
    final Animation<double> animation = timingListAnimationController
        .drive(CurveTween(
            curve: Interval(
                widget.titleFadeInDurationFactor -
                    BusStopDetailSheet.rowAnimationOffset,
                1))) // animate after previous code disappears
        .drive(CurveTween(
            curve: Interval(
                startOffset, endOffset))); // delay animation based on position
    return SlideTransition(
      position: animation
          .drive(CurveTween(curve: Curves.easeOutQuint))
          .drive(Tween<Offset>(
            begin: const Offset(0, 0.5),
            end: Offset.zero,
          )),
      child: FadeTransition(
        opacity: animation,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const SizedBox(height: 8.0),
              const BusStopLegendCard(),
              Center(
                child: TextButton(
                  onPressed: () {
                    // Open settings page
                    Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                            builder: (BuildContext context) =>
                                const SettingsPage()));
                  },
                  child: Text('Missing bus services?',
                      style: Theme.of(context)
                          .textTheme
                          .subtitle2!
                          .copyWith(color: Theme.of(context).hintColor)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showEditNameDialog() async {
    // Reset text controller
    textController!.text = _busStop!.displayName;
    final String? newName = await showDialog<String>(
        context: context,
        builder: (BuildContext context) {
          textController!.selection = TextSelection(
              baseOffset: 0, extentOffset: textController!.text.length);
          return Dialog(
            child: Padding(
              padding:
                  const EdgeInsets.only(left: 8.0, right: 8.0, bottom: 8.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.only(top: 16.0, left: 16.0),
                    child: Text(
                      'Rename bus stop',
                      style: Theme.of(context).textTheme.headline6,
                    ),
                  ),
                  Container(height: 16.0),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    child: TextField(
                      onSubmitted: (String name) {
                        changeBusStopName(name);
                        Navigator.pop(context);
                      },
                      autofocus: true,
                      autocorrect: true,
                      controller: textController,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        labelText: 'Name',
                      ),
                    ),
                  ),
                  Container(height: 28.0),
                  ButtonTheme(
                    minWidth: 0,
                    height: 36,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    child: Row(
                      children: <Widget>[
                        TextButton(
                          onPressed: () {
                            textController!.text = _busStop!.defaultName;
                          },
                          child: Text('RESET',
                              style: TextStyle(
                                  color: Theme.of(context).colorScheme.primary,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1.1)),
                        ),
                        const Spacer(),
                        TextButton(
                          onPressed: () {
                            Navigator.pop(context);
                          },
                          child: Text('CANCEL',
                              style: TextStyle(
                                  color: Theme.of(context).colorScheme.primary,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1.1)),
                        ),
                        Container(width: 8.0),
                        TextButton(
                          onPressed: () {
                            final String newName = textController!.text;
                            Navigator.pop(context, newName);
                          },
                          child: Text('SAVE',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1.1,
                                  color:
                                      Theme.of(context).colorScheme.primary)),
                        )
                      ],
                    ),
                  )
                ],
              ),
            ),
          );
        });
    if (newName != null) {
      changeBusStopName(newName);
    }
  }

  void changeBusStopName(String newName) {
    setState(() {
      _busStop!.displayName = newName;
    });
    updateBusStop(_busStop!);
  }

  void edit() {
    setState(() {
      _isEditing = true;
      if (widget.rubberAnimationController.value !=
          widget.rubberAnimationController.upperBound) {
        widget.rubberAnimationController.launchTo(
            widget.rubberAnimationController.value,
            widget.rubberAnimationController.upperBound,
            velocity: BusStopDetailSheet._launchVelocity / 2);
      }
    });
  }
}

enum _MenuOption { edit, favorite, googleMaps, rename }
