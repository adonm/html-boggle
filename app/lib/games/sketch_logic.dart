/// SketchIt (pictionary): the round starter deals a secret word and picks
/// the drawer; strokes stream as id'd deltas; a host-arbitrated exact guess
/// scores for both the guesser and the drawer and ends the round.
library;

import 'game_logic.dart';
import 'turn_game.dart';

class SketchLogic extends GameLogic {
  SketchLogic(super.host);

  @override
  String get wireName => 'sketchit';

  String word = '';
  String drawer = '';
  bool solved = false;
  final List<Map<String, dynamic>> strokes = [];

  @override
  String get startToast => 'Round ${host.round} - start drawing!';

  @override
  void populateStart(Map<String, dynamic> msg) {
    word = host.finder.randomWord(host.rng, 4, 9) ?? 'cat';
    drawer = host.sortedPlayers[(host.round - 1) % host.players.length].id;
    strokes.clear();
    solved = false;
    host.deadline =
        DateTime.now().add(const Duration(seconds: 90));
    msg['word'] = word;
    msg['drawer'] = drawer;
  }

  @override
  void applyStart(Map<String, dynamic> m) {
    word = (m['word'] as String?) ?? '';
    drawer = (m['drawer'] as String?) ?? '';
    strokes.clear();
    solved = false;
  }

  @override
  void onMessage(String type, Map<String, dynamic> m, String from) {
    switch (type) {
      case 'sketchStroke':
        _onStroke(m, from);
      case 'sketchClear':
        if (host.phase != Phase.play || from != drawer) return;
        strokes.clear();
      case 'sketchGuess':
        _onGuess(m, from);
      case 'sketchSolved':
        _onSolved(m);
    }
  }

  @override
  Map<String, dynamic> stateJson() => {
        'sketchWord': word,
        'sketchDrawer': drawer,
        'sketchSolved': solved,
      };

  @override
  void adoptState(Map<String, dynamic> m) {
    word = adoptNonEmpty(word, m['sketchWord']);
    drawer = adoptNonEmpty(drawer, m['sketchDrawer']);
    // sticky within a round (start resets it)
    solved = adoptStickyBool(solved, m['sketchSolved']);
  }

  @override
  Map<String, dynamic> debugJson() => {
        'sketchWord': word,
        'sketchDrawer': drawer,
        'sketchSolved': solved,
        'sketchStrokes': strokes.length,
      };

  @override
  void reset() {
    word = '';
    drawer = '';
    solved = false;
    strokes.clear();
  }

  // --------------------------------------------------------------- drawing

  /// Drawer: append a stroke or a delta of points (canvas coords 0..1).
  /// A new stroke sends [id] + start point; later deltas reuse the id and
  /// only carry the new points so the wire stays light while drawing.
  void draw(double color, double width, List<double> pts, {String? id}) {
    if (host.phase != Phase.play || host.meId != drawer) return;
    if (id == null) {
      strokes.add({'color': color, 'width': width, 'pts': pts});
      if (strokes.length > 500) strokes.removeAt(0);
      host.send({
        't': 'sketchStroke',
        'node': host.meId,
        'stroke': {'color': color, 'width': width, 'pts': pts},
      });
      return;
    }
    final existing = strokes.where((x) => x['id'] == id).firstOrNull;
    if (existing != null) {
      (existing['pts'] as List).addAll(pts);
    } else {
      strokes.add({'id': id, 'color': color, 'width': width, 'pts': pts});
    }
    host.send({
      't': 'sketchStroke',
      'node': host.meId,
      'stroke': {'id': id, 'color': color, 'width': width, 'pts': pts},
    });
  }

  /// Drawer: clear the canvas.
  void clearCanvas() {
    if (host.phase != Phase.play || host.meId != drawer) return;
    strokes.clear();
    host.send({'t': 'sketchClear', 'node': host.meId});
  }

  /// Guesser: send a guess.
  void guess(String text) {
    if (host.phase != Phase.play) return;
    if (host.meId == drawer || solved) return;
    host.send({
      't': 'sketchGuess',
      'node': host.meId,
      'name': host.myName,
      'text': text.trim(),
    });
  }

  void _onStroke(Map<String, dynamic> m, String from) {
    if (host.phase != Phase.play || from != drawer) return;
    final stroke = m['stroke'];
    if (stroke is! Map) return;
    final s = stroke.cast<String, dynamic>();
    final id = s['id'];
    final pts = s['pts'];
    if (id is String && pts is List) {
      final existing = strokes.where((x) => x['id'] == id).firstOrNull;
      if (existing != null) {
        (existing['pts'] as List).addAll(pts);
      } else {
        strokes.add(s);
      }
      if (strokes.length > 500) strokes.removeAt(0);
    }
  }

  void _onGuess(Map<String, dynamic> m, String from) {
    if (host.phase != Phase.play) return;
    if (from == drawer || solved) return;
    final guess = ((m['text'] as String?) ?? '').trim().toLowerCase();
    if (guess != word.toLowerCase()) return;
    if (!host.isHost) return; // the leader arbitrates the win
    solved = true;
    final drawerP = host.players.where((p) => p.id == drawer).firstOrNull;
    final guesser = host.players.where((p) => p.id == from).firstOrNull;
    drawerP?.score++;
    guesser?.score++;
    host.endRound();
    host.sfx('win');
    host.send({
      't': 'sketchSolved',
      'node': host.meId,
      'word': word,
      'drawer': drawer,
      'guesser': from,
    });
    host.showToast('${guesser?.name ?? 'Someone'} guessed "$word"!');
  }

  void _onSolved(Map<String, dynamic> m) {
    solved = true;
    final w = m['word'];
    if (w is String && w.isNotEmpty) word = w;
    if (!host.isHost) {
      host.players
          .where((p) => p.id == (m['drawer'] as String?))
          .firstOrNull
          ?.score++;
      host.players
          .where((p) => p.id == (m['guesser'] as String?))
          .firstOrNull
          ?.score++;
    }
    host.endRound();
  }
}
