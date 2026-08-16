/// SketchIt play view: live canvas + guess input.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../game.dart';
import '../../widgets/sketch_painter.dart';


class SketchPlayBody extends StatefulWidget {
  const SketchPlayBody({super.key, required this.game});

  final Game game;

  @override
  State<SketchPlayBody> createState() => _SketchPlayBodyState();
}

class _SketchPlayBodyState extends State<SketchPlayBody> {
  final TextEditingController _guess = TextEditingController();
  final List<Offset> _buf = [];
  Timer? _flush;
  String? _strokeId;

  Game get game => widget.game;

  @override
  void initState() {
    super.initState();
    game.addListener(_onGame);
  }

  @override
  void dispose() {
    game.removeListener(_onGame);
    _flush?.cancel();
    _guess.dispose();
    super.dispose();
  }

  void _onGame() => setState(() {});

  bool get _isDrawer => game.meId == game.sketch?.drawer;

  void _sendBuf(double color, double width) {
    if (_buf.isEmpty || _strokeId == null) return;
    // interleaved [x1, y1, x2, y2, ...] - the one canonical point format;
    // flattened-halves deltas used to break merged multi-point strokes
    game.sketch?.draw(
      color,
      width,
      [for (final p in _buf) ...[p.dx, p.dy]],
      id: _strokeId,
    );
    _buf.clear();
  }

  void _startStroke(Offset p, Size size) {
    if (!_isDrawer) return;
    _flush?.cancel();
    _strokeId = DateTime.now().microsecondsSinceEpoch.toString();
    _buf
      ..clear()
      ..add(Offset(
        (p.dx / size.width).clamp(0.0, 1.0),
        (p.dy / size.height).clamp(0.0, 1.0),
      ));
    _sendBuf(_color, _width);
    _flush = Timer.periodic(const Duration(milliseconds: 90), (_) {
      _sendBuf(_color, _width);
    });
  }

  void _extendStroke(Offset p, Size size) {
    if (!_isDrawer || _strokeId == null) return;
    final np = Offset(
      (p.dx / size.width).clamp(0.0, 1.0),
      (p.dy / size.height).clamp(0.0, 1.0),
    );
    // skip near-duplicate points: they feed noise to the stroke builder
    if (_buf.isNotEmpty && (np - _buf.last).distance < 0.004) return;
    _buf.add(np);
    // the painter renders the live buffer at full pointer rate; committed
    // strokes are outline-cached, so this repaint is cheap
    setState(() {});
  }

  void _endStroke() {
    _flush?.cancel();
    _flush = null;
    if (_strokeId == null) return;
    _sendBuf(_color, _width);
    _strokeId = null;
    _buf.clear();
  }

  double _color = 0xFF1D1D1D;
  double _width = 0.008;
  static const List<double> _widths = [0.004, 0.008, 0.015];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final g = game;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Text(
            _isDrawer
                ? 'DRAW: ${g.sketch!.word.toUpperCase()}'
                : 'ANSWER: ${g.sketch!.word.toUpperCase()}',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleLarge?.copyWith(
              color: _isDrawer ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        Expanded(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900, maxHeight: 520),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: Card(
                  clipBehavior: Clip.antiAlias,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final size = Size(
                        constraints.maxWidth,
                        constraints.maxHeight,
                      );
                      return Semantics(
                        label: 'drawing canvas',
                        child: GestureDetector(
                          onPanDown: _isDrawer
                              ? (d) => _startStroke(d.localPosition, size)
                              : null,
                          onPanUpdate: _isDrawer
                              ? (d) => _extendStroke(d.localPosition, size)
                              : null,
                          onPanEnd: _isDrawer ? (_) => _endStroke() : null,
                          onPanCancel: _isDrawer ? _endStroke : null,
                          child: CustomPaint(
                            size: size,
                            painter: SketchPainter(
                              strokes: g.sketch!.strokes,
                              rev: g.sketch!.rev,
                              liveStrokeId: _strokeId,
                              livePts: _buf.isEmpty
                                  ? null
                                  : [
                                      for (final p in _buf) ...[p.dx, p.dy],
                                    ],
                              liveColor: _color,
                              liveWidth: _width,
                            ),
                            child: const SizedBox.expand(),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(8),
          child: _isDrawer
              ? Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (final c in const [
                      0xFF1D1D1D, 0xFFF44336, 0xFF4CAF50, 0xFF2196F3, 0xFF9C27B0, 0xFFFF9800,
                    ])
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        child: InkWell(
                          onTap: () => setState(() => _color = c.toDouble()),
                          child: Container(
                            width: 26,
                            height: 26,
                            decoration: BoxDecoration(
                              color: Color(c),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: _color == c.toDouble()
                                    ? theme.colorScheme.primary
                                    : Colors.transparent,
                                width: 3,
                              ),
                            ),
                          ),
                        ),
                      ),
                    const SizedBox(width: 12),
                    for (final w in _widths)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        child: InkWell(
                          onTap: () => setState(() => _width = w),
                          child: Container(
                            width: 26,
                            height: 26,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: _width == w
                                    ? theme.colorScheme.primary
                                    : theme.colorScheme.outline,
                                width: _width == w ? 3 : 1,
                              ),
                            ),
                            child: Container(
                              width: w * 700,
                              height: w * 700,
                              decoration: BoxDecoration(
                                color: theme.colorScheme.onSurface,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                        ),
                      ),
                    const SizedBox(width: 12),
                    OutlinedButton.icon(
                      onPressed: () {
                        game.sketch?.clearCanvas();
                        setState(() {});
                      },
                      icon: const Icon(Icons.cleaning_services, size: 18),
                      label: const Text('CLEAR'),
                    ),
                  ],
                )
              : Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _guess,
                        onSubmitted: _submitGuess,
                        decoration: InputDecoration(
                          hintText: 'type your guess...',
                          isDense: true,
                          border: const OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: () => _submitGuess(_guess.text),
                      child: const Text('GUESS'),
                    ),
                  ],
                ),
        ),
      ],
    );
  }

  void _submitGuess(String text) {
    if (text.trim().isEmpty) return;
    game.sketch?.guess(text);
    _guess.clear();
  }
}
