// The tables, exactly as drift creates them for `app/lib/data/db.dart`
// (schema 7): the same SQL text, so a database made by either version is
// the same file to the other. Columns are listed the way drift orders them:
// the sync columns of the `SyncColumns` mixin first, then the table's own.
//
// Versions (`PRAGMA user_version`), from `db.dart`'s `onUpgrade`:
//   1  task_lists, tasks, checklist_items
//   2  + key_values
//   3  + tasks.reminders, repeat_rule, repeat_from (reminders and repeat)
//   4  + tasks.duration (time spans)
//   5  + task_filters (saved filters); sync.cursor back to 0
//   6  + list_sections, tasks.section_id (sections); sync.cursor back to 0
//   7  + tasks.pinned_at (pinning)
//   8  + habits, habit_checkins, focus_sessions, countdowns (效率模块, the
//      Swift version's first); sync.cursor back to 0
//   9… the Swift version's next: add a step to `migrations`.
//
// The Flutter version can still open a version-8 database: drift runs its
// `onUpgrade` (nothing for `from` 8) and writes `user_version` back to 7,
// ignoring the new tables. Step 8 is safe to run again on that file
// (CREATE TABLE IF NOT EXISTS; one more pull from the start).

import GRDB

enum Schema {
    /// The version a new database is created at, and the newest this code
    /// knows how to upgrade to.
    static let version = 8

    static let createTaskLists = """
        CREATE TABLE IF NOT EXISTS "task_lists" ("created_at" INTEGER NOT NULL, "updated_at" INTEGER NOT NULL, \
        "deleted_at" INTEGER NULL, "server_version" INTEGER NOT NULL DEFAULT 0, "dirty" INTEGER NOT NULL DEFAULT 1 \
        CHECK ("dirty" IN (0, 1)), "id" TEXT NOT NULL, "name" TEXT NOT NULL, "emoji" TEXT NULL, "color" INTEGER NULL, \
        "sort_order" REAL NOT NULL DEFAULT 0.0, PRIMARY KEY ("id"));
        """

    static let createTasks = """
        CREATE TABLE IF NOT EXISTS "tasks" ("created_at" INTEGER NOT NULL, "updated_at" INTEGER NOT NULL, \
        "deleted_at" INTEGER NULL, "server_version" INTEGER NOT NULL DEFAULT 0, "dirty" INTEGER NOT NULL DEFAULT 1 \
        CHECK ("dirty" IN (0, 1)), "id" TEXT NOT NULL, "list_id" TEXT NOT NULL, "section_id" TEXT NULL, \
        "title" TEXT NOT NULL, "content" TEXT NOT NULL DEFAULT '', "priority" INTEGER NOT NULL DEFAULT 0, \
        "due_date" TEXT NULL, "due_time" INTEGER NULL, "duration" INTEGER NULL, "time_zone" TEXT NULL, \
        "tags" TEXT NOT NULL DEFAULT '[]', "status" INTEGER NOT NULL DEFAULT 0, "completed_at" INTEGER NULL, \
        "reminders" TEXT NOT NULL DEFAULT '[]', "repeat_rule" TEXT NULL, "repeat_from" INTEGER NOT NULL DEFAULT 0, \
        "pinned_at" INTEGER NULL, "trashed_at" INTEGER NULL, "sort_order" REAL NOT NULL DEFAULT 0.0, \
        PRIMARY KEY ("id"));
        """

    static let createChecklistItems = """
        CREATE TABLE IF NOT EXISTS "checklist_items" ("created_at" INTEGER NOT NULL, "updated_at" INTEGER NOT NULL, \
        "deleted_at" INTEGER NULL, "server_version" INTEGER NOT NULL DEFAULT 0, "dirty" INTEGER NOT NULL DEFAULT 1 \
        CHECK ("dirty" IN (0, 1)), "id" TEXT NOT NULL, "task_id" TEXT NOT NULL, "title" TEXT NOT NULL, \
        "done" INTEGER NOT NULL DEFAULT 0 CHECK ("done" IN (0, 1)), "sort_order" REAL NOT NULL DEFAULT 0.0, \
        PRIMARY KEY ("id"));
        """

