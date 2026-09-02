import 'dart:async';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/recipe.dart';
import '../services/api_client.dart';
import '../theme/app_theme.dart';

/// 烹饪模式：全屏逐屏显示步骤大字 + 计时器 + 服务端 Edge TTS 朗读
/// （对齐网页端 detail.html cookMode：5 个音色、语速/音调、自动朗读）
class CookModeScreen extends StatefulWidget {
  final ApiClient api;
  final String recipeTitle;
  final List<RecipeStep> steps;

  const CookModeScreen({
    super.key,
    required this.api,
    required this.recipeTitle,
    required this.steps,
  });

  @override
  State<CookModeScreen> createState() => _CookModeScreenState();
}

class _CookModeScreenState extends State<CookModeScreen> {
  static const _prefsVoice = 'tts_voice';
  static const _prefsRate = 'tts_rate';
  static const _prefsPitch = 'tts_pitch';
  static const _prefsAuto = 'tts_auto';
  static const _maxTtsChars = 480;

  final PageController _pageController = PageController();
  final AudioPlayer _player = AudioPlayer();

  int _stepIndex = 0;
  Timer? _ticker;
  int _elapsedSeconds = 0;
  bool _timerRunning = false;

  String _voice = 'xiaoxiao';
  double _rate = 1.0;
  double _pitch = 1.0;
  bool _autoRead = false;
  List<({String key, String label})> _voices = const [];
  bool _loadingVoice = false;
  bool _speaking = false;

