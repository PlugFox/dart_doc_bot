import '../database/database.dart';

final RegExp _$exp = RegExp(r'[^a-z0-9a-яё]+');

class SearchService {
  SearchService({required Database database}) : _database = database;

  final Database _database;

  /// Sanitize query and split it into words.
  /// Maximum length of query is 60 characters.
  List<String> sanitize(String query) => (query.length > 60 ? '${query.substring(0, 60)}' : query)
      .trim()
      .toLowerCase()
      .split(_$exp)
      .where((e) => e.length > 2)
      .toList();

  /// Search by beginning of name.
  /// [words] - should be at least 3 characters long,
  /// sanitized and contain only letters and numbers.
  ///
  /// Returns list of entity ids.
  Future<List<String>> searchByName(List<String> words, {int limit = 25}) =>
      _database.customSelect(_$getSearchRequest$Words(words, limit)).get().then<List<String>>(
            (r) => r.map<String>((e) => e.data['id']! as String).toList(),
          );

  /// Search by trigrams.
  /// [words] - should be at least 3 characters long,
  /// sanitized and contain only letters and numbers.
  ///
  /// Returns list of entity ids.
  Future<List<String>> searchByTrigrams(List<String> words, {int limit = 25}) =>
      _database.customSelect(_$getSearchRequest$Trigrams(words, limit)).get().then<List<String>>(
            (r) => r.map<String>((e) => e.data['id']! as String).toList(),
          );

  /// Search by name and trigrams.
  /// [query] - should be at least 3 characters long
  /// and contain only letters and numbers.
  /// [limit] - maximum number of results.
  Future<List<Map<String, Object?>>> search(String query, {int limit = 25}) {
    final words = sanitize(query);
    if (words.isEmpty) return Future<List<Map<String, Object?>>>.value(<Map<String, Object?>>[]);
    return _database
        .customSelect(_$getSearchRequest$All(words, limit))
        .get()
        .then<List<Map<String, Object?>>>((data) => data.map<Map<String, Object?>>((e) => e.data).toList());
  }
}

/// Get trigram tokens from words.
List<String> _$trigramsFromWords(Iterable<String> words) => words
    .expand<String>((e) => e.split(_$exp).expand((word) sync* {
          if (word.length < 3) return;
          for (int i = 0; i <= word.length - 3; i++) {
            yield word.substring(i, i + 3);
          }
        }))
    .where((e) => e.length == 3)
    .toList();

/// Get request for searching by name.
String _$getSearchRequest$Words(Iterable<String> words, [int limit = 25]) => '''
WITH _input (value) AS (
  VALUES
    ${words.map<String>((e) => "('$e')").join(',\n    ')}
),
_prefixes (token, len, value) AS (
  SELECT DISTINCT
    substr(value, 1, 3) AS token,
    length(value)       AS len,
    value               AS value
  FROM _input
)
SELECT DISTINCT
  p.entity_id AS id
FROM prefix AS p
  INNER JOIN _prefixes AS t
  ON t.token = p.token
    AND t.len <= p.len
    AND t.value = substr(p.name, 1, t.len)
ORDER BY p.len ASC
LIMIT $limit
''';

/// Get request for searching by trigrams.
String _$getSearchRequest$Trigrams(Iterable<String> words, [int limit = 25]) => '''
SELECT
  entity_id  AS id,
  SUM(count) AS relevance
FROM trigram
WHERE token IN
  (${_$trigramsFromWords(words).map<String>((e) => "'$e'").join(', ')})
GROUP BY entity_id
ORDER BY relevance DESC
LIMIT $limit
''';

String _$getSearchRequest$All(List<String> words, [int limit = 24]) => '''
WITH _input (value) AS (
  VALUES
    ${words.map<String>((e) => "('$e')").join(',\n    ')}
),
_prefixes (token, len, value) AS (
  SELECT DISTINCT
    substr(value, 1, 3) AS token,
    length(value)       AS len,
    value               AS value
  FROM _input
),
_word_ids (id, relevance) AS (
  SELECT DISTINCT
    p.entity_id                 AS id,
    1000 + (1000 / (p.len - 3)) AS relevance
  FROM prefix AS p
    INNER JOIN _prefixes AS t
    ON t.token = p.token
      AND t.len <= p.len
      AND t.value = substr(p.name, 1, t.len)
  LIMIT $limit
),
_trigram_ids (id, relevance) AS (
  SELECT
    entity_id  AS id,
    SUM(count) AS relevance
  FROM trigram
  WHERE token IN
    (${_$trigramsFromWords(words).map<String>((e) => "'$e'").join(', ')})
  GROUP BY entity_id
  LIMIT $limit
),
_ids (id, relevance) AS (
  SELECT
    id             AS id,
    SUM(relevance) AS relevance
  FROM (
    SELECT id, relevance FROM _word_ids
    UNION ALL
    SELECT id, relevance FROM _trigram_ids
  )
  GROUP BY id
  ORDER BY relevance DESC
  LIMIT $limit
)
SELECT
  e.id          AS id,
  i.relevance   AS relevance,
  e.library     AS library,
  e.parent_id   AS parent_id,
  e.name        AS name,
  e.kind        AS kind,
  e.description AS description,
  e.path        AS path,
  e.created_at  AS created_at,
  e.updated_at  AS updated_at
FROM entity AS e
  INNER JOIN _ids AS i
    ON e.id = i.id
ORDER BY i.relevance DESC
''';
