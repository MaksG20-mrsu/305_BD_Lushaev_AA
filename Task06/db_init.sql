-- Лабораторная работа 6
-- База данных для автоматизации станции технического обслуживания автомобилей (СТО)
-- SQLite

PRAGMA foreign_keys = ON;

BEGIN TRANSACTION;

-- 1. Сотрудники (мастера).
-- Уволенных сотрудников не удаляем: заполняем termination_date,
-- чтобы сохранить историю записей, выполненных работ и зарплат.
CREATE TABLE employees (
    id                INTEGER PRIMARY KEY,
    first_name        TEXT NOT NULL CHECK (length(trim(first_name)) > 0),
    last_name         TEXT NOT NULL CHECK (length(trim(last_name)) > 0),
    middle_name       TEXT,
    phone             TEXT UNIQUE,
    email             TEXT NOT NULL UNIQUE,
    hire_date         TEXT NOT NULL DEFAULT (date('now')),
    termination_date  TEXT,
    commission_rate   REAL NOT NULL DEFAULT 30.0
                      CHECK (commission_rate BETWEEN 0 AND 100),
    created_at        TEXT NOT NULL DEFAULT (datetime('now')),
    CHECK (date(hire_date) IS NOT NULL),
    CHECK (termination_date IS NULL OR date(termination_date) IS NOT NULL),
    CHECK (termination_date IS NULL OR date(termination_date) > date(hire_date))
);

-- 2. Клиенты.
CREATE TABLE clients (
    id          INTEGER PRIMARY KEY,
    first_name  TEXT NOT NULL CHECK (length(trim(first_name)) > 0),
    last_name   TEXT NOT NULL CHECK (length(trim(last_name)) > 0),
    phone       TEXT NOT NULL UNIQUE,
    email       TEXT UNIQUE,
    notes       TEXT,
    created_at  TEXT NOT NULL DEFAULT (datetime('now'))
);

-- 3. Справочник услуг.
CREATE TABLE services (
    id               INTEGER PRIMARY KEY,
    name             TEXT NOT NULL UNIQUE CHECK (length(trim(name)) > 0),
    description      TEXT,
    duration_minutes INTEGER NOT NULL CHECK (duration_minutes > 0),
    price            REAL NOT NULL CHECK (price >= 0),
    is_active        INTEGER NOT NULL DEFAULT 1 CHECK (is_active IN (0, 1))
);

-- 4. Повторяющийся индивидуальный график мастеров.
-- weekday: 1 = понедельник, ... 7 = воскресенье.
CREATE TABLE employee_schedule (
    id          INTEGER PRIMARY KEY,
    employee_id INTEGER NOT NULL,
    weekday     INTEGER NOT NULL CHECK (weekday BETWEEN 1 AND 7),
    start_time  TEXT NOT NULL,
    end_time    TEXT NOT NULL,
    valid_from  TEXT NOT NULL DEFAULT (date('now')),
    valid_to    TEXT,
    FOREIGN KEY (employee_id) REFERENCES employees(id)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    CHECK (time(start_time) IS NOT NULL AND time(end_time) IS NOT NULL),
    CHECK (time(start_time) < time(end_time)),
    CHECK (date(valid_from) IS NOT NULL),
    CHECK (valid_to IS NULL OR date(valid_to) IS NOT NULL),
    CHECK (valid_to IS NULL OR date(valid_to) >= date(valid_from)),
    UNIQUE (employee_id, weekday, valid_from)
);

-- 5. Исключения из обычного графика: выходной или дополнительное/изменённое время.
CREATE TABLE schedule_exceptions (
    id             INTEGER PRIMARY KEY,
    employee_id    INTEGER NOT NULL,
    exception_date TEXT NOT NULL,
    exception_type TEXT NOT NULL
                   CHECK (exception_type IN ('day_off', 'working_hours')),
    start_time     TEXT,
    end_time       TEXT,
    reason         TEXT,
    FOREIGN KEY (employee_id) REFERENCES employees(id)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    CHECK (date(exception_date) IS NOT NULL),
    CHECK (
        (exception_type = 'day_off' AND start_time IS NULL AND end_time IS NULL)
        OR
        (exception_type = 'working_hours'
         AND start_time IS NOT NULL AND end_time IS NOT NULL
         AND time(start_time) IS NOT NULL AND time(end_time) IS NOT NULL
         AND time(start_time) < time(end_time))
    ),
    UNIQUE (employee_id, exception_date)
);

