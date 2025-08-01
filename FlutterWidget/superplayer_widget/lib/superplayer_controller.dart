// Copyright (c) 2022 Tencent. All rights reserved.
part of demo_super_player_lib;

/// superPlayer play controller
class SuperPlayerController {
  static const TAG = "SuperPlayerController";

  final StreamController<Map<dynamic, dynamic>> _simpleEventStreamController = StreamController.broadcast();
  final StreamController<Map<dynamic, dynamic>> _playerNetStatusStreamController = StreamController.broadcast();

  /// simple event,see SuperPlayerViewEvent
  Stream<Map<dynamic, dynamic>> get onSimplePlayerEventBroadcast => _simpleEventStreamController.stream;

  /// player net status,see TXVodNetEvent
  Stream<Map<dynamic, dynamic>> get onPlayerNetStatusBroadcast => _playerNetStatusStreamController.stream;

  late TXVodPlayerController _vodPlayerController;
  late TXLivePlayerController _livePlayerController;

  SuperPlayerModel? videoModel;
  int _playAction = SuperPlayerModel.PLAY_ACTION_AUTO_PLAY;
  _SuperPlayerObserver? _observer;
  VideoQuality? currentQuality;
  List<VideoQuality>? currentQualityList;
  TXTrackInfo? currentAudioTrackInfo;
  List<TXTrackInfo>? audioTrackInfoList;
  TXTrackInfo? currentSubtitleTrackInfo;
  List<TXTrackInfo>? subtitleTrackInfoList;
  TXVodSubtitleData? currentSubtitleData;
  TXSubtitleRenderModel? _currentSubtitleRenderModel;
  SuperPlayerState playerState = SuperPlayerState.INIT;
  SuperPlayerType playerType = SuperPlayerType.VOD;
  FTXVodPlayConfig vodConfig = FTXVodPlayConfig();
  FTXLivePlayConfig liveConfig = FTXLivePlayConfig();
  StreamSubscription? _vodPlayEventListener;
  StreamSubscription? _vodNetEventListener;
  StreamSubscription? _livePlayEventListener;
  StreamSubscription? _liveNetEventListener;

  PlayImageSpriteInfo? spriteInfo;
  List<PlayKeyFrameDescInfo>? keyFrameInfo;

  String _currentPlayUrl = "";

  bool isPrepared = false;
  bool isMute = false;
  bool isLoop = false;
  bool _needToResume = false;
  bool _needToPause = false;
  bool callResume = false;
  bool _isMultiBitrateStream = false; // the flag playing multi-bitrate URLs flag
  bool _changeHWAcceleration = false; // the flag before receiving the first keyframe after switching to hardware decoding
  bool _isOpenHWAcceleration = true;
  int _playerUIStatus = SuperPlayerUIStatus.WINDOW_MODE;
  final BuildContext _context;
  FullScreenController fullScreenController = FullScreenController();

  double currentDuration = 0;
  double videoDuration = 0;
  int _maxLiveProgressTime = 0;

  double _seekPos = 0; // the playback time when switching to hardware decoding.
  /// This value will change the playback start time of the new video
  /// 该值会改变新播放视频的播放开始时间点
  double startPos = 0;

  /// The video size parsed by the player kernel
  /// 播放器内核解析出来的视频宽高
  double videoWidth = 0;
  double videoHeight = 0;
  double currentPlayRate = 1.0;
  int _curViewId = -1;

  SuperPlayerController(this._context) {
    _initVodPlayer();
    _initLivePlayer();
  }

  void _initVodPlayer() async {
    _vodPlayerController = TXVodPlayerController();
    _setVodListener();
  }

  void _initLivePlayer() async {
    _livePlayerController = TXLivePlayerController();
    _setLiveListener();
  }

