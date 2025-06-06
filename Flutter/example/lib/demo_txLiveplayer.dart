// Copyright (c) 2022 Tencent. All rights reserved.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:super_player/super_player.dart';
import 'package:super_player_example/res/app_localizations.dart';
import 'package:superplayer_widget/demo_superplayer_lib.dart';

import 'ui/demo_inputdialog.dart';
import 'ui/demo_volume_slider.dart';
import 'ui/demo_video_slider_view.dart';
import 'common/demo_config.dart';

class DemoTXLivePlayer extends StatefulWidget {
  @override
  _DemoTXLivePlayerState createState() => _DemoTXLivePlayerState();
}

class _DemoTXLivePlayerState extends State<DemoTXLivePlayer> with WidgetsBindingObserver {
  late TXLivePlayerController _controller;
  int _volume = 100;
  bool _isMute = false;
  String _url = "http://liteavapp.qcloud.com/live/liteavdemoplayerstreamid_demo1080p.flv";
  int _currentBitRateIndex = 0;
  bool _isStop = true;
  bool _isPlaying = false;
  StreamSubscription? playEventSubscription;
  StreamSubscription? playNetEventSubscription;
  StreamSubscription? playerStateEventSubscription;

  GlobalKey<VideoSliderViewState> progressSliderKey = GlobalKey();
  FTXPlayerRenderMode _renderMode = FTXPlayerRenderMode.ADJUST_RESOLUTION;

  Future<void> init() async {
    if (!mounted) return;

    _controller = TXLivePlayerController();

    playEventSubscription = _controller.onPlayerEventBroadcast.listen((event) {
      // Subscribe to event distribution
      int evtCode = event["event"];
      if (evtCode == TXVodPlayEvent.PLAY_EVT_RCV_FIRST_I_FRAME) {
        // First frame appearance
        _isStop = false;
        _isPlaying = true;
        EasyLoading.dismiss();
      } else if (evtCode == TXVodPlayEvent.PLAY_EVT_PLAY_BEGIN) {
        _isPlaying = true;
      } else if (evtCode== TXVodPlayEvent.PLAY_EVT_STREAM_SWITCH_SUCC) {
        // Stream switching successful.
        EasyLoading.dismiss();
        EasyLoading.showSuccess(AppLocals.current.playerSwitchSuc);
      } else if (evtCode == TXVodPlayEvent.PLAY_ERR_STREAM_SWITCH_FAIL) {
        EasyLoading.dismiss();
        EasyLoading.showError(AppLocals.current.playerLiveSwitchFailed);
      } else if(evtCode < 0 && evtCode != -100) {
        EasyLoading.showError("play failed, code:$evtCode,event:$event");
      }
    });

    playerStateEventSubscription = _controller.onPlayerState.listen((event) {
      // Subscribe to status changes
      debugPrint("Playback status ${event!.name}");
    });

    _controller.setRenderMode(FTXPlayerRenderMode.ADJUST_RESOLUTION);

    if (!isLicenseSuc.isCompleted) {
      SuperPlayerPlugin.setGlobalLicense(LICENSE_URL, LICENSE_KEY);
      await isLicenseSuc.future;
      await _controller.startLivePlay(_url);
    } else {
      await _controller.startLivePlay(_url);
    }
  }

  @override
  void initState() {
    super.initState();
    // stop pip window if exists
    TXPipController.instance.exitAndReleaseCurrentPip();
    init();
    WidgetsBinding.instance.addObserver(this);
    EasyLoading.show(status: 'loading...');
  }

  @override
  Future didChangeAppLifecycleState(AppLifecycleState state) async {
    super.didChangeAppLifecycleState(state);
    print("didChangeAppLifecycleState $state");
    switch (state) {
      case AppLifecycleState.inactive:
        break;
      case AppLifecycleState.resumed:
        if (_isPlaying) {
          _controller.resume();
        }
        break;
      case AppLifecycleState.paused:
        _controller.pause();
        break;
      default:
        break;
    }
  }

