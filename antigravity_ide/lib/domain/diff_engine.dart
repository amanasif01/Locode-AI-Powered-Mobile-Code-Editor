import 'dart:math';

enum DiffType { unchanged, insert, delete }

class DiffLine {
  final String text;
  final DiffType type;
  final int originalLineNumber; // -1 if insert
  final int newLineNumber; // -1 if delete

  DiffLine(this.text, this.type, this.originalLineNumber, this.newLineNumber);
}

class DiffHunk {
  final List<DiffLine> lines = [];
  bool isAccepted = false;
  bool isRejected = false;
  bool get isPending => !isAccepted && !isRejected;
}

class DiffEngine {
  /// Computes a basic line-by-line diff between two strings.
  /// Uses a simplified Longest Common Subsequence (LCS) dynamic programming approach.
  /// For very large files, a true Myers diff is faster, but this works for typical code blocks.
  static List<DiffLine> computeDiff(String oldText, String newText) {
    final oldLines = oldText.split('\n');
    final newLines = newText.split('\n');
    
    // Quick optimization for exact matches
    if (oldText == newText) {
      return [];
    }

    // 1. Strip common prefix
    int prefixLen = 0;
    while (prefixLen < oldLines.length && prefixLen < newLines.length && oldLines[prefixLen] == newLines[prefixLen]) {
      prefixLen++;
    }

    // 2. Strip common suffix
    int suffixLen = 0;
    while (suffixLen < (oldLines.length - prefixLen) && suffixLen < (newLines.length - prefixLen) && 
           oldLines[oldLines.length - 1 - suffixLen] == newLines[newLines.length - 1 - suffixLen]) {
      suffixLen++;
    }

    final oldSlice = oldLines.sublist(prefixLen, oldLines.length - suffixLen);
    final newSlice = newLines.sublist(prefixLen, newLines.length - suffixLen);

    // 3. Compute LCS grid for the differing slice
    final grid = List.generate(oldSlice.length + 1, (_) => List.filled(newSlice.length + 1, 0));
    
    for (int i = 1; i <= oldSlice.length; i++) {
      for (int j = 1; j <= newSlice.length; j++) {
        if (oldSlice[i - 1] == newSlice[j - 1]) {
          grid[i][j] = grid[i - 1][j - 1] + 1;
        } else {
          grid[i][j] = max(grid[i - 1][j], grid[i][j - 1]);
        }
      }
    }

    // 4. Backtrack to find the diff path
    int i = oldSlice.length;
    int j = newSlice.length;
    final List<DiffLine> diffPath = [];

    while (i > 0 || j > 0) {
      if (i > 0 && j > 0 && oldSlice[i - 1] == newSlice[j - 1]) {
        diffPath.add(DiffLine(oldSlice[i - 1], DiffType.unchanged, prefixLen + i - 1, prefixLen + j - 1));
        i--;
        j--;
      } else if (j > 0 && (i == 0 || grid[i][j - 1] >= grid[i - 1][j])) {
        diffPath.add(DiffLine(newSlice[j - 1], DiffType.insert, -1, prefixLen + j - 1));
        j--;
      } else if (i > 0 && (j == 0 || grid[i][j - 1] < grid[i - 1][j])) {
        diffPath.add(DiffLine(oldSlice[i - 1], DiffType.delete, prefixLen + i - 1, -1));
        i--;
      }
    }

    // The path is built backwards, so reverse it
    final reversedPath = diffPath.reversed.toList();

    // If it's a completely new file (old text is empty)
    if (oldText.trim().isEmpty && newText.trim().isNotEmpty) {
      final lines = <DiffLine>[];
      for (int k = 0; k < newLines.length; k++) {
        lines.add(DiffLine(newLines[k], DiffType.insert, -1, k));
      }
      return lines;
    }

    // Combine prefix, reversed path, and suffix into one full file diff
    final fullDiff = <DiffLine>[];
    
    // Add prefix
    for (int k = 0; k < prefixLen; k++) {
      fullDiff.add(DiffLine(oldLines[k], DiffType.unchanged, k, k));
    }
    
    // Add computed diff path
    fullDiff.addAll(reversedPath);
    
    // Add suffix
    for (int k = 0; k < suffixLen; k++) {
      fullDiff.add(DiffLine(oldLines[oldLines.length - suffixLen + k], DiffType.unchanged, oldLines.length - suffixLen + k, newLines.length - suffixLen + k));
    }

    return fullDiff;
  }
}