  void _setVodListener() {
    _vodPlayEventListener?.cancel();
    _vodNetEventListener?.cancel();
    _vodPlayEventListener = _vodPlayerController.onPlayerEventBroadcast.listen((event) async {
      int eventCode = event['event'];
      switch (eventCode) {
        case TXVodPlayEvent.VOD_PLAY_EVT_SELECT_TRACK_COMPLETE:
          int? errorCode = event["EVT_KEY_SELECT_TRACK_ERROR_CODE"];
          int? trackIndex = event["EVT_KEY_SELECT_TRACK_INDEX"];
          LogUtils.d(TAG, "selectTrack,trackIndex:$trackIndex,errorCode:$errorCode");
          break;
        case TXVodPlayEvent.PLAY_EVT_GET_PLAYINFO_SUCC:
          _currentPlayUrl = event[TXVodPlayEvent.EVT_PLAY_URL];
          PlayImageSpriteInfo playImageSpriteInfo = PlayImageSpriteInfo();
          playImageSpriteInfo.webVttUrl = event[TXVodPlayEvent.EVT_IMAGESPRIT_WEBVTTURL] ?? "";
          event[TXVodPlayEvent.EVT_IMAGESPRIT_IMAGEURL_LIST]?.forEach((element) {
            playImageSpriteInfo.imageUrls.add(element);
          });
          _vodPlayerController.initImageSprite(playImageSpriteInfo.webVttUrl, playImageSpriteInfo.imageUrls);
          spriteInfo = playImageSpriteInfo;
          _addSimpleEvent(SuperPlayerViewEvent.onSuperPlayerGetInfo, params: event);
          break;
        case TXVodPlayEvent.PLAY_EVT_VOD_PLAY_PREPARED: // vodPrepared
          isPrepared = true;
          addSubTitle();
          if (_isMultiBitrateStream) {
            List<dynamic>? bitrateListTemp = await _vodPlayerController.getSupportedBitrates();
            List<FTXBitrateItem> bitrateList = [];
            if (null != bitrateListTemp) {
              for (Map<dynamic, dynamic> map in bitrateListTemp) {
                bitrateList.add(FTXBitrateItem(map['index'], map['width'], map['height'], map['bitrate']));
              }
            }

            VideoQuality? defaultQuality;
            List<VideoQuality> videoQualities = [];
            bitrateList.sort((a, b) => b.bitrate.compareTo(a.bitrate)); // Sort the bitrate from high to low
            for (int i = 0; i < bitrateList.length; i++) {
              FTXBitrateItem bitrateItem = bitrateList[i];
              VideoQuality quality = VideoQualityUtils.convertToVideoQualityByBitrate(_context, bitrateItem);
              videoQualities.add(quality);
            }

            int? bitrateIndex = await _vodPlayerController.getBitrateIndex(); // Get the index of the default bitrate
            for (VideoQuality quality in videoQualities) {
              if (quality.index == bitrateIndex) {
                defaultQuality = quality;
              }
            }
            _updateVideoQualityList(videoQualities, defaultQuality);
          }

          if (_needToPause) {
            _vodPlayerController.pause();
          } else if (_needToResume) {
            _vodPlayerController.resume();
          }
          videoDuration = await _vodPlayerController.getDuration();
          currentDuration = await _vodPlayerController.getCurrentPlaybackTime();
          List<TXTrackInfo> aaa = await _vodPlayerController.getAudioTrackInfo();
          _onSelectTrackInfoWhenPrepare();
          break;
        case TXVodPlayEvent.PLAY_EVT_PLAY_LOADING: // PLAY_EVT_PLAY_LOADING
          if (playerState == SuperPlayerState.PAUSE) {
            _updatePlayerState(SuperPlayerState.PAUSE);
          } else {
            _updatePlayerState(SuperPlayerState.LOADING);
          }
          break;
        case TXVodPlayEvent.PLAY_EVT_VOD_LOADING_END:
          if (playerState == SuperPlayerState.LOADING) {
            _updatePlayerState(SuperPlayerState.PLAYING);
          }
          break;
        case TXVodPlayEvent.PLAY_EVT_PLAY_BEGIN: // PLAY_EVT_PLAY_BEGIN
          if (_needToPause) {
            return;
          }
          _updatePlayerState(SuperPlayerState.PLAYING);
          break;
        case TXVodPlayEvent.PLAY_EVT_RCV_FIRST_I_FRAME: // PLAY_EVT_RCV_FIRST_I_FRAME
          if (_needToPause) {
            return;
          }
          if (_changeHWAcceleration) {
            LogUtils.d(TAG, "seek pos $_seekPos");
            seek(_seekPos);
            _changeHWAcceleration = false;
          }
          _updatePlayerState(SuperPlayerState.PLAYING);
          _observer?.onRcvFirstIframe();
          break;
        case TXVodPlayEvent.PLAY_EVT_PLAY_END:
          _updatePlayerState(SuperPlayerState.END);
          // reset start time when end
          if (startPos > 0) {
            await setStartTime(0);
          }
          break;
        case TXVodPlayEvent.PLAY_EVT_PLAY_PROGRESS:
          dynamic progress = event[TXVodPlayEvent.EVT_PLAY_PROGRESS];
          dynamic duration = event[TXVodPlayEvent.EVT_PLAY_DURATION];
          if (null != progress) {
            currentDuration = progress.toDouble(); // Current time, converted unit: seconds
          }
          if (null != duration) {
            videoDuration = duration.toDouble(); // Total playback time, converted unit: seconds
          }
          if (videoDuration != 0) {
            _observer?.onPlayProgress(currentDuration, videoDuration, await getPlayableDuration());
            _addSimpleEvent(SuperPlayerViewEvent.onSuperPlayerProgress, params: event);
          }
          break;
        case TXVodPlayEvent.PLAY_EVT_CHANGE_RESOLUTION:
          _configVideoSize(event);
          _observer?.onResolutionChanged();
          break;
        case TXVodPlayEvent.EVENT_SUBTITLE_DATA:
          String subtitleDataStr = event[TXVodPlayEvent.EXTRA_SUBTITLE_DATA] ?? "";
          int? startPositionMs = event[TXVodPlayEvent.EXTRA_SUBTITLE_START_POSITION_MS];
          int? durationMs = event[TXVodPlayEvent.EXTRA_SUBTITLE_DURATION_MS];
          int? trackIndex = event[TXVodPlayEvent.EXTRA_SUBTITLE_TRACK_INDEX];
          currentSubtitleData = new TXVodSubtitleData(subtitleDataStr, startPositionMs, durationMs, trackIndex);
          _observer?.onSubtitleData(currentSubtitleData);
          break;
        case TXVodPlayEvent.VOD_PLAY_EVT_SELECT_TRACK_COMPLETE:
          int trackIndex = event[TXVodPlayEvent.EVT_KEY_SELECT_TRACK_INDEX];
          int errorCode = event[TXVodPlayEvent.EVT_KEY_SELECT_TRACK_ERROR_CODE];
          LogUtils.d(TAG, "SELECT_TRACK_COMPLETE trackIndex: ${trackIndex}, errorCode: ${errorCode}");
          break;
        case TXVodPlayEvent.VOD_PLAY_EVT_LOOP_ONCE_COMPLETE:
          // reset start time when once complete
          if (startPos > 0) {
            await setStartTime(0);
          }
          break;
      }
      // -100 is IOS valid view
      if (eventCode < 0 && eventCode != -100) {
        _observer?.onError(SuperPlayerCode.VOD_PLAY_FAIL, event.toString());
        _addSimpleEvent(SuperPlayerViewEvent.onSuperPlayerError, params: event);
        _updatePlayerState(SuperPlayerState.END);
      }
    });
    _vodNetEventListener = _vodPlayerController.onPlayerNetStatusBroadcast.listen((event) {
      _playerNetStatusStreamController.add(event);
    });
  }