    static let createTaskFilters = """
        CREATE TABLE IF NOT EXISTS "task_filters" ("created_at" INTEGER NOT NULL, "updated_at" INTEGER NOT NULL, \
        "deleted_at" INTEGER NULL, "server_version" INTEGER NOT NULL DEFAULT 0, "dirty" INTEGER NOT NULL DEFAULT 1 \
        CHECK ("dirty" IN (0, 1)), "id" TEXT NOT NULL, "name" TEXT NOT NULL, "rule" TEXT NOT NULL DEFAULT '{}', \
        "sort_order" REAL NOT NULL DEFAULT 0.0, PRIMARY KEY ("id"));
        """

    static let createListSections = """
        CREATE TABLE IF NOT EXISTS "list_sections" ("created_at" INTEGER NOT NULL, "updated_at" INTEGER NOT NULL, \
        "deleted_at" INTEGER NULL, "server_version" INTEGER NOT NULL DEFAULT 0, "dirty" INTEGER NOT NULL DEFAULT 1 \
        CHECK ("dirty" IN (0, 1)), "id" TEXT NOT NULL, "list_id" TEXT NOT NULL, "name" TEXT NOT NULL, \
        "sort_order" REAL NOT NULL DEFAULT 0.0, PRIMARY KEY ("id"));
        """

    static let createKeyValues = """
        CREATE TABLE IF NOT EXISTS "key_values" ("key" TEXT NOT NULL, "value" TEXT NOT NULL, PRIMARY KEY ("key"));
        """


    // MARK: Version 8: the efficiency module, in the same style.

    static let createHabits = """
        CREATE TABLE IF NOT EXISTS "habits" ("created_at" INTEGER NOT NULL, "updated_at" INTEGER NOT NULL, \
        "deleted_at" INTEGER NULL, "server_version" INTEGER NOT NULL DEFAULT 0, "dirty" INTEGER NOT NULL DEFAULT 1 \
        CHECK ("dirty" IN (0, 1)), "id" TEXT NOT NULL, "name" TEXT NOT NULL, "emoji" TEXT NULL, \
        "color" INTEGER NULL, "goal_kind" INTEGER NOT NULL DEFAULT 0, "goal" REAL NOT NULL DEFAULT 1.0, \
        "step" REAL NOT NULL DEFAULT 1.0, "unit" TEXT NOT NULL DEFAULT '', "frequency" TEXT NOT NULL DEFAULT 'FREQ=DAILY', \
        "reminders" TEXT NOT NULL DEFAULT '[]', "start_date" TEXT NOT NULL, "section" INTEGER NOT NULL DEFAULT 0, \
        "archived_at" INTEGER NULL, "sort_order" REAL NOT NULL DEFAULT 0.0, PRIMARY KEY ("id"));
        """

    static let createHabitCheckins = """
        CREATE TABLE IF NOT EXISTS "habit_checkins" ("created_at" INTEGER NOT NULL, "updated_at" INTEGER NOT NULL, \
        "deleted_at" INTEGER NULL, "server_version" INTEGER NOT NULL DEFAULT 0, "dirty" INTEGER NOT NULL DEFAULT 1 \
        CHECK ("dirty" IN (0, 1)), "id" TEXT NOT NULL, "habit_id" TEXT NOT NULL, \
        "day" TEXT NOT NULL, "value" REAL NOT NULL DEFAULT 0.0, "status" INTEGER NOT NULL DEFAULT 0, PRIMARY KEY ("id"));
        """

    static let createFocusSessions = """
        CREATE TABLE IF NOT EXISTS "focus_sessions" ("created_at" INTEGER NOT NULL, "updated_at" INTEGER NOT NULL, \
        "deleted_at" INTEGER NULL, "server_version" INTEGER NOT NULL DEFAULT 0, "dirty" INTEGER NOT NULL DEFAULT 1 \
        CHECK ("dirty" IN (0, 1)), "id" TEXT NOT NULL, "started_at" INTEGER NOT NULL, \
        "ended_at" INTEGER NOT NULL, "duration" INTEGER NOT NULL DEFAULT 0, "kind" INTEGER NOT NULL DEFAULT 0, \
        "completed" INTEGER NOT NULL DEFAULT 1 CHECK ("completed" IN (0, 1)), "task_id" TEXT NULL, "habit_id" TEXT NULL, \
        "note" TEXT NOT NULL DEFAULT '', PRIMARY KEY ("id"));
        """