  @override
  void initState() {
    super.initState();
    _startTimer();
    _loadPrefs();
    _loadVoices();
    _player.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _speaking = false);
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _pageController.dispose();
    _player.dispose();
    super.dispose();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _voice = prefs.getString(_prefsVoice) ?? 'xiaoxiao';
      _rate = prefs.getDouble(_prefsRate) ?? 1.0;
      _pitch = prefs.getDouble(_prefsPitch) ?? 1.0;
      _autoRead = prefs.getBool(_prefsAuto) ?? false;
    });
    if (_autoRead) {
      _speakCurrentStep();
    }
  }

  Future<void> _savePrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsVoice, _voice);
    await prefs.setDouble(_prefsRate, _rate);
    await prefs.setDouble(_prefsPitch, _pitch);
    await prefs.setBool(_prefsAuto, _autoRead);
  }

  Future<void> _loadVoices() async {
    try {
      final voices = await widget.api.fetchTtsVoices();
      if (!mounted) return;
      setState(() {
        _voices = voices;
        if (voices.isNotEmpty && !voices.any((v) => v.key == _voice)) {
          _voice = voices.first.key;
        }
      });
    } catch (_) {
      // 音色列表拿不到也不影响使用（有默认值）
    }
  }

  void _startTimer() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_timerRunning && mounted) {
        setState(() => _elapsedSeconds++);
      }
    });
    _timerRunning = true;
  }

  String get _timerText {
    final m = (_elapsedSeconds ~/ 60).toString().padLeft(2, '0');
    final s = (_elapsedSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  RecipeStep get _currentStep => widget.steps[_stepIndex];

  String get _stepText {
    final desc = _currentStep.description.trim();
    return desc.length > _maxTtsChars ? desc.substring(0, _maxTtsChars) : desc;
  }

  Future<void> _speakCurrentStep() async {
    if (_speaking) {
      await _player.stop();
      setState(() => _speaking = false);
      return;
    }
    final text = _stepText;
    if (text.isEmpty) return;
    setState(() => _loadingVoice = true);
    try {
      final bytes = await widget.api.synthesizeTts(
        text: text,
        voice: _voice,
        rate: _rate,
        pitch: _pitch,
      );
      if (!mounted) return;
      await _player.stop();
      await _player.play(BytesSource(Uint8List.fromList(bytes)));
      if (mounted) setState(() => _speaking = true);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('语音合成失败，请检查服务器连接')),
      );
    } finally {
      if (mounted) setState(() => _loadingVoice = false);
    }
  }

  Future<void> _openSettings() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('朗读设置',
                    style: AppTypography.h3.copyWith(
                      color: Theme.of(sheetContext).colorScheme.onSurface,
                    )),
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _autoRead,
                  onChanged: (v) {
                    setSheetState(() => _autoRead = v);
                    setState(() => _autoRead = v);
                    _savePrefs();
                  },
                  title: const Text('自动朗读当前步骤'),
                ),
                if (_voices.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text('音色列表加载中…'),
                  )
                else
                  RadioGroup<String>(
                    groupValue: _voice,
                    onChanged: (value) {
                      setSheetState(() => _voice = value ?? _voice);
                      setState(() => _voice = value ?? _voice);
                      _savePrefs();
                    },
                    child: Column(
                      children: _voices
                          .map((v) => RadioListTile<String>(
                                contentPadding: EdgeInsets.zero,
                                value: v.key,
                                title: Text(v.label),
                              ))
                          .toList(),
                    ),
                  ),
                Row(
                  children: [
                    const Text('语速'),
                    Expanded(
                      child: Slider(
                        value: _rate,
                        min: 0.6,
                        max: 1.4,
                        divisions: 8,
                        label: _rate.toStringAsFixed(1),
                        onChanged: (v) {
                          setSheetState(() => _rate = v);
                          setState(() => _rate = v);
                          _savePrefs();
                        },
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    const Text('音调'),
                    Expanded(
                      child: Slider(
                        value: _pitch,
                        min: 0.6,
                        max: 1.4,
                        divisions: 8,
                        label: _pitch.toStringAsFixed(1),
                        onChanged: (v) {
                          setSheetState(() => _pitch = v);
                          setState(() => _pitch = v);
                          _savePrefs();
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _goStep(int index) {
    if (index < 0 || index >= widget.steps.length) return;
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: Text(widget.recipeTitle, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: '朗读设置',
            icon: const Icon(Icons.tune),
            onPressed: _openSettings,
          ),
          IconButton(
            tooltip: _speaking ? '停止朗读' : '朗读本步',
            icon: _loadingVoice
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : Icon(_speaking ? Icons.stop : Icons.volume_up),
            onPressed: _loadingVoice ? null : _speakCurrentStep,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Row(
              children: [
                Text(
                  '第 ${_stepIndex + 1} / ${widget.steps.length} 步',
                  style: AppTypography.h3.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const Spacer(),
                const Icon(Icons.timer_outlined, size: 20),
                const SizedBox(width: 6),
                Text(
                  _timerText,
                  style: AppTypography.h3.copyWith(
                    color: theme.colorScheme.onSurface,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: _timerRunning ? '暂停计时' : '继续计时',
                  icon: Icon(
                    _timerRunning ? Icons.pause_circle_outline : Icons.play_circle_outline,
                  ),
                  onPressed: () =>
                      setState(() => _timerRunning = !_timerRunning),
                ),
                IconButton(
                  tooltip: '清零',
                  icon: const Icon(Icons.restart_alt, size: 20),
                  onPressed: () => setState(() => _elapsedSeconds = 0),
                ),
              ],
            ),
          ),
          Expanded(
            child: PageView.builder(
              controller: _pageController,
              itemCount: widget.steps.length,
              onPageChanged: (index) {
                setState(() => _stepIndex = index);
                if (_speaking) {
                  _player.stop();
                  setState(() => _speaking = false);
                }
                if (_autoRead) {
                  _speakCurrentStep();
                }
              },
              itemBuilder: (context, index) {
                final step = widget.steps[index];
                return Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 28),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 56,
                          height: 56,
                          alignment: Alignment.center,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppColors.primary,
                          ),
                          child: Text(
                            '${index + 1}',
                            style: AppTypography.h2.copyWith(
                              color: AppColors.onPrimary,
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        Text(
                          step.description,
                          textAlign: TextAlign.center,
                          style: AppTypography.h2.copyWith(
                            color: theme.colorScheme.onSurface,
                            height: 1.6,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _stepIndex == 0
                          ? null
                          : () => _goStep(_stepIndex - 1),
                      icon: const Icon(Icons.chevron_left),
                      label: const Text('上一步'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _stepIndex == widget.steps.length - 1
                          ? null
                          : () => _goStep(_stepIndex + 1),
                      icon: const Icon(Icons.chevron_right),
                      label: const Text('下一步'),
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
}
