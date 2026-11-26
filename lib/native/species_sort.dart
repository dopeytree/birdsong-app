import 'package:flutter/material.dart';

import '../main.dart' show caps, ink, madder, paper, sepia;
import 'plate_library.dart';

/// All sort options shared between "No pecking order" and "Index of Species".
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
  SortOption('name', 'Name', Icons.sort_by_alpha, defaultAsc: true),
  SortOption('rare', 'Rarity', Icons.diamond_outlined, defaultAsc: true),
  SortOption('size', 'Size', Icons.straighten, defaultAsc: false),
  SortOption('colour', 'Colour', Icons.palette_outlined, defaultAsc: true),
  SortOption('artist', 'Artist', Icons.brush_outlined, defaultAsc: true),
  SortOption('sci', 'Latin', Icons.account_tree_outlined, defaultAsc: true),
];

/// Extract a clean sortable artist / illustrator name from a plate's credit.
/// Returns '' when no artist is known (so unattributed plates sort to the end).
String artistOfPlate(PlateArt? art) {
  if (art == null) return '';
  final raw = art.credit.trim().replaceFirst(RegExp(r'^After\s+'), '');
  if (raw.isEmpty) return '';
  // Fugleramme credits look like: "John Gould. Cut-out from the Fugleramme project, CC BY-SA 4.0."
  // or "The von Wright brothers, Svenska Fåglar. Cut-out from..."
  if (raw.contains('Cut-out from the Fugleramme')) {
    final before = raw.split('.').first.trim();
    if (before.isEmpty || before.startsWith('Cut-out')) return 'Fugleramme';
    final name = before.split(',').first.trim();
    return name.replaceFirst(RegExp(r'^The\s+', caseSensitive: false), '');
  }
  // Commons credits typically look like: "Artist, Title (year), Licence" or "Title — Artist"
  final emDash = raw.split('—');
  if (emDash.length >= 2) {
    return emDash.last.split(',').first.trim();
  }
  return raw.split(',').first.split('.').first.trim();
}

/// Clean, modern, transparent sort control with black icons, one-word labels,
/// and a direction flip arrow (↑ / ↓). Used on both "No pecking order" and
/// "Index of Species".
class SpeciesSortBar extends StatelessWidget {
  const SpeciesSortBar({
    super.key,
    required this.open,
    required this.sortKey,
    required this.ascending,
    required this.onToggleOpen,
    required this.onSelect,
    required this.onFlipDirection,
    this.centered = false,
  });

  final bool open;
  final String sortKey;
  final bool ascending;
  final VoidCallback onToggleOpen;
  final ValueChanged<String> onSelect;
  final VoidCallback onFlipDirection;
  final bool centered;

  @override
  Widget build(BuildContext context) {
    final active = speciesSortOptions.firstWhere(
      (o) => o.key == sortKey,
      orElse: () => speciesSortOptions.first,
    );
    return Row(
      mainAxisSize: centered ? MainAxisSize.min : MainAxisSize.max,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        IconButton(
          constraints: const BoxConstraints.tightFor(width: 38, height: 38),
          padding: EdgeInsets.zero,
          iconSize: 21,
          tooltip: open ? 'Hide sort' : 'Sort by ${active.label}',
          icon: Icon(open ? Icons.close : Icons.sort, color: ink),
          onPressed: onToggleOpen,
        ),
        if (!open)
          IconButton(
            constraints: const BoxConstraints.tightFor(width: 32, height: 38),
            padding: EdgeInsets.zero,
            iconSize: 18,
            tooltip: ascending ? 'Ascending (tap to reverse)' : 'Descending (tap to reverse)',
            icon: Icon(ascending ? Icons.arrow_upward : Icons.arrow_downward, color: ink),
            onPressed: onFlipDirection,
          ),
        Flexible(
          child: ClipRect(
            child: AnimatedSize(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              alignment: Alignment.centerLeft,
              child: open
                  ? Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                      decoration: BoxDecoration(
                        color: paper.withValues(alpha: 0.78),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            for (final opt in speciesSortOptions) _chip(opt),
                            const SizedBox(width: 2),
                            IconButton(
                              constraints: const BoxConstraints.tightFor(width: 32, height: 32),
                              padding: EdgeInsets.zero,
                              iconSize: 17,
                              tooltip: ascending ? 'Ascending (tap to reverse)' : 'Descending (tap to reverse)',
                              icon: Icon(
                                ascending ? Icons.arrow_upward : Icons.arrow_downward,
                                color: ink,
                              ),
                              onPressed: onFlipDirection,
                            ),
                          ],
                        ),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _chip(SortOption opt) {
    final selected = opt.key == sortKey;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
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
            const SizedBox(width: 4),
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