    static let createCountdowns = """
        CREATE TABLE IF NOT EXISTS "countdowns" ("created_at" INTEGER NOT NULL, "updated_at" INTEGER NOT NULL, \
        "deleted_at" INTEGER NULL, "server_version" INTEGER NOT NULL DEFAULT 0, "dirty" INTEGER NOT NULL DEFAULT 1 \
        CHECK ("dirty" IN (0, 1)), "id" TEXT NOT NULL, "title" TEXT NOT NULL, \
        "kind" INTEGER NOT NULL DEFAULT 0, "date" TEXT NOT NULL, "lunar" INTEGER NOT NULL DEFAULT 0 CHECK ("lunar" IN (0, 1)), \
        "repeats" INTEGER NOT NULL DEFAULT 0, "emoji" TEXT NULL, "color" INTEGER NULL, \
        "show_in_today" INTEGER NOT NULL DEFAULT 0 CHECK ("show_in_today" IN (0, 1)), "reminders" TEXT NOT NULL DEFAULT '[]', \
        "pinned_at" INTEGER NULL, "sort_order" REAL NOT NULL DEFAULT 0.0, PRIMARY KEY ("id"));
        """

    static let efficiencyTables = [createHabits, createHabitCheckins, createFocusSessions, createCountdowns]

    /// drift's `createAll`, in its order, then the Swift version's tables.
    static func create(_ db: Database) throws {
        for sql in [createTaskLists, createTasks, createChecklistItems, createTaskFilters, createListSections, createKeyValues]
            + efficiencyTables {
            try db.execute(sql: sql)
        }
    }

    /// Step `n` takes a database at version `n - 1` to `n`. Together they
    /// are `onUpgrade`: drift's `if (from < n)` blocks, one step each (the
    /// cursor reset that `onUpgrade` does last for `from < 6` happens in
    /// step 6, which runs exactly when `from < 6`).
    static let migrations: [Int: @Sendable (Database) throws -> Void] = [
        2: { db in try db.execute(sql: createKeyValues) },
        3: { db in
            try addColumn(db, "tasks", #""reminders" TEXT NOT NULL DEFAULT '[]'"#)
            try addColumn(db, "tasks", #""repeat_rule" TEXT NULL"#)
            try addColumn(db, "tasks", #""repeat_from" INTEGER NOT NULL DEFAULT 0"#)
        },
        4: { db in try addColumn(db, "tasks", #""duration" INTEGER NULL"#) },
        5: { db in
            // Saved filters. An older version skipped filter records other
            // devices synced but still moved its cursor past them.
            try db.execute(sql: createTaskFilters)
            try resetCursor(db)
        },
        6: { db in
            // Sections (分组) in lists; the same cursor story.
            try db.execute(sql: createListSections)
            try addColumn(db, "tasks", #""section_id" TEXT NULL"#)
            try resetCursor(db)
        },
        7: { db in try addColumn(db, "tasks", #""pinned_at" INTEGER NULL"#) },
        8: { db in
            // New kinds of synced records: pull everything again once, so
            // ones another device synced before this version arrive.
            for sql in efficiencyTables { try db.execute(sql: sql) }
            try resetCursor(db)
        },
    ]

    /// Brings a database at `from` up to `version`. 0 is a new database.
    static func migrate(_ db: Database, from: Int) throws {
        if from == 0 {
            try create(db)
        } else if from < version {
            for step in (from + 1) ... version {
                try migrations[step]?(db)
            }
        }
        try db.execute(sql: "PRAGMA user_version = \(version)")
    }

    private static func addColumn(_ db: Database, _ table: String, _ definition: String) throws {
        try db.execute(sql: #"ALTER TABLE "\#(table)" ADD COLUMN \#(definition);"#)
    }

    private static func resetCursor(_ db: Database) throws {
        try db.execute(sql: "UPDATE key_values SET value = '0' WHERE key = 'sync.cursor'")
    }
}