  void _setLiveListener() {
    _livePlayEventListener?.cancel();
    _liveNetEventListener?.cancel();
    _livePlayEventListener = _livePlayerController.onPlayerEventBroadcast.listen((event) async {
      int eventCode = event['event'];
      switch (eventCode) {
        case TXVodPlayEvent.PLAY_EVT_VOD_PLAY_PREPARED: // vodPrepared
        case TXVodPlayEvent.PLAY_EVT_PLAY_BEGIN:
          _updatePlayerState(SuperPlayerState.PLAYING);
          break;
        case TXVodPlayEvent.PLAY_ERR_NET_DISCONNECT:
        case TXVodPlayEvent.PLAY_EVT_PLAY_END:
          stopPlay();
          if (eventCode == TXVodPlayEvent.PLAY_ERR_NET_DISCONNECT) {
            _observer?.onError(SuperPlayerCode.NET_ERROR, FSPLocal.current.txSpwNetWeak);
          } else {
            _observer?.onError(SuperPlayerCode.LIVE_PLAY_END, event[TXVodPlayEvent.EVT_DESCRIPTION]);
          }
          break;
        case TXVodPlayEvent.PLAY_EVT_PLAY_LOADING:
          _updatePlayerState(SuperPlayerState.LOADING);
          break;
        case TXVodPlayEvent.PLAY_EVT_RCV_FIRST_I_FRAME:
          _updatePlayerState(SuperPlayerState.PLAYING);
          _observer?.onRcvFirstIframe();
          break;
        case TXVodPlayEvent.PLAY_EVT_STREAM_SWITCH_SUCC:
          _observer?.onSwitchStreamEnd(true, SuperPlayerType.LIVE, currentQuality);
          break;
        case TXVodPlayEvent.PLAY_ERR_STREAM_SWITCH_FAIL:
          _observer?.onSwitchStreamEnd(false, SuperPlayerType.LIVE, currentQuality);
          break;
        case TXVodPlayEvent.PLAY_EVT_PLAY_PROGRESS:
          int progress = event[TXVodPlayEvent.EVT_PLAY_PROGRESS_MS];
          _maxLiveProgressTime = progress > _maxLiveProgressTime ? progress : _maxLiveProgressTime;
          _observer?.onPlayProgress(progress / 1000, _maxLiveProgressTime / 1000, await getPlayableDuration());
          break;
        case TXVodPlayEvent.PLAY_EVT_CHANGE_RESOLUTION:
          _configVideoSize(event);
          _observer?.onResolutionChanged();
          break;
      }
    });
  }

  void _onSelectTrackInfoWhenPrepare() async {
    // subtitle track info
    List<TXTrackInfo> subtitleTrackList = await _vodPlayerController.getSubtitleTrackInfo();
    TXTrackInfo? selectedSubtitleTrack;
    for (TXTrackInfo track in subtitleTrackList) {
      if (track.isSelected) {
        selectedSubtitleTrack = track;
        break;
      }
    }
    _updateSubtitleTrackList(subtitleTrackList, selectedSubtitleTrack);

    // audio track info
    List<TXTrackInfo> audioTrackList = await _vodPlayerController.getAudioTrackInfo();
    TXTrackInfo? selectedAudioTrack;
    for (TXTrackInfo track in audioTrackList) {
      if (track.isSelected) {
        selectedAudioTrack = track;
        break;
      }
    }
    _updateAudioTrackList(audioTrackList, selectedAudioTrack);
  }

  void _configVideoSize(Map<dynamic, dynamic> event) {
    int? eventVideoWidth = event[TXVodPlayEvent.EVT_VIDEO_WIDTH];
    int? eventVideoHeight = event[TXVodPlayEvent.EVT_VIDEO_HEIGHT];
    eventVideoWidth ??= event[TXVodPlayEvent.EVT_PARAM1];
    eventVideoHeight ??= event[TXVodPlayEvent.EVT_PARAM2];
    if (eventVideoWidth != null && eventVideoWidth != 0) {
      videoWidth = eventVideoWidth.toDouble();
    }
    if (eventVideoHeight != null && eventVideoHeight != 0) {
      videoHeight = eventVideoHeight.toDouble();
    }
  }

