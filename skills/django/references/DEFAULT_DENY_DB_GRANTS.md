# Default-deny database grants, declared per table

Runtime roles get nothing by default. Each app declares what each role may do with each of its tables, in `grants.py` beside its models. Provisioning and migrations make the live privileges equal that declaration, and CI fails on any difference.

Measured on PostgreSQL 17 with the baseline and converge code below. The runtime role was refused, with SQLSTATE `42501`, on every undeclared action:

- SELECT of an undeclared column;
- UPDATE of a column outside the declared list;
- DELETE on an append-only outbox;
- `CREATE TABLE` in `public`;
- calling a function.

Every declared action succeeded. A stray table-level `GRANT SELECT` and a `GRANT … TO PUBLIC` were revoked on the first converge run. A second run changed nothing.

## 1. The baseline: nothing is granted by default

Run as the database owner (the migrator role) when the database is created:

```sql
REVOKE ALL ON DATABASE app FROM PUBLIC;
REVOKE ALL ON SCHEMA public FROM PUBLIC;            -- includes CREATE; PG <= 14 granted it to PUBLIC
REVOKE ALL ON ALL TABLES IN SCHEMA public FROM PUBLIC;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA public FROM PUBLIC;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA public FROM PUBLIC;
ALTER DEFAULT PRIVILEGES FOR ROLE migrator REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;  -- functions default to PUBLIC EXECUTE
GRANT CONNECT ON DATABASE app TO app_web, app_worker;
GRANT USAGE ON SCHEMA public TO app_web, app_worker;
```

- **Runtime roles own nothing and cannot CREATE.** Use `NOCREATEDB NOCREATEROLE`, no ownership, and no CREATE on any schema. The migrator owns the tables. An owner can always grant itself anything back, so a runtime role that owns a table bypasses this whole design.
- **`ALTER DEFAULT PRIVILEGES` grants nothing.** A default grant puts privileges on every future table without a declaration, which is the opposite of this pattern.

## 2. The declaration: `grants.py` beside the models

```python
# orders/grants.py
GRANTS = {
    "orders_order": {
        "web": {"select": True, "insert": True, "update": ["status", "updated_at"]},
        "worker": {"select": ["id", "status"], "update": ["status", "updated_at"]},
    },
    # Append-only history (an outbox): insert, then move the status. No DELETE, no payload edits.
    "orders_outbox": {
        "web": {"select": ["id"], "insert": True},
        "worker": {"select": True, "update": ["status", "attempts", "sent_at"]},
    },
}
```

The shape is `GRANTS = {"<db_table>": {"<role_kind>": {"select": True | [cols], "insert": True | [cols], "update": [cols] | False, "delete": bool}}}`.

- **A missing key means no privilege.** `"delete"` absent = no DELETE.
- **A column list becomes a column-level grant:** `GRANT UPDATE (status, updated_at) ON …`.
- **Role kinds, not role names.** A mapping like `{"web": "app_web"}` per environment or per tenant DB resolves them, so the declaration stays the same everywhere.

Django facts that shape the declaration, each one tested:

| Django does                                                                    | So the role needs                                                                   |
| ------------------------------------------------------------------------------ | ----------------------------------------------------------------------------------- |
| `INSERT … RETURNING id` on every `create()` / `save()` of a new row            | SELECT on the pk column (`"select": ["id"]` is enough)                              |
| `UPDATE … WHERE id = %s` on `save()`                                           | SELECT on the pk column                                                             |
| `save()` without `update_fields` writes **every** column                       | column-limited UPDATE only works with `save(update_fields=[...])` or `.update(...)` |
| `AutoField` / `BigAutoField` are identity columns on PostgreSQL (Django ≥ 4.1) | no sequence privilege                                                               |
| an older `serial` column                                                       | `USAGE` on its sequence, or the insert fails with `permission denied for sequence`  |
| M2M fields create a through table (`app_model_field`)                          | a declaration of its own; it has no `models.py` class of its own                    |

## 3. Converge: make the live privileges equal the declaration