-- 6. Предварительные записи клиентов.
-- Время хранится в формате YYYY-MM-DD HH:MM:SS.
CREATE TABLE appointments (
    id          INTEGER PRIMARY KEY,
    client_id   INTEGER NOT NULL,
    employee_id INTEGER NOT NULL,
    starts_at   TEXT NOT NULL,
    ends_at     TEXT NOT NULL,
    status      TEXT NOT NULL DEFAULT 'booked'
                CHECK (status IN ('booked', 'confirmed', 'completed', 'cancelled', 'no_show')),
    notes       TEXT,
    created_at  TEXT NOT NULL DEFAULT (datetime('now')),
    FOREIGN KEY (client_id) REFERENCES clients(id)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    FOREIGN KEY (employee_id) REFERENCES employees(id)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    CHECK (datetime(starts_at) IS NOT NULL AND datetime(ends_at) IS NOT NULL),
    CHECK (datetime(ends_at) > datetime(starts_at)),
    CHECK (date(starts_at) = date(ends_at))
);

-- 7. Услуги, выбранные при предварительной записи.
-- Цена и длительность копируются из справочника на момент записи.
CREATE TABLE appointment_services (
    appointment_id         INTEGER NOT NULL,
    service_id             INTEGER NOT NULL,
    quantity               INTEGER NOT NULL DEFAULT 1 CHECK (quantity > 0),
    price_at_booking       REAL NOT NULL CHECK (price_at_booking >= 0),
    duration_at_booking    INTEGER NOT NULL CHECK (duration_at_booking > 0),
    PRIMARY KEY (appointment_id, service_id),
    FOREIGN KEY (appointment_id) REFERENCES appointments(id)
        ON UPDATE CASCADE ON DELETE CASCADE,
    FOREIGN KEY (service_id) REFERENCES services(id)
        ON UPDATE CASCADE ON DELETE RESTRICT
);

-- 8. Заказы/работы, которые мастер фактически выполнил.
-- Ставка комиссии фиксируется на момент выполнения заказа.
CREATE TABLE work_orders (
    id                       INTEGER PRIMARY KEY,
    appointment_id           INTEGER NOT NULL UNIQUE,
    employee_id              INTEGER NOT NULL,
    started_at               TEXT NOT NULL,
    ended_at                 TEXT NOT NULL,
    status                   TEXT NOT NULL DEFAULT 'completed'
                             CHECK (status IN ('in_progress', 'completed', 'cancelled')),
    commission_rate_snapshot REAL NOT NULL
                             CHECK (commission_rate_snapshot BETWEEN 0 AND 100),
    completed_at             TEXT,
    notes                    TEXT,
    created_at               TEXT NOT NULL DEFAULT (datetime('now')),
    FOREIGN KEY (appointment_id) REFERENCES appointments(id)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    FOREIGN KEY (employee_id) REFERENCES employees(id)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    CHECK (datetime(started_at) IS NOT NULL AND datetime(ended_at) IS NOT NULL),
    CHECK (datetime(ended_at) > datetime(started_at)),
    CHECK (
        (status = 'completed' AND completed_at IS NOT NULL AND datetime(completed_at) IS NOT NULL)
        OR
        (status IN ('in_progress', 'cancelled') AND completed_at IS NULL)
    )
);

-- 9. Фактически выполненные услуги по каждому заказу.
-- line_total рассчитывается автоматически по сохранённой цене и количеству.
CREATE TABLE work_order_services (
    work_order_id INTEGER NOT NULL,
    service_id    INTEGER NOT NULL,
    quantity      INTEGER NOT NULL DEFAULT 1 CHECK (quantity > 0),
    unit_price    REAL NOT NULL CHECK (unit_price >= 0),
    duration_minutes INTEGER NOT NULL CHECK (duration_minutes > 0),
    line_total    REAL GENERATED ALWAYS AS (quantity * unit_price) STORED,
    PRIMARY KEY (work_order_id, service_id),
    FOREIGN KEY (work_order_id) REFERENCES work_orders(id)
        ON UPDATE CASCADE ON DELETE CASCADE,
    FOREIGN KEY (service_id) REFERENCES services(id)
        ON UPDATE CASCADE ON DELETE RESTRICT
);