  Future<bool> isDownloaded() async {
    if (videoWidth == 0 || videoHeight == 0) {
      return false;
    } else {
      return await DownloadHelper.instance.isDownloaded(videoModel, videoWidth.toInt(), videoHeight.toInt());
    }
  }

  void startDownload() {
    DownloadHelper.instance.startDownloadBySize(videoModel, videoWidth.toInt(), videoHeight.toInt());
  }

  /// Play video.
  /// Starting from version 10.7, `playWithModel` has been changed to `playWithModelNeedLicence`,
  /// and you need to set the license through `SuperPlayerPlugin#setGlobalLicense` to play successfully.
  /// Otherwise, the playback will fail (black screen). The live streaming license, short video license,
  /// and video playback license can all be used. If you have not obtained the above licenses,
  /// you can [apply for a free trial license](https://cloud.tencent.com/act/event/License) to play normally,
  /// and you need to [purchase]
  /// (https://cloud.tencent.com/document/product/881/74588#.E8.B4.AD.E4.B9.B0.E5.B9.B6.E6.96.B0.E5.BB.BA.E6.AD.A3.E5.BC.8F.E7.89.88-license)
  /// the formal license.
  ///
  /// 播放视频.
  /// 10.7版本开始，playWithModel变更为playWithModelNeedLicence，需要通过 {@link SuperPlayerPlugin#setGlobalLicense} 设置 Licence 后方可成功播放，
  /// 否则将播放失败（黑屏），全局仅设置一次即可。直播 Licence、短视频 Licence 和视频播放 Licence 均可使用，若您暂未获取上述 Licence ，
  /// 可[快速免费申请测试版 Licence](https://cloud.tencent.com/act/event/License) 以正常播放，
  /// 正式版 License 需[购买]
  /// (https://cloud.tencent.com/document/product/881/74588#.E8.B4.AD.E4.B9.B0.E5.B9.B6.E6.96.B0.E5.BB.BA.E6.AD.A3.E5.BC.8F.E7.89.88-license)。
  Future<void> playWithModelNeedLicence(SuperPlayerModel videoModel) async {
    LogUtils.i(TAG, "widget version:${PlayerConstants.PLAYER_WIDGET_VERSION}");
    this.videoModel = videoModel;
    _playAction = videoModel.playAction;
    await stopPlay();
    if (_playAction == SuperPlayerModel.PLAY_ACTION_AUTO_PLAY || _playAction == SuperPlayerModel.PLAY_ACTION_PRELOAD) {
      await _playWithModelInner(videoModel);
    }
    _updatePlayerState(SuperPlayerState.START);
    _observer?.onPreparePlayVideo();
  }

  Future<void> _playWithModelInner(SuperPlayerModel videoModel) async {
    this.videoModel = videoModel;
    _playAction = videoModel.playAction;
    _updateImageSpriteAndKeyFrame(null, null);
    callResume = false;
    // Priority use URL to play
    if (videoModel.videoURL.isNotEmpty) {
      _playWithUrl(videoModel);
    } else if (videoModel.videoId != null && (videoModel.videoId!.fileId.isNotEmpty)) {
      _playWithField(videoModel);
    }
  }

  Future<void> _playWithField(SuperPlayerModel model) async {
    _setVodListener();
    await _vodPlayerController.setToken(null);
    _updatePlayerType(SuperPlayerType.VOD);
    if (_curViewId >=0) {
      setPlayerView(_curViewId);
    }
    _vodPlayerController.startVodPlayWithParams(TXPlayInfoParams(appId: model.appId,
        fileId: model.videoId!.fileId, psign: model.videoId!.psign));
    _observer?.onPlayProgress(0, model.duration.toDouble(), await getPlayableDuration());
    _updateImageSpriteAndKeyFrame(null, null);
  }

  void addSubTitle() {
    if (videoModel != null && videoModel!.subtitleSources.isNotEmpty) {
      for (FSubtitleSourceModel sourceModel in videoModel!.subtitleSources) {
        _vodPlayerController.addSubtitleSource(sourceModel.url, sourceModel.name, mimeType: sourceModel.mimeType);
      }
    }
  }

  void _updateImageSpriteAndKeyFrame(PlayImageSpriteInfo? spriteInfo, List<PlayKeyFrameDescInfo>? keyFrameInfo) {
    _observer?.onVideoImageSpriteAndKeyFrameChanged(spriteInfo, keyFrameInfo);
    if (null != spriteInfo) {
      _vodPlayerController.initImageSprite(spriteInfo.webVttUrl, spriteInfo.imageUrls);
    } else {
      _vodPlayerController.initImageSprite(null, null);
    }
    this.spriteInfo = spriteInfo;
    this.keyFrameInfo = keyFrameInfo;
  }

  /// select audio track
  Future<void> selectAudioTrack(TXTrackInfo trackInfo) async {
    if (playerType == SuperPlayerType.VOD) {
      List<TXTrackInfo> trackInfoList = await _vodPlayerController.getAudioTrackInfo();
      for (TXTrackInfo tempInfo in trackInfoList) {
        if(tempInfo.trackIndex == trackInfo.trackIndex) {
          _vodPlayerController.selectTrack(tempInfo.trackIndex);
        } else {
          _vodPlayerController.deselectTrack(tempInfo.trackIndex);
        }
      }
    }
  }

