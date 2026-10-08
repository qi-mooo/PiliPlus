import 'package:PiliPlus/models/common/video/video_type.dart';
import 'package:PiliPlus/models/common/video/source_type.dart';
import 'package:PiliPlus/models_new/pgc/pgc_info_model/episode.dart' as pgc;
import 'package:PiliPlus/models_new/pgc/pgc_info_model/result.dart';
import 'package:PiliPlus/models_new/video/video_detail/episode.dart';
import 'package:PiliPlus/models_new/video/video_detail/page.dart';
import 'package:PiliPlus/models_new/video/video_detail/section.dart';
import 'package:PiliPlus/models_new/video/video_detail/ugc_season.dart';
import 'package:PiliPlus/pages/video/controller.dart';
import 'package:PiliPlus/pages/video/introduction/pgc/controller.dart';
import 'package:PiliPlus/pages/video/introduction/ugc/controller.dart';
import 'package:PiliPlus/plugin/pl_player/controller.dart';
import 'package:PiliPlus/plugin/pl_player/models/play_repeat.dart';
import 'package:PiliPlus/services/lan_cast/page_settings.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:hive_ce/hive.dart';

class _Settings extends Fake implements Box<dynamic> {
  final _values = <dynamic, dynamic>{};
  @override
  dynamic get(dynamic key, {dynamic defaultValue}) =>
      _values[key] ?? defaultValue;
  @override
  Future<void> put(dynamic key, dynamic value) async {
    _values[key] = value;
  }
}

class _Ugc extends UgcIntroController {
  _Ugc(this.video);
  final VideoDetailController video;
  final selected = <BaseEpisodeItem>[];
  @override
  VideoDetailController get videoDetailCtr => video;
  @override
  Future<bool> onChangeEpisode(
    BaseEpisodeItem episode, {
    bool isStein = false,
  }) async {
    selected.add(episode);
    cid.value = episode.cid!;
    return true;
  }
}

class _Pgc extends PgcIntroController {
  _Pgc(this.video);
  final VideoDetailController video;
  final selected = <BaseEpisodeItem>[];
  @override
  VideoDetailController get videoDetailCtr => video;
  @override
  Future<bool> onChangeEpisode(BaseEpisodeItem episode) async {
    selected.add(episode);
    video.cid.value = episode.cid!;
    return true;
  }
}

class _TransitionVideo extends VideoDetailController {
  bool queried = false;
  @override
  bool get showReply => false;
  @override
  void makeHeartBeat() {}
  @override
  void updateMediaListHistory(int aid) {}
  @override
  void onReset({bool isStein = false}) {}
  @override
  Future<void> queryVideoUrl({
    bool fromReset = false,
    bool autoFullScreenFlag = false,
  }) async {
    queried = true;
  }
}

class _ChangingUgc extends UgcIntroController {
  _ChangingUgc(this.video);
  final VideoDetailController video;
  @override
  VideoDetailController get videoDetailCtr => video;
  @override
  Future<void> queryVideoIntro() async {}
  @override
  Future<void> queryOnlineTotal() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    GStorage.setting = _Settings();
    GStorage.video = _Settings();
    GStorage.localCache = _Settings();
  });
  tearDown(() {
    PlPlayerController.instance?.clearReceivingCast();
  });

  test('receiver can leave a finished API list for related autoplay in the same page', () async {
    final video = _TransitionVideo()
      ..args = {}
      ..isPlayAll = true
      ..sourceType = SourceType.fav
      ..bvid = 'BV1xx411c7mD'
      ..aid = 1
      ..cid = 10.obs
      ..cover = ''.obs;
    final player = video.plPlayerController;
    player
      ..receivingCastMediaKey = player.castMediaKey
      ..receivingCastRepeat = PlayRepeat.autoPlayRelated;
    final intro = _ChangingUgc(video)
      ..bvid = video.bvid
      ..cid = 10.obs
      ..hasLater = false.obs;
    expect(
      await intro.onChangeEpisode(
        BaseEpisodeItem(
          aid: 2,
          bvid: 'BV17x411w7KC',
          cid: 20,
          title: '相关推荐',
        ),
      ),
      isTrue,
    );
    expect(video.queried, isTrue);
    expect(video.isPlayAll, isFalse);
    expect(video.sourceType, SourceType.normal);
    expect(video.args['title'], '相关推荐');
    expect(
      player.updateReceivingCastSource('ugc:2:20:null', network: true),
      isTrue,
    );
    expect(player.receivingCastRepeat, PlayRepeat.autoPlayRelated);
  });

  test(
    'receiver uses its own part order and loops only when selected',
    () async {
      final video = VideoDetailController()..isPlayAll = false;
      final player = video.plPlayerController;
      player.receivingCastMediaKey = player.castMediaKey;
      final intro = _Ugc(video)..cid = 10.obs;
      intro.videoDetail.value.pages = [Part(cid: 10), Part(cid: 20)];
      final settings = LanCastPageSettings(player);
      await settings.apply('repeat', 'listOrder');
      expect(intro.nextPlay(), isTrue);
      expect(intro.selected.single.cid, 20);
      expect(intro.nextPlay(), isFalse);
      await settings.apply('repeat', 'listCycle');
      expect(intro.nextPlay(), isTrue);
      expect(intro.selected.last.cid, 10);
      expect(player.playRepeat, PlayRepeat.listCycle);
    },
  );

  test(
    'receiver season ordering and PGC episodes use existing nextPlay logic',
    () async {
      final video = VideoDetailController()
        ..isPlayAll = false
        ..videoType = VideoType.pgc
        ..cid = 10.obs;
      final player = video.plPlayerController;
      player.receivingCastMediaKey = player.castMediaKey;
      final settings = LanCastPageSettings(player);
      await settings.apply('repeat', 'listCycle');
      final ugc = _Ugc(video)..cid = 20.obs;
      ugc.videoDetail.value.ugcSeason = UgcSeason(
        sections: [
          SectionItem(episodes: [EpisodeItem(cid: 10), EpisodeItem(cid: 20)]),
        ],
      );
      expect(ugc.nextPlay(), isTrue);
      expect(ugc.selected.single.cid, 10);

      final intro = _Pgc(video)
        ..pgcItem = PgcInfoModel(
          episodes: [pgc.EpisodeItem(cid: 10), pgc.EpisodeItem(cid: 20)],
        );
      expect(intro.nextPlay(), isTrue);
      expect(intro.selected.single.cid, 20);
      expect(intro.nextPlay(), isTrue);
      expect(intro.selected.last.cid, 10);
      await settings.apply('repeat', 'listOrder');
      expect(intro.nextPlay(), isTrue);
      expect(intro.nextPlay(), isFalse);
    },
  );
}
