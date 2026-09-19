from pathlib import Path
import pandas as pd


def extract_sheets_to_parquet() -> list[Path]:
    """Export every worksheet in the source workbook to a Parquet file."""
    root_path = Path(__file__).resolve().parent.parent
    src_files = root_path / "src_files"
    input_xlsx = src_files / "delinea_case_study_data.xlsx"

    if not input_xlsx.is_file():
        raise FileNotFoundError(f"Source workbook not found: {input_xlsx}")

    converted_files: list[Path] = []
    with pd.ExcelFile(input_xlsx) as workbook:
        for sheet_name in workbook.sheet_names:
            sheet = pd.read_excel(workbook, sheet_name=sheet_name, dtype=str)
            output_path = src_files / f"{sheet_name}.parquet"
            sheet.to_parquet(output_path, index=False)
            converted_files.append(output_path)

    return converted_files


def generate_snowflake_ddl(parquet_files: list[Path]) -> None:
    """Prompt for Snowflake details and print CREATE TABLE statements."""
    print("\n--- Snowflake Configuration ---")
    stage_path = input("Enter Snowflake Stage path (e.g., DXLINEA_INTERVIEW.RAW_DXLINEA.RAW_DXLINEA_STAGE): ").strip()
    file_format = input("Enter File Format name (e.g., DXLINEA_INTERVIEW.RAW_DXLINEA.DXLINEA_FF): ").strip()

    print("\n--- Generated SQL Statements ---\n")
    for file_path in parquet_files:
        table_name = file_path.stem.lower()
        
        # Read columns from parquet file
        df = pd.read_parquet(file_path)
        columns = df.columns.tolist()

        # Build SELECT column list pointing to $1:col_name without quotes on the alias
        select_cols = []
        for col in columns:
            safe_col = col.replace('"', '""')
            select_cols.append(f"    $1:\"{safe_col}\"::VARCHAR AS {col}")

        cols_sql = ",\n".join(select_cols)

        # Output the CTAS statement
        print(f"CREATE OR REPLACE TABLE {table_name} AS")
        print("SELECT")
        print(cols_sql)
        print(f"FROM @{stage_path}/{file_path.name}")
        print(f"    (FILE_FORMAT => '{file_format}');\n")


if __name__ == "__main__":
    files = extract_sheets_to_parquet()
    print(f"\nSuccessfully converted {len(files)} sheets to Parquet.")
    generate_snowflake_ddl(files)