  /// select subtitle track
  Future<void> selectSubtitleTrack(TXTrackInfo trackInfo) async {
    if (playerType == SuperPlayerType.VOD) {
      List<TXTrackInfo> trackInfoList = await _vodPlayerController.getSubtitleTrackInfo();
      for (TXTrackInfo tempInfo in trackInfoList) {
        if(tempInfo.trackIndex == trackInfo.trackIndex) {
          _vodPlayerController.selectTrack(tempInfo.trackIndex);
        } else {
          _vodPlayerController.deselectTrack(tempInfo.trackIndex);
        }
      }
      // clear deselect subtitle
      if (trackInfo.trackIndex == SPConstants.VALID_SUBTITLE_INDEX) {
        currentSubtitleData = null;
        _observer?.onSubtitleData(currentSubtitleData);
      }
    }
  }

  Future<double> getPlayableDuration() async {
    return await _vodPlayerController.getPlayableDuration();
  }

  void _playWithUrl(SuperPlayerModel model) {
    List<VideoQuality> videoQualities = [];
    VideoQuality? defaultVideoQuality;
    String? videoUrl;
    if (model.multiVideoURLs.isNotEmpty) {
      int i = 0;
      for (SuperPlayerUrl superPlayerUrl in model.multiVideoURLs) {
        if (i == model.defaultPlayIndex) {
          videoUrl = superPlayerUrl.url;
        }
        videoQualities.add(VideoQuality(index: i++, title: superPlayerUrl.qualityName, url: superPlayerUrl.url));
      }
      defaultVideoQuality = videoQualities[model.defaultPlayIndex];
    } else {
      videoUrl = model.videoURL;
    }
    if (videoUrl == null || videoUrl.isEmpty) {
      _observer?.onError(SuperPlayerCode.PLAY_URL_EMPTY, FSPLocal.current.txSpwErrEmptyUrl);
      return;
    }
    bool isLivePlay = (_isRTMPPlay(videoUrl) || _isFLVPlay(videoUrl) || _isWebRtcPlay(videoUrl));
    _updatePlayerType(isLivePlay ? SuperPlayerType.LIVE : SuperPlayerType.VOD);
    if (isLivePlay) {
      _playLiveURL(videoUrl);
    } else {
      _playVodUrl(videoUrl);
    }
    _observer?.onPlayProgress(0, model.duration.toDouble(), 0);
    _updateVideoQualityList(videoQualities, defaultVideoQuality);
    _updateImageSpriteAndKeyFrame(null, null);
  }

  Future<void> _playVodUrl(String? url) async {
    if (null == url || url.isEmpty) {
      return;
    }
    _isMultiBitrateStream = url.contains(".m3u8");
    _currentPlayUrl = url;
    await _vodPlayerController.setStartTime(startPos);
    if (_playAction == SuperPlayerModel.PLAY_ACTION_PRELOAD) {
      await _vodPlayerController.setAutoPlay(isAutoPlay: false);
      _playAction = SuperPlayerModel.PLAY_ACTION_AUTO_PLAY;
    } else if (_playAction == SuperPlayerModel.PLAY_ACTION_AUTO_PLAY ||
        _playAction == SuperPlayerModel.PLAY_ACTION_MANUAL_PLAY) {
      await _vodPlayerController.setAutoPlay(isAutoPlay: true);
    }
    _setVodListener();
    if (_curViewId >= 0) {
      setPlayerView(_curViewId);
    }
    await _vodPlayerController.setToken(null);
    LogUtils.d(TAG, "playVodURL url:$url");
    await _vodPlayerController.startVodPlay(url);
  }

  /// pause video
  /// 暂停视频
  void pause() {
    // Related methods involving `_updatePlayerState` do not use asynchronous calls to avoid delayed updates to the `playerState`.
    if (playerType == SuperPlayerType.VOD) {
      if (isPrepared) {
        _vodPlayerController.pause();
      }
    } else {
      _livePlayerController.pause();
    }
    _updatePlayerState(SuperPlayerState.PAUSE);
    _needToPause = true;
  }

  /// resume play
  /// 继续播放视频
  void resume() {
    if (playerType == SuperPlayerType.VOD) {
      _needToResume = true;
      if (isPrepared) {
        _vodPlayerController.resume();
      }
    } else {
      _livePlayerController.resume();
    }
    callResume = true;
    _needToPause = false;
    _updatePlayerState(SuperPlayerState.PLAYING);
  }

  /// restart play
  /// 重新开始播放视频
  Future<void> reStart() async {
    if (playerType == SuperPlayerType.LIVE || playerType == SuperPlayerType.LIVE_SHIFT) {
      if (_isRTMPPlay(_currentPlayUrl) || _isWebRtcPlay(_currentPlayUrl) || _isFLVPlay(_currentPlayUrl)) {
        _playLiveURL(_currentPlayUrl);
      }
    } else {
      if (null != videoModel) {
        await playWithModelNeedLicence(videoModel!);
      }
    }
  }

  /// Play live streaming
  /// 播放直播URL
  void _playLiveURL(String url) async {
    _currentPlayUrl = url;
    _setLiveListener();
    if (_curViewId >= 0) {
      setPlayerView(_curViewId);
    }
    bool result = await _livePlayerController.startLivePlay(url);
    if (result) {
      _updatePlayerState(SuperPlayerState.PLAYING);
    } else {
      LogUtils.e(TAG, "playLiveURL videoURL:$url,result:$result");
    }
  }

