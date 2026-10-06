import csv
import re

DATASET_DIR = "dataset"
SQL_FILE = "Task02/db_init.sql"


def create_tables(sql):
    sql.write("DROP TABLE IF EXISTS movies;\n")
    sql.write("DROP TABLE IF EXISTS ratings;\n")
    sql.write("DROP TABLE IF EXISTS tags;\n")
    sql.write("DROP TABLE IF EXISTS users;\n\n")

    sql.write("""
CREATE TABLE movies (
    id INTEGER PRIMARY KEY,
    title TEXT,
    year INTEGER,
    genres TEXT
);

CREATE TABLE ratings (
    id INTEGER PRIMARY KEY,
    user_id INTEGER,
    movie_id INTEGER,
    rating REAL,
    timestamp INTEGER
);

CREATE TABLE tags (
    id INTEGER PRIMARY KEY,
    user_id INTEGER,
    movie_id INTEGER,
    tag TEXT,
    timestamp INTEGER
);

CREATE TABLE users (
    id INTEGER PRIMARY KEY,
    name TEXT,
    email TEXT,
    gender TEXT,
    register_date TEXT,
    occupation TEXT
);

""")


def load_movies(sql):
    with open(f"{DATASET_DIR}/movies.csv", "r", encoding="utf-8") as file:
        reader = csv.DictReader(file)

        for row in reader:
            match = re.search(r"\((\d{4})\)$", row["title"])

            if match:
                year = int(match.group(1))
                title = row["title"][:match.start()].strip()
            else:
                year = None
                title = row["title"]

            genres = row["genres"]

            sql.write(
                "INSERT INTO movies (id, title, year, genres) "
                f"VALUES ({int(row['movieId'])}, "
                f"'{title.replace(chr(39), chr(39) + chr(39))}', "
                f"{year if year is not None else 'NULL'}, "
                f"'{genres.replace(chr(39), chr(39) + chr(39))}');\n"
            )


def load_ratings(sql):
    with open(f"{DATASET_DIR}/ratings.csv", "r", encoding="utf-8") as file:
        reader = csv.DictReader(file)

        record_id = 1

        for row in reader:
            sql.write(
                "INSERT INTO ratings (id, user_id, movie_id, rating, timestamp) "
                f"VALUES ({record_id}, "
                f"{int(row['userId'])}, "
                f"{int(row['movieId'])}, "
                f"{float(row['rating'])}, "
                f"{int(row['timestamp'])});\n"
            )

            record_id += 1


def load_tags(sql):
    with open(f"{DATASET_DIR}/tags.csv", "r", encoding="utf-8") as file:
        reader = csv.DictReader(file)

        record_id = 1

        for row in reader:
            tag = row["tag"].replace(chr(39), chr(39) + chr(39))

            sql.write(
                "INSERT INTO tags (id, user_id, movie_id, tag, timestamp) "
                f"VALUES ({record_id}, "
                f"{int(row['userId'])}, "
                f"{int(row['movieId'])}, "
                f"'{tag}', "
                f"{int(row['timestamp'])});\n"
            )

            record_id += 1


def load_users(sql):
    with open(f"{DATASET_DIR}/users.txt", "r", encoding="utf-8") as file:
        for line in file:
            line = line.strip()

            if not line:
                continue

            fields = line.split("|")

            user_id = int(fields[0])
            name = fields[1].replace(chr(39), chr(39) + chr(39))
            email = fields[2].replace(chr(39), chr(39) + chr(39))
            gender = fields[3].replace(chr(39), chr(39) + chr(39))
            register_date = fields[4]
            occupation = fields[5].replace(chr(39), chr(39) + chr(39))

            sql.write(
                "INSERT INTO users "
                "(id, name, email, gender, register_date, occupation) "
                f"VALUES ({user_id}, "
                f"'{name}', "
                f"'{email}', "
                f"'{gender}', "
                f"'{register_date}', "
                f"'{occupation}');\n"
            )


with open(SQL_FILE, "w", encoding="utf-8") as sql:
    create_tables(sql)
    load_movies(sql)
    load_ratings(sql)
    load_tags(sql)
    load_users(sql)