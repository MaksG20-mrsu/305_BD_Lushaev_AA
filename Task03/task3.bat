
#!/bin/bash
chcp 65001 2>/dev/null || true

if command -v sqlite3 >/dev/null 2>&1; then
    SQLITE="sqlite3"
elif [ -x "/c/Users/alexandr/Desktop/sqlite/sqlite3.exe" ]; then
    SQLITE="/c/Users/alexandr/Desktop/sqlite/sqlite3.exe"
else
    echo "SQLite не найден. Установите SQLite и добавьте его в PATH."
    exit 1
fi

"$SQLITE" movies_rating.db < db_init.sql

echo "1. Составить список фильмов, имеющих хотя бы одну оценку. Отсортировать по году выпуска и названию. Оставить первые 10 фильмов."
echo "--------------------------------------------------"
"$SQLITE" -box -echo movies_rating.db "SELECT m.title, m.year
FROM movies AS m
WHERE EXISTS (SELECT 1 FROM ratings AS r WHERE r.movie_id = m.id)
ORDER BY (m.year IS NULL), m.year, m.title
LIMIT 10;"
echo " "

echo "2. Вывести пользователей, фамилии которых начинаются на букву A. Отсортировать по дате регистрации. Оставить первых 5 пользователей."
echo "--------------------------------------------------"
"$SQLITE" -box -echo movies_rating.db "SELECT name, register_date
FROM users
WHERE UPPER(SUBSTR(TRIM(name), INSTR(TRIM(name), ' ') + 1, 1)) = 'A'
ORDER BY register_date
LIMIT 5;"
echo " "

echo "3. Вывести имя и фамилию эксперта, название фильма, год выпуска, оценку и дату оценки в формате ГГГГ-ММ-ДД. Отсортировать по имени эксперта, названию фильма и оценке. Оставить первые 50 записей."
echo "--------------------------------------------------"
"$SQLITE" -box -echo movies_rating.db "SELECT u.name AS expert, m.title, m.year,
       r.rating, DATE(r.timestamp, 'unixepoch') AS rating_date
FROM ratings AS r
JOIN users AS u ON u.id = r.user_id
JOIN movies AS m ON m.id = r.movie_id
ORDER BY u.name, m.title, r.rating
LIMIT 50;"
echo " "

echo "4. Вывести фильмы и присвоенные им теги. Сортировать по году выпуска, названию фильма и тегу. Оставить первые 40 записей."
echo "--------------------------------------------------"
"$SQLITE" -box -echo movies_rating.db "SELECT m.title, m.year, t.tag
FROM movies AS m
JOIN tags AS t ON t.movie_id = m.id
ORDER BY (m.year IS NULL), m.year, m.title, t.tag
LIMIT 40;"
echo " "

echo "5. Вывести все фильмы самого позднего года выпуска, определив этот год непосредственно в запросе."
echo "--------------------------------------------------"
"$SQLITE" -box -echo movies_rating.db "SELECT title, year
FROM movies
WHERE year = (SELECT MAX(year) FROM movies WHERE year IS NOT NULL)
ORDER BY title;"
echo " "

echo "6. Найти комедии после 2000 года, получившие оценки не ниже 4.5 от мужчин. Вывести название, год и количество таких оценок."
echo "--------------------------------------------------"
"$SQLITE" -box -echo movies_rating.db "SELECT m.title, m.year, COUNT(*) AS positive_ratings
FROM movies AS m
JOIN ratings AS r ON r.movie_id = m.id
JOIN users AS u ON u.id = r.user_id
WHERE m.year > 2000
  AND ('|' || m.genres || '|') LIKE '%|Comedy|%'
  AND LOWER(u.gender) = 'male'
  AND r.rating >= 4.5
GROUP BY m.id, m.title, m.year
ORDER BY (m.year IS NULL), m.year, m.title;"
echo " "

echo "7. Посчитать пользователей по профессиям и определить самую распространенную и самую редкую профессию."
echo "--------------------------------------------------"
"$SQLITE" -box -echo movies_rating.db "WITH occupation_counts AS (
    SELECT occupation, COUNT(*) AS user_count
    FROM users
    GROUP BY occupation
)
SELECT occupation, user_count,
       CASE
           WHEN user_count = (SELECT MAX(user_count) FROM occupation_counts)
               THEN 'Самая распространенная'
           WHEN user_count = (SELECT MIN(user_count) FROM occupation_counts)
               THEN 'Самая редкая'
           ELSE ''
       END AS result
FROM occupation_counts
ORDER BY user_count DESC, occupation;"
echo " "
