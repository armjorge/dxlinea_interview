# Analytical plan for Q4 Demand Generation Insights. 

This plan bridges raw multi-source data extraction with rigorous modeling to deliver reliable, transparent, and auditable insights. It guarantees that every executive metric is fully reproducible, error-free, and directly aligned with strategic business value.

- PLN-1: Extract multi-sheet Excel data using Python and Pandas, exporting each sheet individually into optimized Parquet files without early transformations.
- PLN-2: Load the Parquet files into a Snowflake internal stage.
- PLN-3: Create raw Snowflake tables to ingest the data via COPY INTO statements, establishing an unmodified Bronze layer.
- PLN-4: Apply the Google Data Analytics lifecycle (Ask, Prepare, Process, Analyze, Share, Act) to structure the analytical problem-solving approach.
- PLN-5: Implement a Medallion Architecture using dbt to progressively increase transformation complexity, ensuring full reproducibility and a clean semantic layer for consumption.
- PLN-5: Implement a Medallion Architecture using dbt to progressively increase transformation complexity, ensuring full reproducibility and a clean semantic layer for consumption.
- PLN-6: Enforce strict data modeling and governance standards:
    - Validate entity relationships during joins to prevent unintended many-to-many cardinality issues.
    - Incorporate DAMA-DMBOK principles by adding concise descriptions to final attributes and explicitly classifying objects as dimensions, metrics, or facts.

