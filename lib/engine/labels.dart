import 'dart:convert';

/// One class a model can output.
class SpeciesLabel {
  const SpeciesLabel(this.sci, this.common, {this.animal = true});

  final String sci;
  final String common;

  /// False for sound classes such as "Engine" or "Human vocal".
  final bool animal;

  SpeciesLabel withCommon(String name) =>
      SpeciesLabel(sci, name, animal: animal);
}

final _binomial = RegExp(r"^[A-Z][a-z\-]+ [a-z\-]+( [a-z\-]+)?$");

bool looksLikeSpecies(String sci) => _binomial.hasMatch(sci);

const _soundClassWords = {'Human', 'Power'};

bool _isAnimal(String sci, String common, String cls) {
  if (!looksLikeSpecies(sci)) return false;
  if (sci == common) return false; // BirdNET v2.4 writes sound classes twice
  if (_soundClassWords.contains(sci.split(' ').first)) return false;
  final c = cls.toLowerCase();
  if (c.isNotEmpty && (c.contains('sound') || c.contains('noise') || c.contains('human'))) {
    return false;
  }
  return true;
}

/// Reads any of the label formats in use:
///
/// * BirdNET: `Scientific name_Common name[_code]`, one per line
/// * Perch: `Scientific name`, one per line
/// * CSV with a header naming `sci_name`/`scientific_name` and
///   `com_name`/`common_name`, separated by `;`, `,` or tabs
/// * headerless tab- or `;`-separated rows such as `BN00001<TAB>Sci<TAB>Common`
List<SpeciesLabel> parseLabels(String text) {
  final lines = const LineSplitter()
      .convert(text)
      .map((l) => l.replaceAll('\r', '').trim())
      .where((l) => l.isNotEmpty)
      .toList();
  if (lines.isEmpty) return const [];

  final head = lines.first.toLowerCase();
  if (head.contains('sci_name') || head.contains('scientific_name')) {
    return _parseWithHeader(lines);
  }
  return lines.map(_parseLine).toList(growable: false);
}

String _delimiterOf(String line) {
  if (line.contains('\t')) return '\t';
  if (line.contains(';')) return ';';
  return ',';
}

List<SpeciesLabel> _parseWithHeader(List<String> lines) {
  final d = _delimiterOf(lines.first);
  final header = lines.first.split(d).map((h) => h.trim().toLowerCase()).toList();
  int col(List<String> names) {
    for (final n in names) {
      final i = header.indexOf(n);
      if (i >= 0) return i;
    }
    return -1;
  }

  final iSci = col(['sci_name', 'scientific_name']);
  final iCom = col(['com_name', 'common_name']);
  final iCls = col(['class', 'taxon_group']);
  final out = <SpeciesLabel>[];
  for (final line in lines.skip(1)) {
    final cells = line.split(d);
    String at(int i) => i >= 0 && i < cells.length ? cells[i].trim() : '';
    final sci = at(iSci);
    final common = at(iCom);
    out.add(SpeciesLabel(sci, common.isEmpty ? sci : common,
        animal: _isAnimal(sci, common, at(iCls))));
  }
  return out;
}

SpeciesLabel _parseLine(String line) {
  if (line.contains('\t') || line.contains(';')) {
    final cells = line.split(_delimiterOf(line)).map((c) => c.trim()).toList();
    final iSci = cells.indexWhere(looksLikeSpecies);
    if (iSci >= 0) {
      final sci = cells[iSci];
      final common = iSci + 1 < cells.length ? cells[iSci + 1] : '';
      return SpeciesLabel(sci, common.isEmpty ? sci : common,
          animal: _isAnimal(sci, common, ''));
    }
    final name = cells.firstWhere((c) => c.isNotEmpty, orElse: () => line);
    return SpeciesLabel(name, name, animal: false);
  }
  if (line.contains('_')) {
    final parts = line.split('_');
    final sci = parts[0].trim();
    final common = parts.length > 1 ? parts[1].trim() : '';
    return SpeciesLabel(sci, common.isEmpty ? sci : common,
        animal: _isAnimal(sci, common, ''));
  }
  // Perch writes scientific names alone; sound classes are single words.
  return SpeciesLabel(line, line, animal: looksLikeSpecies(line));
}

/// Scientific name to common name, from any parsed label list.
Map<String, String> namesOf(List<SpeciesLabel> labels) => {
      for (final l in labels)
        if (l.common.isNotEmpty && l.common != l.sci) l.sci: l.common,
    };