```python
# core/db_grants.py
from psycopg import sql

PRIVILEGES = ("select", "insert", "update", "delete")

# Every table-level and column-level ACL entry in one schema, PUBLIC included.
# Reads pg_class.relacl / pg_attribute.attacl directly: the information_schema
# views only show grants where the *current* role is grantor or grantee.
LIVE_SQL = """
SELECT coalesce(r.rolname, 'PUBLIC'), c.relname, a.privilege_type, NULL::name
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
CROSS JOIN LATERAL aclexplode(c.relacl) a
LEFT JOIN pg_roles r ON r.oid = a.grantee
WHERE n.nspname = %(schema)s AND c.relkind IN ('r', 'p', 'v', 'm')
  AND a.grantee <> c.relowner
UNION ALL
SELECT coalesce(r.rolname, 'PUBLIC'), c.relname, a.privilege_type, att.attname
FROM pg_attribute att
JOIN pg_class c ON c.oid = att.attrelid
JOIN pg_namespace n ON n.oid = c.relnamespace
CROSS JOIN LATERAL aclexplode(att.attacl) a
LEFT JOIN pg_roles r ON r.oid = a.grantee
WHERE n.nspname = %(schema)s AND att.attnum > 0 AND NOT att.attisdropped
  AND a.grantee <> c.relowner
"""


def declared(grants, role_for_kind):
    """GRANTS dict -> {(role, table, PRIVILEGE, column_or_None)}."""
    out = set()
    for table, kinds in grants.items():
        for kind, privs in kinds.items():
            role = role_for_kind[kind]
            for priv in PRIVILEGES:
                value = privs.get(priv, False)  # missing key = no privilege
                if value is True:
                    out.add((role, table, priv.upper(), None))
                elif value:
                    if priv == "delete":
                        raise ValueError(f"{table}: DELETE has no column form")
                    out.update((role, table, priv.upper(), col) for col in value)
    return out


def live(conn, schema="public"):
    with conn.cursor() as cur:
        cur.execute(LIVE_SQL, {"schema": schema})
        return {tuple(row) for row in cur.fetchall()}


def _stmt(verb, role, table, priv, column, schema):
    cols = sql.SQL("") if column is None else sql.SQL(" ({})").format(sql.Identifier(column))
    grantee = sql.SQL("PUBLIC") if role == "PUBLIC" else sql.Identifier(role)
    return sql.SQL("{verb} {priv}{cols} ON {tbl} {prep} {grantee}").format(
        verb=sql.SQL(verb), priv=sql.SQL(priv), cols=cols,
        tbl=sql.Identifier(schema, table),
        prep=sql.SQL("TO" if verb == "GRANT" else "FROM"), grantee=grantee,
    )


def converge(conn, grants, role_for_kind, schema="public"):
    """Make live ACLs equal the declaration. Idempotent: a second run returns ([], [])."""
    want = declared(grants, role_for_kind)
    revoked = sorted(live(conn, schema) - want, key=str)
    with conn.cursor() as cur:
        for role, table, priv, column in revoked:
            cur.execute(_stmt("REVOKE", role, table, priv, column, schema))
    # Re-read: a table-level REVOKE also strips that privilege from every column,
    # so column grants that were correct before the revoke may be gone now.
    granted = sorted(want - live(conn, schema), key=str)
    with conn.cursor() as cur:
        for role, table, priv, column in granted:
            cur.execute(_stmt("GRANT", role, table, priv, column, schema))
    return granted, revoked
```

- **Revoke first, re-read, then grant.** Computing both lists from one snapshot loses column grants. PostgreSQL's `REVOKE SELECT ON t` also removes `SELECT (col)` on each of `t`'s columns.
- **Converge runs at provisioning and after every migrate,** as the migrator, through a raw psycopg connection (`connection.connection` inside Django, autocommit on). A `post_migrate` handler filtered to one app's `sender` runs it once per database.
- **Collect `GRANTS` from every installed app.** Catch only the missing module itself (`except ModuleNotFoundError as e: if e.name != f"{app.name}.grants": raise`). A bare `except ImportError` hides a typo inside `grants.py`. Under default-deny that app's tables then go silently ungranted, and the first sign is a refused query in production.

## 4. CI: the declaration and the database must agree

| Test                    | How                                                                                                                                                                                                                                                                                 |
| ----------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Every table is declared | every `model._meta.db_table` from `apps.get_models(include_auto_created=True)`, so M2M through tables count, plus every table in `connection.introspection.table_names()` that Django does not own, must appear in the merged `GRANTS`, except `django_migrations` (migrator only). |
| Live equals declared    | after `migrate`: `live(conn) == declared(GRANTS, ROLE_FOR_KIND)`. **Equal**, not "contains": an extra grant is the failure this exists to catch.                                                                                                                                    |
| No default privileges   | the query below returns zero rows                                                                                                                                                                                                                                                   |
| Refusals hold           | connect **as the runtime role** and assert `psycopg.errors.InsufficientPrivilege` (SQLSTATE `42501`) for an undeclared column, DELETE on the outbox, `CREATE TABLE`. One success case per role keeps the test honest.                                                               |