-- 10. Начисления и выплаты зарплаты за выбранный период.
-- Сумму можно рассчитать по work_orders и work_order_services;
-- здесь сохраняется итог расчёта и состояние выплаты.
CREATE TABLE salary_payments (
    id             INTEGER PRIMARY KEY,
    employee_id    INTEGER NOT NULL,
    period_start   TEXT NOT NULL,
    period_end     TEXT NOT NULL,
    revenue_amount REAL NOT NULL CHECK (revenue_amount >= 0),
    salary_amount  REAL NOT NULL CHECK (salary_amount >= 0),
    status         TEXT NOT NULL DEFAULT 'accrued' CHECK (status IN ('accrued', 'paid')),
    paid_at        TEXT,
    created_at     TEXT NOT NULL DEFAULT (datetime('now')),
    FOREIGN KEY (employee_id) REFERENCES employees(id)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    CHECK (date(period_start) IS NOT NULL AND date(period_end) IS NOT NULL),
    CHECK (date(period_end) >= date(period_start)),
    CHECK (
        (status = 'paid' AND paid_at IS NOT NULL AND datetime(paid_at) IS NOT NULL)
        OR
        (status = 'accrued' AND paid_at IS NULL)
    ),
    UNIQUE (employee_id, period_start, period_end)
);

-- Проверка сотрудника, графика и занятости при создании записи.
CREATE TRIGGER trg_appointments_validate_insert
BEFORE INSERT ON appointments
WHEN NEW.status <> 'cancelled'
BEGIN
    SELECT CASE
        WHEN NOT EXISTS (
            SELECT 1
            FROM employees e
            WHERE e.id = NEW.employee_id
              AND date(NEW.starts_at) >= date(e.hire_date)
              AND (e.termination_date IS NULL OR date(NEW.starts_at) < date(e.termination_date))
        )
        THEN RAISE(ABORT, 'Employee is not employed on appointment date')
    END;

    SELECT CASE
        WHEN EXISTS (
            SELECT 1 FROM schedule_exceptions x
            WHERE x.employee_id = NEW.employee_id
              AND date(x.exception_date) = date(NEW.starts_at)
              AND x.exception_type = 'day_off'
        )
        THEN RAISE(ABORT, 'Employee has a day off on this date')

        WHEN EXISTS (
            SELECT 1 FROM schedule_exceptions x
            WHERE x.employee_id = NEW.employee_id
              AND date(x.exception_date) = date(NEW.starts_at)
              AND x.exception_type = 'working_hours'
        )
        AND NOT EXISTS (
            SELECT 1 FROM schedule_exceptions x
            WHERE x.employee_id = NEW.employee_id
              AND date(x.exception_date) = date(NEW.starts_at)
              AND x.exception_type = 'working_hours'
              AND time(NEW.starts_at) >= time(x.start_time)
              AND time(NEW.ends_at) <= time(x.end_time)
        )
        THEN RAISE(ABORT, 'Appointment is outside exception working hours')

        WHEN NOT EXISTS (
            SELECT 1 FROM schedule_exceptions x
            WHERE x.employee_id = NEW.employee_id
              AND date(x.exception_date) = date(NEW.starts_at)
        )
        AND NOT EXISTS (
            SELECT 1 FROM employee_schedule s
            WHERE s.employee_id = NEW.employee_id
              AND s.weekday = ((CAST(strftime('%w', NEW.starts_at) AS INTEGER) + 6) % 7) + 1
              AND date(NEW.starts_at) >= date(s.valid_from)
              AND (s.valid_to IS NULL OR date(NEW.starts_at) <= date(s.valid_to))
              AND time(NEW.starts_at) >= time(s.start_time)
              AND time(NEW.ends_at) <= time(s.end_time)
        )
        THEN RAISE(ABORT, 'Appointment is outside employee schedule')
    END;

    SELECT CASE
        WHEN EXISTS (
            SELECT 1 FROM appointments a
            WHERE a.employee_id = NEW.employee_id
              AND a.status <> 'cancelled'
              AND datetime(NEW.starts_at) < datetime(a.ends_at)
              AND datetime(NEW.ends_at) > datetime(a.starts_at)
        )
        THEN RAISE(ABORT, 'Employee already has an appointment at this time')
    END;
END;

