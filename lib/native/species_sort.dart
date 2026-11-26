import 'package:flutter/material.dart';

import '../main.dart' show caps, ink, madder, paper, rule, sepia;
import 'plate_library.dart';

/// All sort options shared between "No pecking order" and "Index of Species",
/// in the user's preferred order.
class SortOption {
  const SortOption(this.key, this.label, this.icon, {required this.defaultAsc});

  final String key;
  final String label;
  final IconData icon;

  /// Natural direction when first selected (e.g. A–Z is ascending; Calls is descending).
  final bool defaultAsc;
}

const speciesSortOptions = <SortOption>[
  SortOption('calls', 'Calls', Icons.graphic_eq, defaultAsc: false),
  SortOption('recent', 'Latest', Icons.schedule, defaultAsc: false),
  SortOption('family', 'Species', Icons.workspaces_outlined, defaultAsc: true),
  SortOption('name', 'Name', Icons.sort_by_alpha, defaultAsc: true),
  SortOption('wingspan', 'Wingspan', Icons.open_in_full, defaultAsc: false),
  SortOption('weight', 'Weight', Icons.scale_outlined, defaultAsc: false),
  SortOption('colour', 'Colour', Icons.palette_outlined, defaultAsc: true),
  SortOption('region', 'Region', Icons.public, defaultAsc: true),
  SortOption('artist', 'Artist', Icons.brush_outlined, defaultAsc: true),
  SortOption('rare', 'Rarity', Icons.diamond_outlined, defaultAsc: true),
  SortOption('active', 'Active', Icons.wb_twilight, defaultAsc: true),
];

/// Extract a clean sortable artist / illustrator name from a plate's credit.
/// Returns '' when no artist is known (so unattributed plates sort to the end).
String artistOfPlate(PlateArt? art) {
  if (art == null) return '';
  final raw = art.credit.trim().replaceFirst(RegExp(r'^After\s+'), '');
  if (raw.isEmpty) return '';
  if (raw.contains('Cut-out from the Fugleramme')) {
    final before = raw.split('.').first.trim();
    if (before.isEmpty || before.startsWith('Cut-out')) return 'Fugleramme';
    final name = before.split(',').first.trim();
    return name.replaceFirst(RegExp(r'^The\s+', caseSensitive: false), '');
  }
  final emDash = raw.split('—');
  if (emDash.length >= 2) {
    return emDash.last.split(',').first.trim();
  }
  return raw.split(',').first.split('.').first.trim();
}

/// Clean, modern, translucent sort control with black icons and one-word
/// labels. Expands into a wrapping panel so every filter is immediately
/// visible on mobile without hidden horizontal scrolling.
class SpeciesSortBar extends StatelessWidget {
  const SpeciesSortBar({
    super.key,
    required this.open,
    required this.sortKey,
    required this.ascending,
    required this.onToggleOpen,
    required this.onSelect,
    required this.onFlipDirection,
    this.showLabels,
    this.onToggleLabels,
    this.centered = false,
  });

  final bool open;
  final String sortKey;
  final bool ascending;
  final VoidCallback onToggleOpen;
  final ValueChanged<String> onSelect;
  final VoidCallback onFlipDirection;

  /// Optional name-ticket labels toggle shown as the 1st option in the panel.
  final bool? showLabels;
  final VoidCallback? onToggleLabels;
  final bool centered;

  @override
  Widget build(BuildContext context) {
    final active = speciesSortOptions.firstWhere(
      (o) => o.key == sortKey,
      orElse: () => speciesSortOptions.first,
    );
    final trigger = IconButton(
      constraints: const BoxConstraints.tightFor(width: 40, height: 40),
      padding: EdgeInsets.zero,
      iconSize: 22,
      tooltip: open ? 'Hide sort' : 'Sort by ${active.label}',
      icon: Icon(open ? Icons.close : Icons.swap_vert, color: ink),
      onPressed: onToggleOpen,
    );
    final panel = AnimatedSize(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      alignment: centered ? Alignment.topCenter : Alignment.topLeft,
      child: open
          ? Container(
              margin: EdgeInsets.only(top: centered ? 4 : 4),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: paper.withValues(alpha: 0.94),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: rule.withValues(alpha: 0.55)),
                boxShadow: const [
                  BoxShadow(color: Color(0x242A241C), offset: Offset(0, 4), blurRadius: 14),
                ],
              ),
              child: Wrap(
                spacing: 2,
                runSpacing: 2,
                alignment: centered ? WrapAlignment.center : WrapAlignment.start,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  // 1st option: toggle bird name-ticket labels on/off.
                  if (showLabels != null && onToggleLabels != null) ...[
                    _labelsChip(showLabels!, onToggleLabels!),
                    Container(
                      width: 1,
                      height: 18,
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      color: rule.withValues(alpha: 0.65),
                    ),
                  ],
                  // Direction toggle sits first among the sort options.
                  IconButton(
                    constraints: const BoxConstraints.tightFor(width: 34, height: 34),
                    padding: EdgeInsets.zero,
                    iconSize: 18,
                    tooltip: ascending ? 'Ascending (tap to reverse)' : 'Descending (tap to reverse)',
                    icon: Icon(ascending ? Icons.arrow_upward : Icons.arrow_downward, color: ink),
                    onPressed: onFlipDirection,
                  ),
                  for (final opt in speciesSortOptions) _chip(opt),
                ],
              ),
            )
          : const SizedBox.shrink(),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: centered ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      children: [
        trigger,
        panel,
      ],
    );
  }

  Widget _labelsChip(bool on, VoidCallback onTap) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      hoverColor: ink.withValues(alpha: 0.08),
      highlightColor: ink.withValues(alpha: 0.12),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        decoration: on
            ? const BoxDecoration(
                border: Border(bottom: BorderSide(color: madder, width: 1.8)),
              )
            : null,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.label_outlined, size: 16, color: on ? madder : ink),
            const SizedBox(width: 5),
            Text(
              'Labels',
              style: TextStyle(
                fontFamily: caps,
                fontSize: 12.5,
                letterSpacing: 0.4,
                color: on ? ink : sepia,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(SortOption opt) {
    final selected = opt.key == sortKey;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      hoverColor: ink.withValues(alpha: 0.08),
      highlightColor: ink.withValues(alpha: 0.12),
      onTap: () {
        if (selected) {
          onFlipDirection();
        } else {
          onSelect(opt.key);
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        decoration: selected
            ? const BoxDecoration(
                border: Border(bottom: BorderSide(color: madder, width: 1.8)),
              )
            : null,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(opt.icon, size: 16, color: selected ? madder : ink),
            const SizedBox(width: 5),
            Text(
              opt.label,
              style: TextStyle(
                fontFamily: caps,
                fontSize: 12.5,
                letterSpacing: 0.4,
                color: selected ? ink : sepia,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
