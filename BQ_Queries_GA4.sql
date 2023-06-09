--/*Consultas para comenzar con Bigquery y GA4 */--



--//// Funnel Chart ////--
-- Esta consulta devuelve un resumen de las sesiones y eventos de un sitio web,
-- agrupados por día, fuente de tráfico, categoría de dispositivo y tipo de evento

SELECT
    PARSE_DATE("%Y%m%d", event_date) as date,
    traffic_source.medium as medium,
    traffic_source.source as source,
    device.category as device,
    COUNT(DISTINCT (
        SELECT value.int_value
        FROM UNNEST(event_params)
        WHERE key = 'ga_session_id'
    )) AS sessions,
    COUNT(DISTINCT (
        SELECT value.int_value
        FROM UNNEST (event_params)
        WHERE event_name = 'form_start' AND key = 'ga_session_id'
    )) as form_start,
    COUNT(DISTINCT (
        SELECT value.int_value
        FROM UNNEST (event_params)
        WHERE event_name = 'form_submit' AND key = 'ga_session_id'
    )) as form_submit,
    COUNT(DISTINCT (
        SELECT value.int_value
        FROM UNNEST (event_params)
        WHERE event_name = 'confirmacion_aj' AND key = 'ga_session_id'
    )) as confirmacion_aj
FROM `analytics_358268804.events_*`
GROUP BY
    date,
    medium,
    source,
    device;



-- //// Consulta que informa sobre la interaccion con los titulos de la pagina  ////
SELECT
  (SELECT value.string_value FROM UNNEST(event_params) WHERE event_name = 'page_view' AND key = 'page_title') AS page_title,
  COUNTIF(event_name = 'page_view') AS page_views,
  COUNT(DISTINCT user_pseudo_id) as users
FROM
  `analytics_358268804.events_*`
GROUP BY
  page_title
ORDER BY
  page_views DESC





-- ////Nuevos Visitantes a la web vs Visitantes Antiguos ////

SELECT
  CASE
    WHEN (SELECT value.int_value FROM UNNEST(event_params) WHERE event_name = 'session_start' AND key = 'ga_session_number') = 1 THEN 'new visitor'
    WHEN (SELECT value.int_value FROM UNNEST(event_params) WHERE event_name = 'session_start' AND key = 'ga_session_number') > 1 THEN 'returning visitor'
    ELSE NULL
  END AS user_type,
  COUNT(DISTINCT user_pseudo_id) AS users
FROM
  `analytics_358268804.events_*`
GROUP BY
  user_type
HAVING
  user_type IS NOT NULL



 --////Pagna que visito el usuario antes de llegar a la web ////


  with events as (
  select
    concat(
      user_pseudo_id,
      (
        select
          value.int_value
        from
          unnest(event_params)
        where
          key = 'ga_session_id'
      )
    ) as unique_session_id,
    event_name,
    event_timestamp,
    regexp_replace(
  regexp_replace(
    (
      select
        p.value.string_value
      from
        unnest(event_params) as p
      where
        p.key = 'page_location'
    ),
    r'^https?://[^/]+',
    ''
  ),
  r'[\?].*',
  ''
) as page_path
  from
 `analytics_358268804.events_*`
)
select
  unique_session_id,
  event_name,
  page_path,
  event_timestamp,
  if(
    event_name = 'page_view',
    coalesce(
      last_value(
        if(event_name = 'page_view', page_path, null) ignore nulls
      ) over(
        partition by unique_session_id
        order by
          event_timestamp asc rows between unbounded preceding
          and 1 preceding
      ),
      '(entrance)'
    ),
    null
  ) as previous_page,
  if(
    event_name = 'page_view',
    coalesce(
      first_value(
        if(event_name = 'page_view', page_path, null) ignore nulls
      ) over(
        partition by unique_session_id
        order by
          event_timestamp asc rows between 1 following
          and unbounded following
      ),
      '(exit)'
    ),
    null
  ) as next_page
from
  events



 --////  Sesiones por usuario ////


 with events as (
  select
    concat(
      user_pseudo_id,
      (
        select
          value.int_value
        from
          unnest(event_params)
        where
          key = 'ga_session_id'
      )
    ) as unique_session_id,
    event_name,
    event_timestamp,
    regexp_replace(
  regexp_replace(
    (
      select
        p.value.string_value
      from
        unnest(event_params) as p
      where
        p.key = 'page_location'
    ),
    r'^https?://[^/]+',
    ''
  ),
  r'[\?].*',
  ''
) as page_path
  from
 `analytics_358268804.events_*`
)
select
  unique_session_id,
  event_name,
  page_path,
  event_timestamp,
  if(
    event_name = 'page_view',
    coalesce(
      last_value(
        if(event_name = 'page_view', page_path, null) ignore nulls
      ) over(
        partition by unique_session_id
        order by
          event_timestamp asc rows between unbounded preceding
          and 1 preceding
      ),
      '(entrance)'
    ),
    null
  ) as previous_page,
  -- look for the next page_path
  if(
    event_name = 'page_view',
    coalesce(
      first_value(
        if(event_name = 'page_view', page_path, null) ignore nulls
      ) over(
        partition by unique_session_id
        order by
          event_timestamp asc rows between 1 following
          and unbounded following
      ),
      '(exit)'
    ),
    null
  ) as next_page
