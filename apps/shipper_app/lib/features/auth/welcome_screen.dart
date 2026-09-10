import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wetruck_core/wetruck_core.dart';

import 'widgets/language_switcher.dart';
import 'widgets/login_sheet.dart';

/// Minimal swipeable onboarding shown when the app opens (signed out): a brand
/// intro slide followed by three feature slides, with a persistent Login button.
class WelcomeScreen extends ConsumerStatefulWidget {
  const WelcomeScreen({super.key});

  @override
  ConsumerState<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends ConsumerState<WelcomeScreen> {
  final _controller = PageController();
  int _page = 0;

  static const _slides = <_Slide>[
    _Slide(
      isBrand: true,
      titleKey: 'auth.welcome.intro_title',
      descKey: 'auth.welcome.intro_desc',
    ),
    _Slide(
      icon: Icons.local_shipping_outlined,
      titleKey: 'auth.welcome.slide1_title',
      descKey: 'auth.welcome.slide1_desc',
    ),
    _Slide(
      icon: Icons.gavel_outlined,
      titleKey: 'auth.welcome.slide2_title',
      descKey: 'auth.welcome.slide2_desc',
    ),
    _Slide(
      icon: Icons.location_on_outlined,
      titleKey: 'auth.welcome.slide3_title',
      descKey: 'auth.welcome.slide3_desc',
    ),
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(localeProvider);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: scheme.surface,
      body: SafeArea(
        child: Column(
          children: [
            // Minimal header: just the language switcher (the brand lives on
            // the first slide).
            const Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: EdgeInsets.fromLTRB(0, 8, 12, 0),
                child: LanguageSwitcher(),
              ),
            ),

            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _slides.length,
                onPageChanged: (i) => setState(() => _page = i),
                itemBuilder: (context, i) => _SlideView(slide: _slides[i]),
              ),
            ),

            // Animated page indicator.
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < _slides.length; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 260),
                    curve: Curves.easeOutCubic,
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    height: 7,
                    width: i == _page ? 22 : 7,
                    decoration: BoxDecoration(
                      color: i == _page
                          ? scheme.primary
                          : scheme.outlineVariant,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 24),

            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
              child: FilledButton(
                onPressed: () => LoginSheet.show(context),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(54),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: Text(
                  'auth.welcome.login'.tr(),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Slide {
  const _Slide({
    this.icon,
    this.isBrand = false,
    required this.titleKey,
    required this.descKey,
  });
  final IconData? icon;
  final bool isBrand;
  final String titleKey;
  final String descKey;
}

class _SlideView extends StatelessWidget {
  const _SlideView({required this.slide});
  final _Slide slide;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (slide.isBrand)
            // Brand mark for the intro slide — the logo on its own, lightly
            // rounded corners, no frame.
            ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Image.asset(
                'assets/images/logo.png',
                width: 128,
                height: 128,
                fit: BoxFit.contain,
                filterQuality: FilterQuality.medium,
              ),
            )
          else
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(slide.icon, size: 44, color: scheme.primary),
            ),
          const SizedBox(height: 28),
          Text(
            slide.titleKey.tr(),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: slide.isBrand ? BrandColors.primary : null,
                ),
          ),
          const SizedBox(height: 10),
          Text(
            slide.descKey.tr(),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: scheme.onSurfaceVariant,
                  height: 1.5,
                ),
          ),
        ],
      ),
    );
  }
}
