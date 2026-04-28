import 'dart:math';

class SearchReplaceBlock {
  final String search;
  final String replace;

  SearchReplaceBlock({required this.search, required this.replace});
}

class DiffParser {
  static List<SearchReplaceBlock> parse(String response) {
    List<SearchReplaceBlock> blocks = [];
    
    int currentIndex = 0;
    while (true) {
      int searchIdx = response.indexOf('<<<<', currentIndex);
      if (searchIdx == -1) break;
      
      int eqIdx = response.indexOf('====', searchIdx);
      if (eqIdx == -1) break;
      
      int endIdx = response.indexOf('>>>>', eqIdx);
      if (endIdx == -1) break;
      
      int searchLineEnd = response.indexOf('\n', searchIdx);
      if (searchLineEnd == -1 || searchLineEnd > eqIdx) break;
      
      int eqLineEnd = response.indexOf('\n', eqIdx);
      if (eqLineEnd == -1 || eqLineEnd > endIdx) break;
      
      String searchPart = response.substring(searchLineEnd + 1, eqIdx);
      String replacePart = response.substring(eqLineEnd + 1, endIdx);
      
      searchPart = _stripOuterNewlines(searchPart);
      replacePart = _stripOuterNewlines(replacePart);
      
      blocks.add(SearchReplaceBlock(search: searchPart, replace: replacePart));
      currentIndex = endIdx + 4;
    }
    
    return blocks;
  }

  static String _stripOuterNewlines(String text) {
    if (text.startsWith('\r\n')) {
      text = text.substring(2);
    } else if (text.startsWith('\n') || text.startsWith('\r')) {
      text = text.substring(1);
    }
    
    if (text.endsWith('\r\n')) {
      text = text.substring(0, text.length - 2);
    } else if (text.endsWith('\n') || text.endsWith('\r')) {
      text = text.substring(0, text.length - 1);
    }
    return text;
  }
}