  void _updatePlayerType(SuperPlayerType type) {
    if (playerType != type) {
      playerType = type;
      _observer?.onPlayerTypeChange(type);
      if (type == SuperPlayerType.VOD) {
        _livePlayerController.exitPictureInPictureMode();
      }
    }
  }

  /// Get the current controller being used
  TXPlayerController getCurrentController() {
    TXPlayerController controller;
    if (playerType == SuperPlayerType.VOD) {
      controller = _vodPlayerController;
    } else {
      controller = _livePlayerController;
    }
    return controller;
  }

  void _updatePlayerState(SuperPlayerState state) {
    playerState = state;
    print("_updatePlayerState:$state");
    switch (state) {
      case SuperPlayerState.START:
        break;
      case SuperPlayerState.INIT:
        _observer?.onPlayPrepare();
        break;
      case SuperPlayerState.PLAYING:
        _observer?.onPlayBegin(_getPlayName());
        _addSimpleEvent(SuperPlayerViewEvent.onSuperPlayerDidStart);
        break;
      case SuperPlayerState.PAUSE:
        _observer?.onPlayPause();
        break;
      case SuperPlayerState.LOADING:
        _observer?.onPlayLoading();
        break;
      case SuperPlayerState.END:
        _observer?.onPlayStop();
        _addSimpleEvent(SuperPlayerViewEvent.onSuperPlayerDidEnd);
        break;
    }
  }

  String _getPlayName() {
    String title = "";
    if (videoModel != null && null != videoModel!.title && videoModel!.title.isNotEmpty) {
      title = videoModel!.title;
    }
    return title;
  }

  void _updateVideoQualityList(List<VideoQuality>? qualityList, VideoQuality? defaultQuality) {
    currentQuality = defaultQuality;
    currentQualityList = qualityList;
    _observer?.onVideoQualityListChange(qualityList, defaultQuality);
  }

  void _updateSubtitleTrackList(List<TXTrackInfo>? subtitleTrackData, TXTrackInfo? selectedTrackInfo) {
    subtitleTrackInfoList = subtitleTrackData;
    currentSubtitleTrackInfo = selectedTrackInfo;
    _observer?.onSubtitleTrackListChange(subtitleTrackInfoList!, currentSubtitleTrackInfo);
  }

  void onSubtitleRenderModelChange(TXSubtitleRenderModel renderModel) {
    _currentSubtitleRenderModel = renderModel;
  }

  void onSelectSubtitleTrack(TXTrackInfo selectedTrack) {
    selectSubtitleTrack(selectedTrack);
    _updateSubtitleTrackList(subtitleTrackInfoList, selectedTrack);
  }

  void _updateAudioTrackList(List<TXTrackInfo>? audioTrackData, TXTrackInfo? selectedTrackInfo) {
    audioTrackInfoList = audioTrackData;
    currentAudioTrackInfo = selectedTrackInfo;
    _observer?.onAudioTrackListChange(audioTrackInfoList!, currentAudioTrackInfo);
  }

  void onSelectAudioTrack(TXTrackInfo selectedTrack) {
    if (selectedTrack.trackIndex == -1) {
      setMute(true);
    } else{
      setMute(false);
      selectAudioTrack(selectedTrack);
    }
    _updateAudioTrackList(audioTrackInfoList, selectedTrack);
  }

  void _addSimpleEvent(String event, {Map<dynamic, dynamic> params = const{}}) {
    Map<dynamic, dynamic> eventMap = {};
    eventMap.addAll(params);
    eventMap['event'] = event;
    _simpleEventStreamController.add(eventMap);
  }

  void _updatePlayerUIStatus(int status) {
    if (_playerUIStatus != status) {
      if (status == SuperPlayerUIStatus.FULLSCREEN_MODE) {
        _addSimpleEvent(SuperPlayerViewEvent.onStartFullScreenPlay);
      } else if (_playerUIStatus == SuperPlayerUIStatus.FULLSCREEN_MODE) {
        _addSimpleEvent(SuperPlayerViewEvent.onStopFullScreenPlay);
      }
      _playerUIStatus = status;
    }
  }

  /// whether it is the webrtc protocol
  /// 是否是webrtc协议
  bool _isWebRtcPlay(String? videoURL) {
    return null != videoURL && videoURL.startsWith("webrtc");
  }

  /// whether it is the RTMP protocol
  /// 是否是RTMP协议
  bool _isRTMPPlay(String? videoURL) {
    return null != videoURL && videoURL.startsWith("rtmp");
  }

  /// whether it is the HTTP-FLV protocol
  /// 是否是HTTP-FLV协议
  bool _isFLVPlay(String? videoURL) {
    return (null != videoURL && videoURL.startsWith("http://") || videoURL!.startsWith("https://")) &&
        videoURL.contains(".flv");
  }

