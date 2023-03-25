import 'package:meta/meta.dart';

@internal
const Map<String, String> $queries = <String, String>{
/*
  'trigramSearch': r'''
WITH _search(id, relevance) AS (
  SELECT
    entity_id  AS id,
    SUM(count) AS relevance
  FROM trigram
  WHERE token IN ?
  GROUP BY entity_id
  --HAVING COUNT(DISTINCT token) = ?
  ORDER BY relevance DESC
  LIMIT 25
)
SELECT
  e.id          AS id,
  e.name        AS name,
  e.kind        AS kind,
  e.library     AS library,
  e.path        AS path,
  e.description AS description
FROM entity AS e
  INNER JOIN (
    SELECT
      MIN(e.id)        AS id,
      e.name           AS name,
      e.kind           AS kind,
      AVG(s.relevance) AS relevance
    FROM entity AS e
      INNER JOIN _search AS s
        ON e.id = s.id
    GROUP BY name, kind
  ) AS s
    ON e.id = s.id
''', */
};
