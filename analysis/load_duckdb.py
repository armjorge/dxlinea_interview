"""Load the case-study workbook into a local DuckDB file.

Every sheet becomes a table, except README. Tables keep the sheet names
(mkt_campaign, mkt_lead, mkt_touchpoint, sfdc_opportunity, sfdc_account).

The database is written to analysis/delinea.duckdb and is gitignored.
Run this from the repository root:

    python analysis/load_duckdb.py /path/to/delinea_case_study_data.xlsx
"""

from __future__ import annotations

import sys
from pathlib import Path

import duckdb
import pandas as pd

ROOT = Path(__file__).resolve().parents[1]
DB_PATH = ROOT / "analysis" / "delinea.duckdb"
SKIP_SHEETS = {"readme"}


def load(xlsx: Path, db_path: Path = DB_PATH) -> None:
    if not xlsx.is_file():
        raise SystemExit(f"workbook not found: {xlsx}")

    db_path.parent.mkdir(parents=True, exist_ok=True)
    if db_path.exists():
        db_path.unlink()

    book = pd.ExcelFile(xlsx)
    con = duckdb.connect(str(db_path))
    try:
        for sheet in book.sheet_names:
            if sheet.strip().lower() in SKIP_SHEETS:
                print(f"skip {sheet}")
                continue
            frame = pd.read_excel(book, sheet_name=sheet)
            con.register("incoming", frame)
            con.execute(f"CREATE TABLE {sheet} AS SELECT * FROM incoming").fetchall()
            con.unregister("incoming")
            rows = con.execute(f"SELECT COUNT(*) FROM {sheet}").fetchall()[0][0]
            print(f"loaded {sheet}: {rows} rows, {frame.shape[1]} columns")
    finally:
        con.close()
    print(f"wrote {db_path}")


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit(
            "usage: python analysis/load_duckdb.py /path/to/delinea_case_study_data.xlsx"
        )
    load(Path(sys.argv[1]))


if __name__ == "__main__":
    main()