-- Аналогичная проверка при изменении времени, мастера или статуса записи.
CREATE TRIGGER trg_appointments_validate_update
BEFORE UPDATE OF employee_id, starts_at, ends_at, status ON appointments
WHEN NEW.status <> 'cancelled'
BEGIN
    SELECT CASE
        WHEN NOT EXISTS (
            SELECT 1
            FROM employees e
            WHERE e.id = NEW.employee_id
              AND date(NEW.starts_at) >= date(e.hire_date)
              AND (e.termination_date IS NULL OR date(NEW.starts_at) < date(e.termination_date))
        )
        THEN RAISE(ABORT, 'Employee is not employed on appointment date')
    END;

    SELECT CASE
        WHEN EXISTS (
            SELECT 1 FROM schedule_exceptions x
            WHERE x.employee_id = NEW.employee_id
              AND date(x.exception_date) = date(NEW.starts_at)
              AND x.exception_type = 'day_off'
        )
        THEN RAISE(ABORT, 'Employee has a day off on this date')

        WHEN EXISTS (
            SELECT 1 FROM schedule_exceptions x
            WHERE x.employee_id = NEW.employee_id
              AND date(x.exception_date) = date(NEW.starts_at)
              AND x.exception_type = 'working_hours'
        )
        AND NOT EXISTS (
            SELECT 1 FROM schedule_exceptions x
            WHERE x.employee_id = NEW.employee_id
              AND date(x.exception_date) = date(NEW.starts_at)
              AND x.exception_type = 'working_hours'
              AND time(NEW.starts_at) >= time(x.start_time)
              AND time(NEW.ends_at) <= time(x.end_time)
        )
        THEN RAISE(ABORT, 'Appointment is outside exception working hours')

        WHEN NOT EXISTS (
            SELECT 1 FROM schedule_exceptions x
            WHERE x.employee_id = NEW.employee_id
              AND date(x.exception_date) = date(NEW.starts_at)
        )
        AND NOT EXISTS (
            SELECT 1 FROM employee_schedule s
            WHERE s.employee_id = NEW.employee_id
              AND s.weekday = ((CAST(strftime('%w', NEW.starts_at) AS INTEGER) + 6) % 7) + 1
              AND date(NEW.starts_at) >= date(s.valid_from)
              AND (s.valid_to IS NULL OR date(NEW.starts_at) <= date(s.valid_to))
              AND time(NEW.starts_at) >= time(s.start_time)
              AND time(NEW.ends_at) <= time(s.end_time)
        )
        THEN RAISE(ABORT, 'Appointment is outside employee schedule')
    END;

    SELECT CASE
        WHEN EXISTS (
            SELECT 1 FROM appointments a
            WHERE a.employee_id = NEW.employee_id
              AND a.id <> OLD.id
              AND a.status <> 'cancelled'
              AND datetime(NEW.starts_at) < datetime(a.ends_at)
              AND datetime(NEW.ends_at) > datetime(a.starts_at)
        )
        THEN RAISE(ABORT, 'Employee already has an appointment at this time')
    END;
END;

-- Заказ должен относиться к тому же мастеру и попадать во временной интервал записи.
CREATE TRIGGER trg_work_orders_validate_insert
BEFORE INSERT ON work_orders
BEGIN
    SELECT CASE
        WHEN NOT EXISTS (
            SELECT 1 FROM appointments a
            WHERE a.id = NEW.appointment_id
              AND a.employee_id = NEW.employee_id
              AND a.status NOT IN ('cancelled', 'no_show')
              AND datetime(NEW.started_at) >= datetime(a.starts_at)
              AND datetime(NEW.ended_at) <= datetime(a.ends_at)
        )
        THEN RAISE(ABORT, 'Work order does not match its appointment')
    END;
END;

-- При завершении заказа помечаем предварительную запись как выполненную.
CREATE TRIGGER trg_work_orders_mark_appointment_completed
AFTER INSERT ON work_orders
WHEN NEW.status = 'completed'
BEGIN
    UPDATE appointments
    SET status = 'completed'
    WHERE id = NEW.appointment_id
      AND status IN ('booked', 'confirmed');
END;