  /// reset player status
  /// 重置播放器状态
  Future<void> resetPlayer() async {
    isPrepared = false;
    _needToResume = false;
    _needToPause = false;
    videoWidth = 0;
    videoHeight = 0;
    currentDuration = 0;
    videoDuration = 0;
    currentQuality = null;
    currentQualityList?.clear();
    currentAudioTrackInfo = null;
    audioTrackInfoList = null;
    currentSubtitleTrackInfo = null;
    subtitleTrackInfoList = null;
    currentSubtitleData = null;
    // cancel all listener
    _vodPlayEventListener?.cancel();
    _vodNetEventListener?.cancel();
    _livePlayEventListener?.cancel();
    _liveNetEventListener?.cancel();
    await _vodPlayerController.stop(isNeedClear: true);
    await _livePlayerController.stop(isNeedClear: true);
    await setMute(false);

    _updatePlayerState(SuperPlayerState.INIT);
  }

  Future<void> stopPlay() async {
    _updatePlayerState(SuperPlayerState.END);
    await resetPlayer();
  }

  /// Release the player. Once the player is released, it cannot be used again
  /// 释放播放器，播放器释放之后，将不能再使用
  Future<void> releasePlayer({bool? cancelListenerWhenPip}) async {
    // If in picture-in-picture mode, the player should not be released temporarily.
    if (!TXPipController.instance.isPlayerInPip(getCurrentController())) {
      await stopPlay();
      await _vodPlayerController.dispose();
      await _livePlayerController.dispose();
    } else if (null != cancelListenerWhenPip && cancelListenerWhenPip) {
      // cancel listener when enter pip
      _vodPlayEventListener?.cancel();
      _vodNetEventListener?.cancel();
      _livePlayEventListener?.cancel();
      _liveNetEventListener?.cancel();
    }
    // Remove the event listener for the widget.
    _observer?.onDispose();
  }

  /// return true: executed exit full screen and other operations, consumed the return event. return false: did not consume the event.
  /// return true : 执行了退出全屏等操作，消耗了返回事件  false：未消耗事件
  bool onBackPress() {
    if (_playerUIStatus == SuperPlayerUIStatus.FULLSCREEN_MODE) {
      _observer?.onSysBackPress();
      return true;
    }
    return false;
  }

  void _onBackTap() {
    _addSimpleEvent(SuperPlayerViewEvent.onSuperPlayerBackAction);
  }

  /// switch stream
  /// 切换清晰度
  void switchStream(VideoQuality videoQuality) async {
    currentQuality = videoQuality;
    if (playerType == SuperPlayerType.VOD) {
      if (videoQuality.url.isNotEmpty) {
        // url stream need manual seek
        double currentTime = await _vodPlayerController.getCurrentPlaybackTime();
        await _vodPlayerController.stop(isNeedClear: false);
        LogUtils.d(TAG, "onQualitySelect quality.url:${videoQuality.url}");
        await _vodPlayerController.setStartTime(currentTime);
        await _vodPlayerController.startVodPlay(videoQuality.url);
      } else {
        LogUtils.d(TAG, "setBitrateIndex quality.index:${videoQuality.index}");
        await _vodPlayerController.setBitrateIndex(videoQuality.index);
      }
      _observer?.onSwitchStreamStart(true, SuperPlayerType.VOD, videoQuality);
    } else {
      bool success = false;
      if (videoQuality.url.isNotEmpty) {
        int result = await _livePlayerController.switchStream(videoQuality.url);
        success = result >= 0;
      }
      _observer?.onSwitchStreamStart(success, SuperPlayerType.LIVE, videoQuality);
    }
  }

  /// Seek to the desired time point for playback.
  /// seek 到需要的时间点进行播放
  Future<void> seek(double progress) async {
    if (playerType == SuperPlayerType.VOD) {
      _needToPause = false;
      await _vodPlayerController.seek(progress);
      bool isPlaying = await _vodPlayerController.isPlaying();
      // resume when not playing.if isPlaying is null,not resume
      if (!isPlaying) {
        resume();
      }
    } else {
      _updatePlayerType(SuperPlayerType.LIVE_SHIFT);
      LogUtils.w(TAG, "live not support seek");
    }
    _observer?.onSeek(progress);
  }

  /// Configure the VOD player.
  /// 配置点播播放器
  Future<void> setPlayConfig(FTXVodPlayConfig config) async {
    vodConfig = config;
    await _vodPlayerController.setConfig(config);
  }

  /// Configure the Live player.
  /// 配置直播播放器
  Future<void> setLiveConfig(FTXLivePlayConfig config) async {
    liveConfig = config;
    await _livePlayerController.setConfig(config);
  }

  /// Enter picture-in-picture mode. To enter picture-in-picture mode, you need to adapt the interface for picture-in-picture mode.
  /// Android only supports models above 7.0.
  ///
  /// <h1>Due to Android system limitations, the size of the passed icon must not exceed 1MB, otherwise it will not be displayed.</h1>
  ///
  /// @param backIcon playIcon pauseIcon forwardIcon are icons for play rewind, play, pause, and fast forward.
  /// If they are assigned, the passed icons will be used; otherwise, the system default icons will be used.
  /// Only supports Flutter's local resource images. When passing, use the same method as using image resources in Flutter,
  /// for example: images/back_icon.png.
  ///
  /// 进入画中画模式，进入画中画模式，需要适配画中画模式的界面，安卓只支持7.0以上机型
  /// <h1> 由于android系统限制，传递的图标大小不得超过1M，否则无法显示 </h1>
  /// @param backIcon playIcon pauseIcon forwardIcon 为播放后退、播放、暂停、前进的图标，如果赋值的话，将会使用传递的图标，否则
  /// 使用系统默认图标，只支持flutter本地资源图片，传递的时候，与flutter使用图片资源一致，例如： images/back_icon.png
  Future<int> enterPictureInPictureMode(
      {String? backIcon, String? playIcon, String? pauseIcon, String? forwardIcon}) async {
    if (_playerUIStatus == SuperPlayerUIStatus.WINDOW_MODE) {
      return TXPipController.instance.enterPip(getCurrentController(), _context,
          backIconForAndroid: backIcon,
          playIconForAndroid: playIcon,
          pauseIconForAndroid: pauseIcon,
          forwardIconForAndroid: forwardIcon);
    }
    return TXVodPlayEvent.ERROR_PIP_CAN_NOT_ENTER;
  }