  bool switchUrl() {
    bool switchStarted = true;
    if (_url == "http://liteavapp.qcloud.com/live/liteavdemoplayerstreamid_demo480p.flv") {
      _url = "http://liteavapp.qcloud.com/live/liteavdemoplayerstreamid_demo1080p.flv";
    } else if (_url == "http://liteavapp.qcloud.com/live/liteavdemoplayerstreamid_demo1080p.flv") {
      _url = "http://liteavapp.qcloud.com/live/liteavdemoplayerstreamid_demo480p.flv";
    } else {
      switchStarted = false;
      EasyLoading.showInfo("no other steam to switch");
    }
    return switchStarted;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
          image: DecorationImage(
        image: AssetImage("images/ic_new_vod_bg.png"),
        fit: BoxFit.cover,
      )),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          title: Text(AppLocals.current.playerLivePlay),
        ),
        body: SafeArea(
          child: Column(
            children: [
              Container(
                height: 220,
                color: Colors.black,
                child: Center(
                  child: TXPlayerVideo(
                    onRenderViewCreatedListener: (viewId) {
                      /// 此处只展示了最基础的纹理和播放器的配置方式。 这里可记录下来 viewId，在多纹理之间进行切换，比如横竖屏切换场景，竖屏的画面，
                      /// 要切换到横屏的画面，可以在切换到横屏之后，拿到横屏的viewId 设置上去。回到竖屏的时候，再通过 viewId 切换回来。
                      /// Only the most basic configuration methods for textures and the player are shown here.
                      /// The `viewId` can be recorded here to switch between multiple textures. For example, in the scenario
                      /// of switching between portrait and landscape orientations:
                      /// To switch from the portrait view to the landscape view, obtain the `viewId` of the landscape view
                      /// after switching to landscape orientation and set it.  When switching back to portrait orientation,
                      /// switch back using the recorded `viewId`.
                      _controller.setPlayerView(viewId);
                    },
                  )
                ),
              ),
              VideoSliderView(_controller, progressSliderKey),
              Expanded(
                  child: GridView.count(
                crossAxisSpacing: 10.0,
                mainAxisSpacing: 30.0,
                padding: EdgeInsets.all(10.0),
                crossAxisCount: 5,
                childAspectRatio: 1.5,
                children: [
                  _createItem(AppLocals.current.playerResumePlay, () async {
                    if (_isStop) {
                      EasyLoading.showError(AppLocals.current.playerLiveStopTip);
                      return;
                    }
                    _controller.resume();
                  }),
                  _createItem(AppLocals.current.playerPausePlay, () {
                    if (_isStop) {
                      EasyLoading.showError(AppLocals.current.playerLiveStopTip);
                      return;
                    }
                    _isPlaying = false;
                    _controller.pause();
                  }),
                  _createItem(AppLocals.current.playerStopPlay, () {
                    _isStop = true;
                    _controller.stop(isNeedClear: true);
                  }),
                  _createItem(AppLocals.current.playerReplay,
                      () => _controller.startLivePlay(_url, playType: TXPlayType.LIVE_FLV)),
                  _createItem(AppLocals.current.playerQualitySwitch, () async {
                    if (_isStop) {
                      EasyLoading.showError(AppLocals.current.playerLiveStopTip);
                      return;
                    }
                    List<FSteamInfo> steamInfo = await _controller.getSupportedBitrate();
                    if (steamInfo.isNotEmpty) {
                      FSteamInfo info = steamInfo[++_currentBitRateIndex % steamInfo.length];
                      if (info.url != null) {
                        _controller.switchStream(info.url!);
                        EasyLoading.show(status: 'loading...');
                      } else {
                        EasyLoading.showError("steam url is null");
                      }
                    } else {
                      if (switchUrl()) {
                        _controller.switchStream(_url);
                        EasyLoading.show(status: 'loading...');
                      }
                    }
                  }),
                  _createItem(_isMute ? AppLocals.current.playerCancelMute : AppLocals.current.playerSetMute, () async {
                    setState(() {
                      _isMute = !_isMute;
                      _controller.setMute(_isMute);
                    });
                  }),
                  _createItem(AppLocals.current.playerAdjustVolume, () {
                    onClickVolume();
                  }),
                  _createItem(_renderMode == FTXPlayerRenderMode.ADJUST_RESOLUTION
                      ? AppLocals.current.playerRenderModeAdjust
                      : AppLocals.current.playerRenderModeFill, () async {
                    if (_renderMode == FTXPlayerRenderMode.ADJUST_RESOLUTION) {
                      _renderMode = FTXPlayerRenderMode.FULL_FILL_CONTAINER;
                    } else {
                      _renderMode = FTXPlayerRenderMode.ADJUST_RESOLUTION;
                    }
                    _controller.setRenderMode(_renderMode);
                    setState(() {});
                  }),
                ],
              )),
              Expanded(
                  child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Container(
                    height: 100,
                    child: IconButton(icon: Image.asset('images/addp.png'), onPressed: () => {onPressed()}),
                  )
                ],
              )),
            ],
          ),
        ),
      ),
    );
  }

  Widget _createItem(String name, GestureTapCallback tapBlock) {
    return InkWell(
      onTap: tapBlock,
      child: Container(
        child: Text(name,
          style: TextStyle(fontSize: 14, color: Colors.blue),
          overflow: TextOverflow.visible,),
      ),
    );
  }

  @override
  void dispose() {
    playerStateEventSubscription?.cancel();
    playEventSubscription?.cancel();
    playNetEventSubscription?.cancel();
    _controller.dispose();
    super.dispose();
    WidgetsBinding.instance.removeObserver(this);
    EasyLoading.dismiss();
  }

  void onPressed() {
    showDialog(
        context: context,
        builder: (context) {
          return DemoInputDialog("", 0, "", (String url, int appId, String fileId, String pSign, bool enableDownload, _) {
            _url = url;
            _controller.stop();
            if (url.isNotEmpty) {
              _controller.startLivePlay(url);
            }
          }, showFileEdited: false);
        });
  }

  void onClickVolume() {
    showDialog(
        context: context,
        builder: (context) {
          return DemoVolumeSlider(_volume, (int result) {
            _volume = result;
            _controller.setVolume(_volume);
          });
        });
  }
}