-- Индексы для частых поисковых запросов и отчётов.
CREATE INDEX idx_employees_last_name ON employees(last_name);
CREATE INDEX idx_appointments_employee_time ON appointments(employee_id, starts_at, ends_at);
CREATE INDEX idx_appointments_client ON appointments(client_id);
CREATE INDEX idx_work_orders_employee_completed ON work_orders(employee_id, completed_at);
CREATE INDEX idx_work_order_services_service ON work_order_services(service_id);
CREATE INDEX idx_salary_payments_employee_period ON salary_payments(employee_id, period_start, period_end);

-- ------------------------------------------------------------
-- ТЕСТОВЫЕ ДАННЫЕ
-- ------------------------------------------------------------

INSERT INTO employees
    (id, first_name, last_name, middle_name, phone, email, hire_date, termination_date, commission_rate)
VALUES
    (1, 'Иван',   'Петров',    'Сергеевич', '+7-900-100-10-01', 'petrov@example.com',    '2022-05-10', NULL,         35.0),
    (2, 'Анна',   'Смирнова',  'Игоревна',  '+7-900-100-10-02', 'smirnova@example.com', '2023-02-20', NULL,         30.0),
    (3, 'Сергей', 'Кузнецов',  'Олегович',  '+7-900-100-10-03', 'kuznetsov@example.com','2021-09-01', NULL,         40.0),
    (4, 'Олег',   'Волков',    'Андреевич', '+7-900-100-10-04', 'volkov@example.com',   '2020-03-15', '2026-11-01', 32.0);

INSERT INTO clients (id, first_name, last_name, phone, email, notes)
VALUES
    (1, 'Дмитрий', 'Орлов',      '+7-901-200-20-01', 'orlov@example.com',      'Предпочитает утреннее время'),
    (2, 'Мария',   'Соколова',   '+7-901-200-20-02', 'sokolova@example.com',   NULL),
    (3, 'Павел',   'Морозов',    '+7-901-200-20-03', 'morozov@example.com',    'Постоянный клиент'),
    (4, 'Елена',   'Фёдорова',   '+7-901-200-20-04', 'fedorova@example.com',   NULL);

INSERT INTO services (id, name, description, duration_minutes, price, is_active)
VALUES
    (1, 'Компьютерная диагностика', 'Диагностика электронных систем автомобиля', 30, 1500.00, 1),
    (2, 'Замена масла',              'Замена моторного масла и масляного фильтра', 45, 2500.00, 1),
    (3, 'Шиномонтаж',                'Снятие, установка и балансировка колёс',    60, 3500.00, 1),
    (4, 'Замена тормозных колодок',  'Замена комплекта тормозных колодок',         90, 6000.00, 1),
    (5, 'Развал-схождение',          'Регулировка углов установки колёс',           60, 3000.00, 1),
    (6, 'Замена аккумулятора',       'Снятие старого и установка нового АКБ',      30, 1200.00, 1);

-- График мастеров с понедельника по пятницу.
INSERT INTO employee_schedule (employee_id, weekday, start_time, end_time, valid_from, valid_to)
VALUES
    (1, 1, '09:00', '18:00', '2022-05-10', NULL),
    (1, 2, '09:00', '18:00', '2022-05-10', NULL),
    (1, 3, '09:00', '18:00', '2022-05-10', NULL),
    (1, 4, '09:00', '18:00', '2022-05-10', NULL),
    (1, 5, '09:00', '18:00', '2022-05-10', NULL),
    (2, 1, '10:00', '19:00', '2023-02-20', NULL),
    (2, 2, '10:00', '19:00', '2023-02-20', NULL),
    (2, 3, '10:00', '19:00', '2023-02-20', NULL),
    (2, 4, '10:00', '19:00', '2023-02-20', NULL),
    (2, 5, '10:00', '19:00', '2023-02-20', NULL),
    (3, 1, '09:00', '17:00', '2021-09-01', NULL),
    (3, 2, '09:00', '17:00', '2021-09-01', NULL),
    (3, 3, '09:00', '17:00', '2021-09-01', NULL),
    (3, 4, '09:00', '17:00', '2021-09-01', NULL),
    (3, 5, '09:00', '17:00', '2021-09-01', NULL),
    (4, 1, '09:00', '18:00', '2020-03-15', '2026-10-31'),
    (4, 2, '09:00', '18:00', '2020-03-15', '2026-10-31'),
    (4, 3, '09:00', '18:00', '2020-03-15', '2026-10-31'),
    (4, 4, '09:00', '18:00', '2020-03-15', '2026-10-31'),
    (4, 5, '09:00', '18:00', '2020-03-15', '2026-10-31');

