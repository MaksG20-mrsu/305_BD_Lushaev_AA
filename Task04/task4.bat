#!/bin/bash
chcp 65001 2>/dev/null || true

if command -v sqlite3 >/dev/null 2>&1; then
    SQLITE="sqlite3"
else
    SQLITE="/c/Users/alexandr/Desktop/sqlite/sqlite3.exe"
fi

if [ ! -x "$SQLITE" ]; then
    echo "SQLite executable not found. Check SQLITE path."
    exit 1
fi

"$SQLITE" movies_rating.db < db_init.sql
if [ $? -ne 0 ]; then
    echo "Database initialization failed."
    exit 1
fi

echo "1. Найти пары пользователей, оценивших один и тот же фильм. Исключить дубликаты и пары с самим собой. Вывести имена пользователей и название фильма. Первые 100 записей."
echo "--------------------------------------------------"
"$SQLITE" -box -echo movies_rating.db "
SELECT DISTINCT
    u1.name AS user_1,
    u2.name AS user_2,
    m.title AS movie_title
FROM ratings AS r1
JOIN ratings AS r2
    ON r1.movie_id = r2.movie_id
   AND r1.user_id < r2.user_id
JOIN users AS u1 ON u1.id = r1.user_id
JOIN users AS u2 ON u2.id = r2.user_id
JOIN movies AS m ON m.id = r1.movie_id
ORDER BY m.title, u1.name, u2.name
LIMIT 100;
"
echo " "

echo "2. Вывести 10 самых свежих оценок от разных пользователей: название фильма, имя пользователя, оценку и дату."
echo "--------------------------------------------------"
"$SQLITE" -box -echo movies_rating.db "
WITH ranked_ratings AS (
    SELECT r.*,
        ROW_NUMBER() OVER (
            PARTITION BY r.user_id
            ORDER BY r.timestamp DESC, r.id DESC
        ) AS user_row
    FROM ratings AS r
)
SELECT
    m.title AS movie_title,
    u.name AS user_name,
    rr.rating,
    date(rr.timestamp, 'unixepoch') AS review_date
FROM ranked_ratings AS rr
JOIN movies AS m ON m.id = rr.movie_id
JOIN users AS u ON u.id = rr.user_id
WHERE rr.user_row = 1
ORDER BY rr.timestamp DESC
LIMIT 10;
"
echo " "

echo "3. Вывести фильмы с максимальным и минимальным средним рейтингом. Для максимального рейтинга указать Рекомендуем: Да, для минимального: Нет."
echo "--------------------------------------------------"
"$SQLITE" -box -echo movies_rating.db "
WITH movie_averages AS (
    SELECT m.id, m.title, m.year, AVG(r.rating) AS avg_rating
    FROM movies AS m
    JOIN ratings AS r ON r.movie_id = m.id
    GROUP BY m.id, m.title, m.year
),
extremes AS (
    SELECT MAX(avg_rating) AS max_rating, MIN(avg_rating) AS min_rating
    FROM movie_averages
)
SELECT
    ma.title AS movie_title,
    ma.year,
    ROUND(ma.avg_rating, 3) AS avg_rating,
    CASE WHEN ma.avg_rating = e.max_rating
         THEN 'Да' ELSE 'Нет' END AS \"Рекомендуем\"
FROM movie_averages AS ma
CROSS JOIN extremes AS e
WHERE ma.avg_rating = e.max_rating
   OR ma.avg_rating = e.min_rating
ORDER BY (ma.year IS NULL), ma.year, ma.title;
"
echo " "

echo "4. Вычислить количество оценок и среднюю оценку, поставленную пользователями-женщинами в период с 2010 по 2012 год включительно."
echo "--------------------------------------------------"
"$SQLITE" -box -echo movies_rating.db "
SELECT
    COUNT(*) AS ratings_count,
    ROUND(AVG(r.rating), 3) AS average_rating
FROM ratings AS r
JOIN users AS u ON u.id = r.user_id
WHERE LOWER(TRIM(u.gender)) IN ('f', 'female', 'ж', 'женский')
  AND date(r.timestamp, 'unixepoch') >= '2010-01-01'
  AND date(r.timestamp, 'unixepoch') < '2013-01-01';
"
echo " "

echo "5. Вывести фильмы со средней оценкой и местом в рейтинге по средней оценке. Отсортировать по году и названию, оставить первые 20 записей."
echo "--------------------------------------------------"
"$SQLITE" -box -echo movies_rating.db "
WITH movie_averages AS (
    SELECT m.id, m.title, m.year, AVG(r.rating) AS avg_rating
    FROM movies AS m
    JOIN ratings AS r ON r.movie_id = m.id
    GROUP BY m.id, m.title, m.year
),
ranked_movies AS (
    SELECT
        title,
        year,
        avg_rating,
        RANK() OVER (ORDER BY avg_rating DESC) AS rating_place
    FROM movie_averages
)
SELECT
    title AS movie_title,
    year,
    ROUND(avg_rating, 3) AS avg_rating,
    rating_place
FROM ranked_movies
ORDER BY (year IS NULL), year, title
LIMIT 20;
"
echo " "

echo "6. Вывести 10 последних зарегистрированных пользователей в формате Фамилия Имя|Дата регистрации."
echo "--------------------------------------------------"
"$SQLITE" -box -echo movies_rating.db "
SELECT
    CASE
        WHEN instr(trim(name), ' ') > 0
        THEN substr(trim(name), instr(trim(name), ' ') + 1)
             || ' ' ||
             substr(trim(name), 1, instr(trim(name), ' ') - 1)
        ELSE trim(name)
    END || '|' || date(register_date) AS user_and_registration_date
FROM users
ORDER BY date(register_date) DESC, id DESC
LIMIT 10;
"
echo " "

echo "7. С помощью рекурсивного CTE вывести таблицу умножения для чисел от 1 до 10 в одном столбце."
echo "--------------------------------------------------"
"$SQLITE" -box -echo movies_rating.db "
WITH RECURSIVE numbers(n) AS (
    SELECT 1
    UNION ALL
    SELECT n + 1 FROM numbers WHERE n < 100
)
SELECT printf(
    '%dx%d=%d',
    (n - 1) / 10 + 1,
    (n - 1) % 10 + 1,
    ((n - 1) / 10 + 1) * ((n - 1) % 10 + 1)
) AS multiplication
FROM numbers;
"
echo " "

echo "8. С помощью рекурсивного CTE выделить все жанры из таблицы movies, каждый жанр в отдельной строке."
echo "--------------------------------------------------"
"$SQLITE" -box -echo movies_rating.db "
WITH RECURSIVE genre_split(movie_id, rest, genre) AS (
    SELECT id, genres || '|', ''
    FROM movies
    UNION ALL
    SELECT
        movie_id,
        substr(rest, instr(rest, '|') + 1),
        substr(rest, 1, instr(rest, '|') - 1)
    FROM genre_split
    WHERE rest <> ''
)
SELECT DISTINCT genre
FROM genre_split
WHERE genre <> ''
ORDER BY genre;
"
echo " "
