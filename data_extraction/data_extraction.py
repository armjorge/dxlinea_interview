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

    print("Successfully converted workbook sheets to Parquet:")
    for output_path in converted_files:
        print(f"- {output_path}")

    return converted_files


if __name__ == "__main__":
    extract_sheets_to_parquet()
