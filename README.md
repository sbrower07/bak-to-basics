# Bak to Basics

**Repeatable SQL Server and Postgres demo databases you can spin up in minutes.**

Local, repeatable database setup for following along with the videos. Everything runs in Docker, so there's nothing to install on your machine besides Docker itself, and you can wipe and rebuild it in seconds.

> SQL Server runs as **Developer edition**: free for development, testing, and demos. Not licensed for production use.

## What you'll need

- [Docker Desktop](https://www.docker.com/products/docker-desktop/) (or Docker Engine + Compose plugin on Linux)
- ~10 GB of free disk space
- The backup file: **[AdventureWorks2022.bak](https://github.com/Microsoft/sql-server-samples/releases/download/adventureworks/AdventureWorks2022.bak)** (place it in the `backups/` folder)
- Optional: a SQL client such as Azure Data Studio, SSMS, DBeaver, or `sqlcmd`

**Platform notes:** I have tested this on Windows Machine. On Apple Silicon Macs the SQL Server image runs under emulation and may be slow or unstable.

## Quick start

Every command below works as written in Windows (PowerShell or Command Prompt), macOS Terminal, and Linux shells. Each command is a single line, so paste the whole line.

```bash
git clone https://github.com/sbrower07/bak-to-basics.git
cd bak-to-basics

# 1. Put the backup file in ./backups/
# 2. Start SQL Server
docker compose up -d
```

Wait about 15-30 seconds for SQL Server to finish starting. Check with:

```bash
docker compose logs --tail 20 sqlserver
```

Look for "SQL Server is now ready for client connections."

## Restore the backup

**1. (Optional) Find the logical file names inside the backup:**

```bash
docker compose exec sqlserver /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P "YourStrong!Passw0rd" -C -Q "RESTORE FILELISTONLY FROM DISK = '/var/opt/mssql/backups/AdventureWorks2022.bak'"
```

**2. Restore:**

```bash
docker compose exec sqlserver /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P "YourStrong!Passw0rd" -C -Q "RESTORE DATABASE AdventureWorks2022 FROM DISK = '/var/opt/mssql/backups/AdventureWorks2022.bak' WITH MOVE 'AdventureWorks2022' TO '/var/opt/mssql/data/AdventureWorks2022.mdf', MOVE 'AdventureWorks2022_log' TO '/var/opt/mssql/data/AdventureWorks2022_log.ldf', REPLACE"
```

## Verify it worked

```bash
docker compose exec sqlserver /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P "YourStrong!Passw0rd" -C -Q "SELECT name, state_desc FROM sys.databases"
```

You should see `AdventureWorks2022` listed as `ONLINE`. A quick sanity query:

```sql
SELECT TOP 10 * FROM AdventureWorks2022.Sales.Customer;
```

## Connection details

| Setting  | Value                      |
|----------|----------------------------|
| Server   | `localhost,1433`           |
| Login    | `sa`                       |
| Password | `YourStrong!Passw0rd`      |
| Database | `AdventureWorks2022`       |
| Trust server certificate | Yes (local demo) |

Change the password in `docker-compose.yml` if you like. These credentials are for local demos only.

## Running the scripts

Scripts live in the `scripts/` folder. Run steps for each one are in the demo sections below.

## Demo: JD Edwards sample data (Postgres)

A script that builds simplified JD Edwards tables in Postgres and fills them with generated fake data, so you always have the same messy, JDE-style data to demo with.

It creates three tables in schema `proddta`: **f0101** Address Book, **f4101** Item Master, and **f4211** Sales Order Detail (4 lines per order, linked to customers and items). They keep the habits that make JDE data awkward to work with: cryptic column names, space-padded CHAR columns, blanks instead of NULLs, Julian dates (`CYYDDD`), times stored as numbers (`HHMMSS`), and amounts stored as whole numbers with implied decimals. Postgres lowercases unquoted names, so you query `aban8`, not `ABAN8`.

The data is repeatable: the same settings give the same rows every run. f0101 includes deliberately bad rows (blank names, impossible Julian dates, unknown search types, an address number of 0) so you have messy data to clean up, reject, or log.

**1. Start Postgres:**

```bash
docker compose --profile postgres up -d
```

**2. Create the tables and generate the data:**

```bash
docker compose exec postgres psql -U postgres -v ON_ERROR_STOP=1 -f /scripts/01_create_jde_source.sql
```

The script prints a row count per table when it finishes. It is safe to re-run: it drops and rebuilds the three tables each time, in a single transaction, so a failed run leaves the old data in place.

**Change how much data you get:** edit the `CONFIG` section near the top of `scripts/postgres/01_create_jde_source.sql`. Defaults are 500 addresses, 100 items, 2,000 order lines, and about 3% bad address rows. With the defaults, f0101 has 504 rows (500 generated plus 4 planted bad rows). A run with 50,000 addresses, 1,000 items, and 100,000 order lines took about 5 seconds in testing.

**Connect with a SQL client** (DBeaver, pgAdmin, Azure Data Studio, and so on):

| Setting  | Value       |
|----------|-------------|
| Host     | `localhost` |
| Port     | `5432`      |
| Login    | `postgres`  |
| Password | `demo`      |
| Database | `postgres`  |

**Take a look at the data:**

```bash
docker compose exec postgres psql -U postgres -c "SELECT aban8, abalph, abmcu, abat1, abupmj, abupmt FROM proddta.f0101 ORDER BY aban8 LIMIT 10"
```

```bash
docker compose exec postgres psql -U postgres -c "SELECT o.sddoco, o.sdlnid, a.abalph, o.sddsc1, o.sduorg, o.sduprc, o.sdaexp FROM proddta.f4211 o JOIN proddta.f0101 a ON a.aban8 = o.sdan8 ORDER BY o.sddoco, o.sdlnid LIMIT 10"
```

**Find the bad rows:**

```bash
docker compose exec postgres psql -U postgres -c "SELECT aban8, abalph, abat1, abupmj FROM proddta.f0101 WHERE trim(abalph) = '' OR aban8 = 0 OR abat1 NOT IN ('E','C','V') OR abupmj % 1000 > 366 ORDER BY aban8"
```

Bad Julian dates are the ones where the last three digits (the day of the year) are above 366, such as `125400`.

**How to read the JDE quirks:**

| Column | What it holds | Example |
|--------|---------------|---------|
| `abupmj`, `sdtrdj` and other `...j` dates | Julian date `CYYDDD` (century since 1900, year, day of year) | `126285` is October 12, 2026; `0` means no date |
| `abupmt`, `sdupmt` and other `...t` times | Time as a number, `HHMMSS` | `93015` is 09:30:15 |
| `abmcu` | Business unit, right-justified with leading spaces | `        1000` |
| `sduorg`, `sdaexp` | Quantity and extended price with 2 implied decimals | `1250` is 12.50 |
| `sduprc` | Unit price with 4 implied decimals | `125000` is 12.5000 |

## Optional: other database servers

Postgres and MySQL are included but off by default:

```bash
docker compose --profile postgres up -d   # Postgres on port 5432
docker compose --profile mysql up -d      # MySQL on port 3306
```

These use their own SQL dialects, not T-SQL, so the SQL Server scripts won't run on them unchanged.

## Reset everything

```bash
docker compose down -v   # stops containers and deletes the data volume
```

If you also started Postgres, include its profile so it is reset too:

```bash
docker compose --profile postgres down -v
```

Then run through Quick start again for a clean slate.

## Troubleshooting

- **Container exits immediately:** the SA password probably doesn't meet complexity rules (8+ characters, mixed case, a number or symbol).
- **Login failed / can't connect:** SQL Server may still be starting. Wait and check the logs.
- **Restore fails with "file not found":** confirm the `.bak` is in `./backups/` and the filename in your command matches exactly.
- **Restore fails on file paths:** run the `FILELISTONLY` step and make sure the `MOVE` logical names match.
- **Port already in use:** another SQL Server (or Postgres/MySQL) is running locally. Stop it or change the left side of the port mapping in `docker-compose.yml`.
- **Slow or crashing on Apple Silicon:** see the platform note above.
- **Postgres says `/scripts/postgres/01_create_jde_source.sql: No such file or directory`:** the Postgres container was created before the `scripts` folder was mounted. Run `docker compose --profile postgres up -d` again so it is recreated with the mount.

## Links