INSERT INTO schedule_exceptions
    (employee_id, exception_date, exception_type, start_time, end_time, reason)
VALUES
    (2, '2026-11-27', 'day_off', NULL, NULL, 'Личный выходной'),
    (1, '2026-11-28', 'working_hours', '10:00', '14:00', 'Дополнительная рабочая смена');

-- Записи на 24 ноября 2026 года и одна будущая запись на 26 ноября.
INSERT INTO appointments
    (id, client_id, employee_id, starts_at, ends_at, status, notes)
VALUES
    (1, 1, 1, '2026-11-24 09:00:00', '2026-11-24 10:30:00', 'completed', 'Диагностика и замена масла'),
    (2, 2, 2, '2026-11-24 11:00:00', '2026-11-24 13:00:00', 'completed', 'Проверка тормозной системы'),
    (3, 3, 3, '2026-11-24 13:00:00', '2026-11-24 14:00:00', 'completed', 'Сезонный шиномонтаж'),
    (4, 4, 4, '2026-10-27 10:00:00', '2026-10-27 11:30:00', 'completed', 'Историческая запись у бывшего сотрудника'),
    (5, 1, 1, '2026-11-26 15:00:00', '2026-11-26 16:00:00', 'booked', 'Предварительная запись на развал-схождение');

INSERT INTO appointment_services
    (appointment_id, service_id, quantity, price_at_booking, duration_at_booking)
VALUES
    (1, 1, 1, 1500.00, 30),
    (1, 2, 1, 2500.00, 45),
    (2, 4, 1, 6000.00, 90),
    (3, 3, 1, 3500.00, 60),
    (4, 4, 1, 5500.00, 90),
    (5, 5, 1, 3000.00, 60);

INSERT INTO work_orders
    (id, appointment_id, employee_id, started_at, ended_at, status,
     commission_rate_snapshot, completed_at, notes)
VALUES
    (1, 1, 1, '2026-11-24 09:05:00', '2026-11-24 10:20:00', 'completed', 35.0, '2026-11-24 10:20:00', 'Работа выполнена'),
    (2, 2, 2, '2026-11-24 11:05:00', '2026-11-24 12:25:00', 'completed', 30.0, '2026-11-24 12:25:00', 'Работа выполнена'),
    (3, 3, 3, '2026-11-24 13:00:00', '2026-11-24 13:55:00', 'completed', 40.0, '2026-11-24 13:55:00', 'Работа выполнена'),
    (4, 4, 4, '2026-10-27 10:05:00', '2026-10-27 11:20:00', 'completed', 32.0, '2026-10-27 11:20:00', 'Историческая работа бывшего сотрудника');

INSERT INTO work_order_services
    (work_order_id, service_id, quantity, unit_price, duration_minutes)
VALUES
    (1, 1, 1, 1500.00, 30),
    (1, 2, 1, 2500.00, 45),
    (2, 4, 1, 6000.00, 90),
    (3, 3, 1, 3500.00, 60),
    (4, 4, 1, 5500.00, 90);

INSERT INTO salary_payments
    (employee_id, period_start, period_end, revenue_amount, salary_amount, status, paid_at)
VALUES
    (1, '2026-11-01', '2026-11-30', 4000.00, 1400.00, 'accrued', NULL),
    (4, '2026-10-01', '2026-10-31', 5500.00, 1760.00, 'paid', '2026-11-05 12:00:00');

COMMIT;

-- Пример расчёта выручки и зарплаты мастеров за произвольный период.
-- Замените даты в условии WHERE на нужные границы периода.
-- Зарплата рассчитывается по ставке, сохранённой в заказе на момент выполнения.
--
-- SELECT
--     e.id,
--     e.last_name || ' ' || e.first_name AS master,
--     SUM(wos.line_total) AS revenue,
--     ROUND(SUM(wos.line_total * wo.commission_rate_snapshot / 100.0), 2) AS salary
-- FROM employees e
-- JOIN work_orders wo ON wo.employee_id = e.id AND wo.status = 'completed'
-- JOIN work_order_services wos ON wos.work_order_id = wo.id
-- WHERE date(wo.completed_at) BETWEEN '2026-11-01' AND '2026-11-30'
-- GROUP BY e.id, e.last_name, e.first_name
-- ORDER BY master;