```sql
-- default ACLs granting to anyone but the owner: must be empty
SELECT pg_get_userbyid(d.defaclrole) AS owner, d.defaclobjtype,
       coalesce(pg_get_userbyid(nullif(a.grantee, 0)), 'PUBLIC') AS grantee, a.privilege_type
FROM pg_default_acl d CROSS JOIN LATERAL aclexplode(d.defaclacl) a
WHERE a.grantee <> d.defaclrole;
```

`information_schema.role_table_grants` and `column_privileges` work for spot checks. Two traps keep them out of the equality test. They show only grants where the current role is grantor or grantee. And `column_privileges` lists a table-level SELECT/INSERT/UPDATE once per column, so a table grant looks like a pile of column grants.

## 5. A derived backup role

A backup role with SELECT on every declared table and sequence is fine, and it should be **generated from `GRANTS`**, not from `GRANT SELECT ON ALL TABLES`. `ON ALL TABLES` is a snapshot of the tables that exist when it runs, so a table created later is silently missing from every backup. Derived from the declaration, the backup set is exactly the declared set, and the coverage test already fails on any undeclared table. `pg_dump` also needs SELECT on sequences to read their current values.

## 6. Gotcha: `makemigrations --check` under default-deny

With a database router, `makemigrations` runs `check_consistent_history` on every alias where the router allows migrations, reading `django_migrations` as that alias's user. The runtime role has no SELECT on it. Django catches only `OperationalError` there, and a permission denial is a `ProgrammingError`, so the command crashes. Allow migrations only on the migrator and template aliases:

```python
# config/routers.py
class MigrateOnlyAsMigrator:
    MIGRATION_ALIASES = frozenset({"migrator", "template"})

    def allow_migrate(self, db, app_label, model_name=None, **hints):
        return db in self.MIGRATION_ALIASES
```

## 7. Pair it with a no-standing-human-access test

Grants decide what the declared roles may do. This test decides who else can get in: the roles holding any privilege on a tenant DB, or membership (direct or nested) in a role that does, must equal exactly the roles the declared kinds resolve to, plus the owner (the owner's own ACL entry puts it in the result). A human login added "just for today" fails CI.

```sql
WITH RECURSIVE holders AS (
  SELECT a.grantee AS r FROM pg_class c CROSS JOIN LATERAL aclexplode(c.relacl) a WHERE c.relnamespace = 'public'::regnamespace
  UNION SELECT a.grantee FROM pg_attribute t JOIN pg_class c ON c.oid = t.attrelid CROSS JOIN LATERAL aclexplode(t.attacl) a WHERE c.relnamespace = 'public'::regnamespace
  UNION SELECT a.grantee FROM pg_database d CROSS JOIN LATERAL aclexplode(d.datacl) a WHERE d.datname = current_database()
  UNION SELECT a.grantee FROM pg_namespace n CROSS JOIN LATERAL aclexplode(n.nspacl) a WHERE n.nspname = 'public'
), reach AS (
  SELECT r FROM holders
  UNION SELECT m.member FROM pg_auth_members m JOIN reach ON m.roleid = reach.r
)
SELECT coalesce(pg_get_userbyid(nullif(r, 0)), 'PUBLIC') AS role FROM reach ORDER BY 1;
```

Tested: a login two levels down (`login → group → app_web`) appears in the result, and a one-level join misses it. Superusers bypass every ACL and appear in none of these catalogs. Assert `SELECT rolname FROM pg_roles WHERE rolsuper` separately, against its own expected list.

## DO / DON'T

✅ DO: `"update": ["status", "updated_at"]` plus `order.save(update_fields=["status", "updated_at"])`.
❌ DON'T: grant table-wide UPDATE "because `save()` needs it". Then every column is writable, and the declaration says nothing.

✅ DO: fail CI when a new model's table has no `GRANTS` entry.
❌ DON'T: `ALTER DEFAULT PRIVILEGES … GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO app_web` to save the declaration step. Every future table, including the audit log, then becomes writable and deletable by the web role.

✅ DO: the outbox gets INSERT plus UPDATE on its status columns, no DELETE.
❌ DON'T: give the worker DELETE on the outbox to "clean up sent rows". The history the outbox exists to keep becomes deletable by the role most exposed to task input. Retention runs as the migrator, on a schedule.
