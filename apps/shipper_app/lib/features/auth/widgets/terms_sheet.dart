import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:wetruck_core/wetruck_core.dart';

/// Checkbox + "I have read and accept the [Terms & Conditions]" row. The link
/// span opens [TermsSheet]; tapping the rest of the label toggles the checkbox.
class TermsRow extends StatefulWidget {
  const TermsRow({
    super.key,
    required this.accepted,
    required this.enabled,
    required this.onChanged,
    required this.onOpenTerms,
  });

  final bool accepted;
  final bool enabled;
  final ValueChanged<bool> onChanged;
  final VoidCallback onOpenTerms;

  @override
  State<TermsRow> createState() => _TermsRowState();
}

class _TermsRowState extends State<TermsRow> {
  late final TapGestureRecognizer _linkRecognizer;

  @override
  void initState() {
    super.initState();
    _linkRecognizer = TapGestureRecognizer()..onTap = widget.onOpenTerms;
  }

  @override
  void dispose() {
    _linkRecognizer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final muted = Theme.of(context).textTheme.bodySmall?.copyWith(
          color: scheme.onSurfaceVariant,
        );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 28,
          height: 28,
          child: Checkbox(
            value: widget.accepted,
            onChanged:
                widget.enabled ? (v) => widget.onChanged(v ?? false) : null,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap:
                widget.enabled ? () => widget.onChanged(!widget.accepted) : null,
            child: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text.rich(
                TextSpan(
                  style: muted,
                  children: [
                    TextSpan(text: '${'auth.sign_in.terms_prefix'.tr()} '),
                    TextSpan(
                      text: 'auth.sign_in.terms_link'.tr(),
                      style: TextStyle(
                        color: scheme.primary,
                        fontWeight: FontWeight.w600,
                        decoration: TextDecoration.underline,
                      ),
                      recognizer: _linkRecognizer,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Draggable bottom sheet with the full Terms & Conditions. Returns `true` when
/// the user taps "I Accept".
class TermsSheet extends StatelessWidget {
  const TermsSheet._();

  static Future<bool?> show(BuildContext context) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (_) => const TermsSheet._(),
    );
  }

  // Bullet bodies mirrored from the Next.js sign-in dialog so the legal content
  // stays consistent across platforms; non-English locales fall back to English.
  static const _section2Bullets = <String>[
    'All GPS devices installed on trucks and integrated with the Wetruck Platform remain the exclusive property of the Company. You must keep them active, functional, and completely unaltered throughout every shipment (per Proclamation Art. 15 on period of responsibility).',
    'If you, the truck owner, or your transport association ceases, suspends, or terminates your relationship with the Company, the Company has the full right to immediately remove, retrieve, or deactivate the GPS device without any objection.',
    'You bear full responsibility for the care, custody, and control of the cargo from the moment of taking charge (handover and acceptance) until delivery to the consignee or authorized person at the agreed destination.',
    'In case of theft, loss, damage, or delay to the cargo during transit, you will be held liable according to this Agreement and Ethiopian law, except when proven that: all reasonable measures were taken to avoid the event, or the loss results from force majeure (extraordinary, unforeseeable circumstances beyond control, such as natural disasters, war, pandemics, or government actions), inherent vice of the goods, or the consignor’s (shipper’s) wrongful act/neglect/instructions.',
    'Liability is limited to 835 Special Drawing Rights (SDR) per package or 2.5 SDR per kg of gross weight (whichever is higher), unless otherwise agreed or the stage of loss is identified under specific laws. For delay, liability is limited to 2.5 times the freight, not exceeding total freight.',
    'You must perform duties with due diligence and are liable for acts/omissions of servants, agents, or others used in performance (Proclamation Art. 16; Regulations No. 37/1998 Art. 12).',
  ];

  static const _section3Bullets = <String>[
    'You must provide accurate, complete, and truthful information about the cargo (general nature, marks, number of packages, weight/quantity, dangerous character if applicable, container details, destination) as required by the Wetruck Platform. You guarantee the accuracy of these particulars and indemnify the Company/Transporter for any losses from inaccuracies.',
    'For dangerous goods, you must mark/label them and inform the Transporter of their character and necessary precautions (Proclamation Art. 29-31).',
    'Upon arrival of the container at the destination, you must complete offloading within the agreed free days specified in the shipment terms.',
    'If offloading exceeds the agreed free time, you will be liable for detention charges calculated at the applicable rates.',
    'You are liable for losses to the Transporter caused by your fault/neglect or that of your servants/agents (Proclamation Art. 28; Regulations No. 37/1998 Art. 12 on due diligence).',
  ];

  static const _section4Bullets = <String>[
    'These terms form part of the full Wetruck User Agreement and comply with Ethiopian laws.',
    'Any stipulations derogating from the Multimodal Transport Proclamation are null and void.',
    'Continued use of the platform constitutes ongoing acceptance.',
    'Notices for loss/damage must be given in writing.',
    'For apparent damage, the notice should be provided the next working day; for non-apparent damage, within 7 days.',
    'In no case when notice is delayed for more than 60 days shall compensation be paid.',
    'When court actions are instituted within 2 years, the right is barred by the period of limitation.',
    'Disputes shall be resolved by courts at the place of contract, taking charge, or delivery which has jurisdiction to entertain as per pertinent law.',
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'auth.terms_dialog.title'.tr(),
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: scheme.primary,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'auth.terms_dialog.subtitle'.tr(),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                children: [
                  _TermsSection(
                    title: 'auth.terms_dialog.section_1_title'.tr(),
                    paragraph: 'auth.terms_dialog.section_1_content'.tr(),
                  ),
                  const SizedBox(height: 16),
                  _TermsSection(
                    title: 'auth.terms_dialog.section_2_title'.tr(),
                    bullets: _section2Bullets,
                  ),
                  const SizedBox(height: 16),
                  _TermsSection(
                    title: 'auth.terms_dialog.section_3_title'.tr(),
                    bullets: _section3Bullets,
                  ),
                  const SizedBox(height: 16),
                  _TermsSection(
                    title: 'auth.terms_dialog.section_4_title'.tr(),
                    bullets: _section4Bullets,
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      child: Text('auth.terms_dialog.close'.tr()),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.of(context).pop(true),
                      child: Text('auth.terms_dialog.accept'.tr()),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _TermsSection extends StatelessWidget {
  const _TermsSection({required this.title, this.paragraph, this.bullets});
  final String title;
  final String? paragraph;
  final List<String>? bullets;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context)
              .textTheme
              .titleSmall
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        if (paragraph != null)
          Text(paragraph!, style: Theme.of(context).textTheme.bodyMedium),
        if (bullets != null)
          for (final item in bullets!)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 7),
                    child: Container(
                      width: 4,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.onSurface,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(item,
                        style: Theme.of(context).textTheme.bodyMedium),
                  ),
                ],
              ),
            ),
      ],
    );
  }
}