from
  events

 -- //// Dias que tardan en volver a la web el usuario ////

 -- Calculará el número promedio de días desde la primera visita para cada sesión.
 -- Luego agrupará por número de sesión y ordenará los resultados por sesión--
SELECT sess_number, avg(daysSinceFirstVisit) FROM
(SELECT
 user_pseudo_id,
 (SELECT value.int_value FROM unnest (event_params) WHERE key="ga_session_number") sess_number,
 MIN ((event_timestamp - user_first_touch_timestamp)/(1000000*60*60*24)) daysSinceFirstVisit
FROM `analytics_358268804.events_*`
WHERE _table_suffix >= '20230406'
GROUP BY 1, 2
)
GROUP BY 1
ORDER BY 1




-- ////engagement rate vs bounce rate ////
WITH sessionsEngaged AS (
  SELECT
    count(distinct session_id) as sessions,
    count(DISTINCT if( session_engaged>0, session_id, null)) as engaged_sessions
  FROM
    (SELECT
        (SELECT value.int_value FROM unnest(event_params) WHERE key="session_engaged")  as session_engaged ,
        CONCAT(user_pseudo_id, "-",
              (SELECT value.int_value FROM unnest(event_params) WHERE key="ga_session_id"))  as session_id
          FROM `analytics_358268804.events_*`)
)

SELECT  round(100*(engaged_sessions/sessions), 2) engagement_rate, round(100*(1-engaged_sessions/sessions), 2) bounce_rate FROM sessionsEngaged


  -- //// Paginas de Salida del Usuario ////
-- Esta consulta utiliza una subconsulta para extraer el ID de sesión y la URL de la página de salida para cada registro de evento de "page_view" en la tabla.
--Luego, utiliza la función first_value para obtener la última URL de la página de salida para cada ID de usuario y sesión.
--Por último, cuenta la cantidad de usuarios y sesiones únicos que tuvieron una página de salida determinada y las ordena por la cantidad de salidas.

with prep as (.
select
    user_pseudo_id,
    (select value.int_value from unnest(event_params) where event_name = 'page_view' and key = 'ga_session_id') as session_id,
    event_timestamp,
    first_value((select value.string_value from unnest(event_params) where event_name = 'page_view' and key = 'page_location')) over (partition by user_pseudo_id,(select value.int_value from unnest(event_params) where event_name = 'page_view' and key = 'ga_session_id') order by event_timestamp desc) as exit_page
from
    `analytics_358268804.events_20230406`
where
    event_name = 'page_view')

select
    exit_page,
    count(distinct concat(user_pseudo_id,session_id)) as exits
from
    prep
group by
    exit_page
having
    exit_page is not null
order by
    exits desc




--//// Como llegan los usuarios a la pagina (solo considerando el medio por el cual llegan) ////

WITH mediumAndSession AS (
  SELECT
  (SELECT value.string_value FROM unnest (event_params) WHERE key = "medium") as medium,
  CONCAT(
    (SELECT value.int_value FROM unnest (event_params) WHERE key = "ga_session_id" ),
    user_pseudo_id
  ) AS sessionID,
  user_pseudo_id,
  FROM `analytics_358268804.events_*`
)
SELECT medium, COUNT(DISTINCT user_pseudo_id) AS users, COUNT(DISTINCT sessionID) AS sessions
FROM mediumAndSession
GROUP BY medium
ORDER BY users DESC



--//// número de usuarios que tuvieron un cierto "page_referrer" en su primera sesión en el rango de fechas especificado////
-- Se agrupa por redes,organico, etc --
WITH prep AS (
  SELECT
    user_pseudo_id,
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS session_id,
    MAX((SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'page_referrer')) AS page_referrer
  FROM
    `analytics_358268804.events_*`
  GROUP BY
    user_pseudo_id,
    session_id
),

rank AS (
  SELECT
    user_pseudo_id,
    session_id,
    page_referrer,
    RANK() OVER (PARTITION BY user_pseudo_id ORDER BY session_id) AS rank
  FROM
    prep
  QUALIFY
    rank = 1
)

SELECT
  CASE
    WHEN page_referrer LIKE '%facebook.com%' THEN 'Facebook'
    WHEN page_referrer LIKE '%google.%' THEN 'Google'
    WHEN page_referrer LIKE '%autojusto.cl%' THEN 'Autojusto'
    WHEN page_referrer LIKE '%bing.%' THEN 'Bing'
    WHEN page_referrer LIKE '%autoutlet.cl%' THEN 'Autoutlet'
    WHEN page_referrer LIKE '%instagram.com%' THEN 'Instagram'
    ELSE '(not set)'
  END AS page_referrer_grouped,
  COUNT(DISTINCT user_pseudo_id) AS users
FROM
  rank
GROUP BY
  page_referrer_grouped
ORDER BY
  users DESC