  /// Enable/disable hardware decoding playback.
  /// 开关硬解编码播放
  Future<void> enableHardwareDecode(bool enable) async {
    _isOpenHWAcceleration = enable;
    if (playerType == SuperPlayerType.VOD) {
      await _vodPlayerController.enableHardwareDecode(enable);
      if (playerState != SuperPlayerState.END) {
        _changeHWAcceleration = true;
        _seekPos = await _vodPlayerController.getCurrentPlaybackTime();
        LogUtils.d(TAG, "seek pos $_seekPos");
        resetPlayer();
        // When the `protocol` is empty, it means that the current video playback is a URL
        if (null != videoModel) {
          _playWithModelInner(videoModel!);
        }
      }
    } else {
      await _vodPlayerController.enableHardwareDecode(enable);
      if (null != videoModel) {
        _playWithModelInner(videoModel!);
      }
    }
  }

  /// Set whether to mute.
  /// 设置是否静音
  Future<void> setMute(bool mute) async {
    isMute = mute;
    if (playerType == SuperPlayerType.VOD) {
      return await _vodPlayerController.setMute(mute);
    } else {
      return await _livePlayerController.setMute(mute);
    }
  }

  /// Set whether to loop playback. This is not supported for live streaming.
  /// 设置是否循环播放，不支持直播时调用
  Future<void> setLoop(bool loop) async {
    if (playerType == SuperPlayerType.VOD) {
      isLoop = loop;
      return await _vodPlayerController.setLoop(loop);
    }
  }

  /// set renderView
  /// 设置渲染 view
  Future<void> setPlayerView(int viewId) async {
    _curViewId = viewId;
    if (playerType == SuperPlayerType.VOD) {
      await _vodPlayerController.setPlayerView(viewId);
    } else {
      await _livePlayerController.setPlayerView(viewId);
    }
  }

  /// Set the playback start time.
  /// 设置播放开始时间
  Future<void> setStartTime(double startTime) async {
    if (playerType == SuperPlayerType.VOD) {
      startPos = startTime;
      return await _vodPlayerController.setStartTime(startTime);
    }
  }

  Future<void> setPlayRate(double rate) async {
    currentPlayRate = rate;
    _vodPlayerController.setRate(rate);
  }

  /// Get the current player state.
  /// 获得当前播放器状态
  SuperPlayerState getPlayerState() {
    return playerState;
  }
}

class FullScreenController {
  bool _isInFullScreenUI = false;
  int currentOrientation = TXVodPlayEvent.ORIENTATION_PORTRAIT_UP;
  Function? onEnterFullScreenUI;
  Function? onExitFullScreenUI;

  FullScreenController();

  Future<void> switchToOrientation(int orientationDirection) async {
    if (currentOrientation != orientationDirection) {
      forceSwitchOrientation(orientationDirection);
    }
  }

  Future<void> forceSwitchOrientation(int orientationDirection) async {
    currentOrientation = orientationDirection;
    if (orientationDirection == TXVodPlayEvent.ORIENTATION_PORTRAIT_UP) {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge, overlays: SystemUiOverlay.values);
      await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
      exitFullScreen();
    } else if (orientationDirection == TXVodPlayEvent.ORIENTATION_LANDSCAPE_RIGHT) {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      await SystemChrome.setPreferredOrientations(Platform.isIOS ? [DeviceOrientation.landscapeRight] : [DeviceOrientation.landscapeLeft]);
      enterFullScreen();
    } else if (orientationDirection == TXVodPlayEvent.ORIENTATION_PORTRAIT_DOWN) {
    } else if (orientationDirection == TXVodPlayEvent.ORIENTATION_LANDSCAPE_LEFT) {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      await SystemChrome.setPreferredOrientations(Platform.isIOS ? [DeviceOrientation.landscapeLeft] : [DeviceOrientation.landscapeRight]);
      enterFullScreen();
    }
  }

  void enterFullScreen() {
    if (!_isInFullScreenUI) {
      _isInFullScreenUI = true;
      onEnterFullScreenUI?.call();
    }
  }

  void exitFullScreen() {
    if (_isInFullScreenUI) {
      _isInFullScreenUI = false;
      onExitFullScreenUI?.call();
    }
  }

  void setListener(Function enterFullScreen, Function exitFullScreen) {
    onExitFullScreenUI = exitFullScreen;
    onEnterFullScreenUI = enterFullScreen;
  }
}

