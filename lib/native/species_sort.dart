import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../main.dart' show caps, ink, madder, rule, sepia;
import '../ui/paper_surface.dart';
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
  SortOption('calls', 'Calls', Symbols.graphic_eq, defaultAsc: false),
  SortOption('recent', 'Latest', Symbols.schedule, defaultAsc: false),
  SortOption('family', 'Species', Symbols.workspaces, defaultAsc: true),
  SortOption('name', 'Name', Symbols.sort_by_alpha, defaultAsc: true),
  SortOption('wingspan', 'Wingspan', Symbols.open_in_full, defaultAsc: false),
  SortOption('weight', 'Weight', Symbols.scale, defaultAsc: false),
  SortOption('colour', 'Colour', Symbols.palette, defaultAsc: true),
  SortOption('region', 'Region', Symbols.public, defaultAsc: true),
  SortOption('artist', 'Artist', Symbols.brush, defaultAsc: true),
  SortOption('rare', 'Rarity', Symbols.diamond, defaultAsc: true),
  SortOption('active', 'Active', Symbols.wb_twilight, defaultAsc: true),
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

/// Clean, modern, frosted-paper sort & filter control with unified Material
/// Symbols icons. Starts with a reset button (default: Labels off, sort by
/// Species), then the Labels toggle (filled when on), direction arrow, and all
/// sort chips wrapped cleanly so nothing hides off-screen on mobile.
class SpeciesSortBar extends StatelessWidget {
  const SpeciesSortBar({
    super.key,
    required this.open,
    required this.sortKey,
    required this.ascending,
    required this.onToggleOpen,
    required this.onSelect,
    required this.onFlipDirection,
    this.onReset,
    this.showLabels,
    this.onToggleLabels,
    this.centered = false,
    this.showTrigger = true,
    this.adaptiveTrigger = false,
  });

  final bool open;
  final String sortKey;
  final bool ascending;
  final VoidCallback onToggleOpen;
  final ValueChanged<String> onSelect;
  final VoidCallback onFlipDirection;
  final VoidCallback? onReset;

  /// Optional name-ticket labels toggle (filled label icon when on).
  final bool? showLabels;
  final VoidCallback? onToggleLabels;
  final bool centered;

  /// When false, renders only the expandable panel (used by [IndexView] which
  /// places the filter icon inline beside the "Index of Species" heading).
  final bool showTrigger;

  /// When true, applies GPU difference inversion to the filter trigger so it
  /// stays crisp over dark bird artwork on No pecking order.
  final bool adaptiveTrigger;

  @override
  Widget build(BuildContext context) {
    final active = speciesSortOptions.firstWhere(
      (o) => o.key == sortKey,
      orElse: () => speciesSortOptions.first,
    );
    final triggerIcon = Icon(
      open ? Symbols.close : Symbols.filter_alt,
      color: adaptiveTrigger ? adaptiveInkSource : ink,
    );
    final trigger = IconButton(
      constraints: const BoxConstraints.tightFor(width: 40, height: 40),
      padding: EdgeInsets.zero,
      iconSize: 22,
      tooltip: open ? 'Hide filters' : 'Filter & sort (${active.label})',
      icon: adaptiveTrigger ? AdaptiveContrast(child: triggerIcon) : triggerIcon,
      onPressed: () {
        hapticTap();
        onToggleOpen();
      },
    );
    final panel = AnimatedSize(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      alignment: centered ? Alignment.topCenter : Alignment.topLeft,
      child: open
          ? PaperSurface(
              margin: const EdgeInsets.only(top: 4),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              borderRadius: 16,
              child: Wrap(
                spacing: 2,
                runSpacing: 2,
                alignment: centered ? WrapAlignment.center : WrapAlignment.start,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  // Far left: Reset to defaults (Labels off, sort by Species).
                  if (onReset != null)
                    IconButton(
                      constraints: const BoxConstraints.tightFor(width: 34, height: 34),
                      padding: EdgeInsets.zero,
                      iconSize: 18,
                      tooltip: 'Reset filters (no labels, sort by Species)',
                      icon: const Icon(Symbols.refresh, color: ink),
                      onPressed: () {
                        hapticTap();
                        onReset!();
                      },
                    ),
                  // Labels toggle (filled Material Symbol when enabled).
                  if (showLabels != null && onToggleLabels != null) ...[
                    _labelsChip(showLabels!, onToggleLabels!),
                    Container(
                      width: 1,
                      height: 18,
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      color: rule.withValues(alpha: 0.6),
                    ),
                  ],
                  // Sort direction arrow.
                  IconButton(
                    constraints: const BoxConstraints.tightFor(width: 34, height: 34),
                    padding: EdgeInsets.zero,
                    iconSize: 18,
                    tooltip: ascending ? 'Ascending (tap to reverse)' : 'Descending (tap to reverse)',
                    icon: Icon(ascending ? Symbols.arrow_upward : Symbols.arrow_downward, color: ink),
                    onPressed: () {
                      hapticTap();
                      onFlipDirection();
                    },
                  ),
                  for (final opt in speciesSortOptions) _chip(opt),
                ],
              ),
            )
          : const SizedBox.shrink(),
    );
    if (!showTrigger) return panel;
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
      onTap: () {
        hapticTap();
        onTap();
      },
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
            Icon(
              Symbols.label,
              fill: on ? 1.0 : 0.0,
              size: 17,
              color: on ? madder : ink,
            ),
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
        hapticTap();
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
            Icon(opt.icon, size: 17, color: selected ? madder : ink),
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
