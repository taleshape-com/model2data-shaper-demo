---
name: shaper-dashboard-development
description: Build, validate, preview, and organize Shaper dashboards using DuckDB SQL and Shaper-specific types, including embedded dashboards with JWT preset variables.
---

# Shaper Dashboard Development Skill

Use this skill to design, implement, validate, and preview Shaper dashboards. Shaper dashboards are defined as SQL files and run on DuckDB SQL, using custom type casting (`::TYPE`) to construct interactive UI elements.

## Workflow

### 1. Prerequisite Check
- Ensure that the environment setup sub-skill (`shaper-setup`) has been successfully run and the configuration file `shaper.json` exists.
- **Authentication**: Shaper CLI commands do not automatically log in the user. Always call `shaper login` before executing other CLI commands (`shaper schema`, `shaper ids`, `shaper validate`, `shaper preview`). Executing `shaper login` prompts the user to open a URL in their browser and confirm authentication (user action required).
- **Authentication Error Handling**: If any CLI command fails to authenticate, execute `shaper login` and instruct the user to complete the browser authentication step before retrying.
- **Instance URL Overwriting**: All Shaper CLI commands accept an optional `--url <URL>` flag to overwrite the instance URL defined in `shaper.json`. If the user specifies that they want to overwrite or target a specific Shaper instance URL, adapt all commands below by passing `--url <URL>`.

### 2. Context Gathering
- **Schema Discovery**: Run the command `shaper schema` (or `shaper schema --url <URL>` / `shaper schema --config-file ...`) to inspect the database schema, tables, and column structures available to query.
- **Style Alignment**: Search the workspace for any existing `*.dashboard.sql` files. Inspect them to understand existing dashboard patterns, styles, common metrics, and tables.
- **Embedding & Scope Clarification**: Embedding is the most common use case for Shaper dashboards. Always clarify whether the dashboard will be embedded into an application and determine which variables will be preset directly in the JWT token (e.g., `tenant_id`, `organization_id`, `user_id`, `role`, `allowed_tenants`). Embedding variables can be a **single string** or a **list of strings**. When a variable is a list of strings, use a SQL `IN` check (e.g., `WHERE tenant_id IN getvariable('allowed_tenants')`). Ensure that all data queries are designed to restrict what users are allowed to see based on these preset variables. In the preview view, the user is able to set these variables in the sidebar to test out what it looks like when embedded.

### 3. Creating a Dashboard
- **File Naming**: Create a file named `<Dashboard Name>.dashboard.sql` (e.g., `Active Users.dashboard.sql`).
- **File Organization**: Dashboard files can be organized into sub-folders. The folder hierarchy is preserved when synced to the production system.
- **ID Generation (Mandatory)**: Immediately after creating the dashboard file (even if it is empty or has a simple skeleton), run:
  ```bash
  shaper ids
  # Or, if overwriting the instance URL:
  shaper ids --url <URL>
  # Or, if using a custom config:
  shaper ids --config-file <PATH_TO_CONFIG>
  ```
  This command inserts/updates a header comment in the format `-- shaperid:<UUID>` at the top of the file. **Do not write, edit, or copy this comment manually.**

### 4. Validation
- **Action**: Before presenting a dashboard or after making any changes to a dashboard file, run the validation tool to check for SQL or execution errors:
  ```bash
  shaper validate path/to/Dashboard.dashboard.sql
  # Or, if overwriting the instance URL:
  shaper validate path/to/Dashboard.dashboard.sql --url <URL>
  # Or, if using a custom config:
  shaper validate path/to/Dashboard.dashboard.sql --config-file <PATH_TO_CONFIG>
  ```

### 5. Previewing (Mandatory After Every Change)
- **Mandatory Action**: Whenever you create a new dashboard or make ANY updates or modifications to an existing dashboard file (e.g. layout adjustments, query fixes, adding metrics, or filter changes), you **MUST** generate a new preview for the user so they can immediately see the updated dashboard.
- Run:
  ```bash
  shaper preview path/to/Dashboard.dashboard.sql
  # Or, if overwriting the instance URL:
  shaper preview path/to/Dashboard.dashboard.sql --url <URL>
  # Or, if using a custom config:
  shaper preview path/to/Dashboard.dashboard.sql --config-file <PATH_TO_CONFIG>
  ```
- **Testing Embedded Variables**: When creating a dashboard for embedding, in the preview view the user is able to set the variables in the sidebar to test out what it looks like when embedded.
- **Rule**: Never end a turn or inform the user that changes are complete without executing `shaper preview` to render a fresh preview for the modified dashboard.

### 6. Git Hygiene & Deployment
- **Deployment constraint**: **Never deploy dashboards directly.** Dashboards are synchronized through the CI/CD pipeline.
- **Action**: Once the changes are verified and previewed, commit the `*.dashboard.sql` files to git so they can be reviewed and deployed automatically.

---

## Best Practices

Follow these guidelines to build clean, maintainable, and high-performing Shaper dashboards:

- **Embedded Dashboard Security**: Embedding into host applications is the primary use case for Shaper dashboards. When embedding, security and data access control rely on variables preset in the JWT token (e.g. `tenant_id` or `allowed_orgs`). Preset embedding variables can be a **single string** or a **list of strings**. Always access these variables with `getvariable('variable_name')` and apply strict filtering in your base queries or temp tables using `=` for single strings or `IN` for lists of strings (`WHERE col IN getvariable('allowed_orgs')`) to ensure users can only access authorized data.
- **Mandatory Re-Preview After Edits**: Every time you modify or update a dashboard file, always run `shaper validate` followed by `shaper preview` to generate a new preview. Never make changes to a dashboard without generating a fresh preview for the user to review.
- **Dashboard Title**: Start your dashboard file with a `SECTION` query to establish a clear main header/title for the dashboard (optionally pair with `::SUBTITLE` for an explanatory subtitle).
- **Top-Heavy Header Controls**: Keep filter components and global download buttons (CSV/XLSX/JSON/PDF) clustered at the top of the file. This groups interactive components into a cohesive header. Only place interactive controls within individual sections on highly complex dashboards.
- **Performance Optimization via Caching**: Define your filters first, then immediately cache the filtered subset of data into a temporary table using `CREATE TEMPORARY TABLE`. This ensures you only filter the dataset once, boosting query performance and avoiding repetitive `WHERE` clauses in subsequent chart queries.
- **Clear Card Labels & Subtitles**: Precede most charts, metrics, and tables with a `LABEL` query to explain what the widget shows. Add a `SUBTITLE` to provide additional context or explanation below a section title or a card label.
- **Single Records & Key-Value Pairs**: Tables are not auto-pivoted on a single row to avoid unexpected layout shifts when queries happen to return only one row. To display a single record or key-value pairs, return a single `STRUCT`, `MAP`, or `JSON` object (e.g. `SELECT mysubquery FROM (SELECT ...) mysubquery;`).
- **Clean Axis Labels**: Visualizations look significantly cleaner without redundant axis labels. Omit axis labels by skipping the `AS alias` clause on axis or count columns when the data type or value is self-evident (e.g. date columns, counts).

---

## Full Dashboard Example

The following example demonstrates a complete, production-ready Shaper dashboard integrating filters, layout sections, caching views, file downloads, metric cards, charts, and tables:

```sql
-- 1. Main Dashboard Header Section
SELECT 'Shaper Demo Dashboard'::SECTION, 'Overview of recent user sessions and performance'::SUBTITLE;

-- 2. Header Filters (Interactivity)
SELECT
  min(created_at)::DATE::DATEPICKER_FROM AS start_date,
  max(created_at)::DATE::DATEPICKER_TO AS end_date,
FROM sessions;

SELECT 'Category'::LABEL;
SELECT category::DROPDOWN_MULTI AS category
FROM sessions
GROUP BY category
ORDER BY category;

-- 3. Caching filtered data for performance & security
-- Note: 'tenant_id' is preset directly in the JWT when embedding
CREATE TEMP TABLE dataset AS (
  SELECT * FROM sessions
    WHERE tenant_id = getvariable('tenant_id')
      AND category IN getvariable('category')
      AND created_at BETWEEN getvariable('start_date') AND getvariable('end_date')
);

-- 4. Utility/Download Actions
SELECT ('sessions-' || today())::DOWNLOAD_CSV AS "CSV";
SELECT * FROM dataset;

SELECT ('sessions-dashboard-' || today())::DOWNLOAD_PDF AS "PDF", 'xdek0446xo2oijlxlodvpo2g'::ID;

-- 5. Primary Metric Cards & Tables
SELECT count(*) AS "Total Sessions"
FROM dataset;

SELECT 'Summary'::LABEL;
SELECT
  category AS "Category",
  count(*) AS "Sessions",
  to_seconds(round(avg(duration))) AS "Avg Duration",
FROM dataset
GROUP BY "Category"
ORDER BY "Sessions" DESC;

SELECT 'Sessions By Time of Day'::LABEL, 'Hourly breakdown of user activity'::SUBTITLE;
SELECT
  date_trunc('hour', created_at)::TIME::XAXIS AS "Time of Day",
  count(*)::BARCHART AS "Total Sessions",
FROM dataset
GROUP BY ALL
ORDER BY ALL;

-- 6. Secondary Section with Multi-category Visualizations
SELECT ''::SECTION;

SELECT 'Sessions per Week'::LABEL;
SELECT
  date_trunc('week', created_at)::XAXIS,
  category::CATEGORY,
  count(*)::BARCHART_STACKED,
FROM dataset
GROUP BY ALL
ORDER BY ALL;

SELECT 'Average Session Duration per Week'::LABEL;
SELECT
  date_trunc('week', created_at)::XAXIS,
  category::CATEGORY,
  to_seconds(round(avg(duration)))::LINECHART,
FROM dataset
GROUP BY ALL
ORDER BY ALL;
```

---

## SQL & Dashboard Reference

Each dashboard is a collection of SQL queries separated by `;`. All queries are executed using **DuckDB SQL**.

### Custom Types & Visualizations

Cast SQL expression output to custom Shaper types using `::TYPE` (e.g., `SELECT 'Total Sales'::LABEL;`).

#### 1. Tables (Default)
Any query returning multiple columns is rendered as a table. Column headers map to column aliases.
Avoid using tables with many columns in layouts with multiple queries in a section.
- **`PERCENT`**: Renders a float/double between 0 and 1 as a percentage (e.g. `col::PERCENT`).
- **`TREND`**: Shows a trend arrow up/down.

##### Examples:
```sql
-- Standard Table
SELECT col0 AS "Date", col1 AS "Type", col2 AS "Amount"
FROM (VALUES
  ('2024-01-01'::DATE, 'Buy', 100),
  ('2024-01-02'::DATE, 'Sell', 120)
);

-- Table with Percent and Trend indicators
SELECT
  date::DATE AS "Date",
  value AS "Value",
  (value::DOUBLE / lag(value) OVER (ORDER BY date))::TREND AS "Trend",
  margin::PERCENT AS "Margin"
FROM sales;
```

#### 2. Single Record / Key-Value Pairs
To display a single record or a set of key-value pairs (displaying fields vertically rather than a horizontal table row), return a single `STRUCT`, `MAP`, or `JSON` object.
- **Explicit Struct Conversion**: You can explicitly turn a query record into a struct by selecting the subquery alias:
  ```sql
  SELECT mysubquery FROM (SELECT ...) mysubquery;
  ```
- **MAP or JSON Object**: Returning a single `MAP` or `JSON` object also renders as a single record.

##### Examples:
```sql
-- Single Record via Subquery Struct Conversion
SELECT org FROM (
  SELECT
    'Acme Corporation' AS "Organization",
    'Enterprise' AS "Plan",
    42 AS "Seats Used",
    'Active' AS "Status"
) org;

-- Single Record via Struct Literal
SELECT {'Organization': 'Acme Corporation', 'Plan': 'Enterprise', 'Seats Used': 42, 'Status': 'Active'};

-- Single Record via MAP
SELECT MAP {
  'Organization': 'Acme Corporation',
  'Plan': 'Enterprise',
  'Status': 'Active'
};
```

#### 3. Single Value Card
If a query returns exactly 1 row and 1 scalar column (excluding `STRUCT`, `MAP`, or `JSON` objects which render as single records), it is rendered as a single large metric card. Font size is auto-scaled to fit the screen.
- **`PERCENT`**: Formats the value as a percentage.
- **`COMPARE`**: Renders a comparison subtitle and trend indicator below the value.
- **`TEXT_SMALL` / `TEXT_MEDIUM` / `TEXT_LARGE`**: Overrides the automatic scaling to make cards visually consistent.
- **Left-Alignment Trick**: Ending string values with a newline `\n` forces left alignment even for short text.

##### Examples:
```sql
-- Standard Single Value Card
SELECT 14500 AS "Active Users";

-- Percentage Value with a Comparison Subtitle
SELECT
  0.85::PERCENT AS "Conversion Rate",
  0.08::COMPARE AS "vs Last Month";

-- Overriding Font Sizes and Left-Aligning Text
SELECT 'Medium Text
'::TEXT_MEDIUM AS "Label";
```

#### 4. Bar Chart
Renders vertical or horizontal bars. Can be grouped or stacked.
- **`XAXIS` / `YAXIS`**: X-axis for vertical charts, Y-axis for horizontal charts (dimensions).
- **`BARCHART`**: The numeric/interval value defining the length of the bar.
- **`CATEGORY`**: Groups data into categories and displays a legend. Setting to `NULL` or empty string hides that category from the legend (useful for selective coloring).
- **`BARCHART_STACKED`**: Stacks categories on top of each other.
- **`BARCHART_PERCENT` / `BARCHART_STACKED_PERCENT`**: Bounds the chart axis to 100% (values should be 0 to 1).
- **`COLOR`**: Sets the color for a category or bar (hex/color name). When `CATEGORY` is not present, bars can be colored individually. If a uniform color is specified across rows, it applies to the series as a whole.

##### Examples:
```sql
-- Vertical Grouped Bar Chart
SELECT month::XAXIS, count::BARCHART, category::CATEGORY
FROM monthly_stats;

-- Horizontal Bar Chart (YAXIS)
SELECT region::YAXIS, revenue::BARCHART
FROM regional_revenue;

-- Stacked Percent Bar Chart
SELECT month::XAXIS, ratio::BARCHART_STACKED_PERCENT, status::CATEGORY
FROM project_status;

-- Individual Bar Colors (without CATEGORY)
SELECT
  status::XAXIS,
  count::BARCHART,
  CASE status WHEN 'Done' THEN '#6cbc87' WHEN 'Blocked' THEN '#ee5674' ELSE '#ffd26a' END::COLOR
FROM tasks
GROUP BY status;

-- Custom Category Colors and Hiding Specific Categories from Legend
SELECT
  month::XAXIS,
  count::BARCHART,
  CASE WHEN priority = 'High' THEN 'High' ELSE NULL END::CATEGORY,
  color::COLOR
FROM tasks;
```

#### 5. Line Chart
Identical to Bar Charts but represents trends over time. Does not support horizontal `YAXIS` or stacked forms.
- **`XAXIS`**: Dimension/time column.
- **`LINECHART` / `LINECHART_PERCENT`**: The numeric/percentage value column.
- **`CATEGORY`**: Renders multiple lines.
- **`COLOR`**: Category line colors. When `CATEGORY` is not present and a `COLOR` is provided, a uniform color applies to the line series, while individual point colors are also supported.
- **`BAND_LOWER` / `BAND_UPPER`**: Displays a confidence band for a line. Column aliases can define labels (e.g. `Lower SD`, `Upper SD`). Set to `NULL` to hide the band for specific categories/lines.

##### Examples:
```sql
-- Standard Line Chart with uniform series color (without CATEGORY)
SELECT date::XAXIS, count::LINECHART, '#19b2ee'::COLOR FROM active_users;

-- Line Chart with individual point colors (without CATEGORY)
SELECT
  date::XAXIS,
  latency::LINECHART,
  CASE WHEN latency > 500 THEN '#ee5674' ELSE '#19b2ee' END::COLOR
FROM response_times;

-- Line Chart with categories and custom colors
SELECT date::XAXIS, active_users::LINECHART, tier::CATEGORY, '#19b2ee'::COLOR
FROM active_tiers;

-- Line Chart with confidence bands (Target line gets band, Actual does not)
SELECT
  date::TIMESTAMP::XAXIS,
  value::LINECHART,
  metric::CATEGORY,
  lower_bound::BAND_LOWER AS "-1 SD",
  upper_bound::BAND_UPPER AS "+1 SD"
FROM performance_metrics;
```

#### 6. Scatter Plot
Visualizes data points plotted on X and Y axes, useful for showing correlations, distributions, and clusters. Supports multiple categories with custom colors.
- **`XAXIS` / `YAXIS`**: Dimension column (VARCHAR, TIMESTAMP, TIME, or numeric). Often a time dimension for XAXIS.
- **`SCATTERPLOT`**: The numeric or INTERVAL value to plot.
- **`SCATTERPLOT_PERCENT`**: Displays values as percentages (values should be between 0 and 1, chart axis bounded to 100%).
- **`CATEGORY`**: Groups data points into multiple series with a legend.
- **`COLOR`**: Assigns custom colors to categories or individual points. When `CATEGORY` is not present, individual points can have distinct colors using their row's `COLOR`.
- Hover tooltips automatically show additional columns not used in the plot definition.

##### Examples:
```sql
-- Basic Scatter Plot with time on X-axis
SELECT ts::XAXIS, val::SCATTERPLOT
FROM measurements;

-- Scatter Plot with individual point colors (without CATEGORY)
SELECT
  ts::XAXIS,
  val::SCATTERPLOT,
  CASE WHEN val > 15 THEN '#ee5674' ELSE '#19b2ee' END::COLOR
FROM measurements;

-- Multi-category Scatter Plot with custom colors
SELECT
  ts::XAXIS,
  val::SCATTERPLOT,
  cat::CATEGORY,
  color::COLOR
FROM (VALUES
    ('2026-07-09 10:00:00'::TIMESTAMP, 10.5, 'Group A', '#19b2ee'),
    ('2026-07-09 10:15:00'::TIMESTAMP, 15.2, 'Group B', '#ee5674'),
    ('2026-07-09 11:00:00'::TIMESTAMP, 12.0, 'Group A', '#19b2ee')
) AS t(ts, val, cat, color);

-- Percentage Scatter Plot
SELECT date::XAXIS, conversion_rate::SCATTERPLOT_PERCENT, segment::CATEGORY
FROM daily_metrics;
```

#### 7. Box Plots
Visualizes distribution of a dataset. Calculated via the aggregate `BOXPLOT()` function.
- **`BOXPLOT(val)`**: Renders boxes showing min, max, median, Q1, Q3.
- **Outliers**: Pass `outlier_info := MAP {'label': col}` to show outlier points on hover with the custom metadata. Pass an empty map `MAP {}` to just show outlier points without custom info. Outliers are defined as values falling outside the 1.5 IQR.

##### Examples:
```sql
-- Simple Box Plot (no outlier hover detail)
SELECT region::XAXIS, BOXPLOT(revenue)
FROM regional_data
GROUP BY region;

-- Box Plot with Outliers & Hover Metadata
SELECT region::XAXIS, BOXPLOT(revenue, outlier_info := MAP {'Client': client_name})
FROM regional_data
GROUP BY region;
```

#### 8. Annotations
Draw mark lines on Bar/Line charts. Place annotation queries *before* the main chart query.
- **`XLINE`**: Vertical line on the X-axis.
- **`YLINE`**: Horizontal line on the Y-axis.
- **`LABEL`**: Label displaying next to the line.

##### Examples:
```sql
-- Vertical Annotation Line (XLINE) on a Timeline
SELECT '2026-11-27'::TIMESTAMP::XLINE, 'Black Friday'::LABEL;
SELECT date::XAXIS, sales::LINECHART FROM daily_sales;

-- Horizontal Annotation Line (YLINE) as a Threshold
SELECT 85::YLINE, 'Target Goal'::LABEL;
SELECT month::XAXIS, revenue::BARCHART FROM monthly_revenue;
```

#### 9. Gauge
Shows progress towards a goal or status distribution.
- **`GAUGE` / `GAUGE_PERCENT`**: Renders progress value.
- **`RANGE`**: Custom range intervals, e.g. `[0, 50, 100]::RANGE`.
- **`COLORS`**: Segment colors. Must contain **one less** element than `RANGE`.
- **`LABELS`**: Segment labels. Must contain **one less** element than `RANGE`.

##### Examples:
```sql
-- Standard Gauge with custom Range
SELECT 4::GAUGE, [0, 10]::RANGE;

-- Percentage Gauge (Range defaults to 0% - 100%)
SELECT 0.22::GAUGE_PERCENT AS "CPU Usage";

-- Segmented, Colored Status Gauge
SELECT
  78::GAUGE,
  [0, 50, 80, 100]::RANGE,
  ['#ee5674', '#ffd26a', '#6cbc87']::COLORS,
  ['Poor', 'Fair', 'Excellent']::LABELS;
```

#### 10. Pie Chart & Donut Chart
Shows category distributions. Donut charts display the total aggregate sum in the center.
- **`PIECHART` / `DONUTCHART`**: Value column (numeric).
- **`PIECHART_PERCENT` / `DONUTCHART_PERCENT`**: Percentage columns.
- **`CATEGORY`**: Category names. Categories `< 5%` are automatically grouped under "Other".
- **`COLOR`**: Slice colors.

##### Examples:
```sql
-- Pie Chart with custom Colors
SELECT country::CATEGORY, visitors::PIECHART, color::COLOR FROM visitor_stats;

-- Donut Chart with percentage values
SELECT tier::CATEGORY, ratio::DONUTCHART_PERCENT AS "Ratio" FROM user_tiers;
```

### Variables, Interactive Filtering & Embedding

Shaper dashboards use variables to dynamically filter data. All variables are accessed in DuckDB SQL queries using `getvariable('variable_name')` (returned as matching DuckDB types).

#### Variable Sources

1. **JWT Preset Variables (Embedded Dashboards)**: Embedding dashboards into host applications is the primary use case for Shaper dashboards. When embedded, the host application presets variables directly in the JWT payload (e.g. `tenant_id`, `organization_id`, `user_id`, `role`, `allowed_tenants`). These variables are set securely outside the user's control and MUST be used in `WHERE` clauses to strictly scope and restrict the data users are allowed to see. In the preview view, the user is able to set these variables in the sidebar to test out what it looks like when embedded.
   - **Single String Variable**: When the variable contains a single string value (e.g. `'org_123'`), use standard equality: `WHERE organization_id = getvariable('organization_id')`.
   - **List of Strings Variable**: When the variable contains a list of strings (e.g. `['tenant_a', 'tenant_b']`), use a SQL `IN` check: `WHERE tenant_id IN getvariable('allowed_tenants')`.
2. **Interactive UI Filters**: Components rendered on the dashboard layout (such as `DATEPICKER`, `DROPDOWN`, or `INPUT`) expose variables that end users can manipulate interactively.

#### UI Filter Types

- **`DATEPICKER`**: Single date selector. Returns `DATE`.
- **`DATEPICKER_FROM` & `DATEPICKER_TO`**: Date range selector. Returns two `DATE` variables.
- **`DROPDOWN`**: Single-select drop-down menu. Returns `VARCHAR`. Use `UNION ALL` to define custom default values.
- **`DROPDOWN` with distinct value vs label**: Map distinct labels to dropdown values using the `::LABEL` type.
- **`DROPDOWN_MULTI`**: Multi-select dropdown. Returns a list/array of `VARCHAR` elements. Use `IN` to query.
  - Optional **`HINT`**: Displays additional text alongside options (e.g. item count).
- **`INPUT`**: Text input field. Returns `VARCHAR` (or `NULL` if empty).

##### Examples:

```sql
-- 1. JWT Preset Variable - Single String (Row-Level Security)
-- Access single string variable preset directly in the JWT token
SELECT * FROM orders WHERE tenant_id = getvariable('tenant_id');

-- 2. JWT Preset Variable - List of Strings (Multi-Tenant / Scope List Security)
-- Access list of strings preset directly in the JWT token using SQL IN check
SELECT * FROM orders WHERE organization_id IN getvariable('allowed_orgs');

-- 3. Date Picker
SELECT today()::DATEPICKER AS select_date;
-- Usage: WHERE date = getvariable('select_date')

-- 4. Date Range Picker
SELECT (today() - 7)::DATEPICKER_FROM AS "from", today()::DATEPICKER_TO AS "to";
-- Usage: WHERE date BETWEEN getvariable('from') AND getvariable('to')

-- 5. Dropdown with Custom Default Value
SELECT 'All Categories'::DROPDOWN AS selected_cat
UNION ALL
(SELECT category FROM items GROUP BY category ORDER BY category);
-- Usage: WHERE category = getvariable('selected_cat') OR getvariable('selected_cat') = 'All Categories'

-- 6. Dropdown with distinct label and value (Value is number, Label is month name)
SELECT
  EXTRACT(MONTH FROM range)::TEXT::DROPDOWN AS month,
  strftime(range, '%B')::LABEL
FROM range(DATE '2024-01-01', DATE '2025-01-01', INTERVAL 1 MONTH);

-- 7. Multi-select Dropdown with Hint
SELECT category::DROPDOWN_MULTI AS selected_cats, count(*)::HINT FROM items GROUP BY category;
-- Usage: WHERE category IN getvariable('selected_cats')

-- 8. Text Input Filter
SELECT 'Search items...'::INPUT AS search_term;
-- Usage: WHERE name LIKE '%' || getvariable('search_term') || '%'

-- 9. Combining JWT Security & Interactive UI Filters in Cached Dataset
CREATE TEMP TABLE dataset AS (
  SELECT * FROM sessions
  WHERE organization_id IN getvariable('allowed_orgs') -- List of strings in JWT
    AND category IN getvariable('selected_cats')       -- Interactive UI filter
);
```

### Downloads

Render download buttons to trigger data extraction.
- **`DOWNLOAD_CSV` / `DOWNLOAD_XLSX` / `DOWNLOAD_JSON`**: Creates a download button for tabular data. The string cast defines the filename, and the column alias defines the button label. The next query defines the actual data returned.
- **`DOWNLOAD_PDF`**: Triggers a PDF download of the dashboard layout.
  - **`ID`**: Download a *different* dashboard (using its UUID) instead of the current one. Applied filters are matched across dashboards.

##### Examples:
```sql
-- Tabular Data Downloads (CSV, XLSX, and JSON)
SELECT concat('sales-report-', today())::DOWNLOAD_CSV AS "Export CSV";
SELECT date, amount FROM daily_sales;

SELECT concat('sales-report-', today())::DOWNLOAD_JSON AS "Export JSON";
SELECT date, amount FROM daily_sales;

-- PDF Download button targeting a different dashboard ID
SELECT 'Download PDF Summary'::DOWNLOAD_PDF, 'd7b1b36b-74b8-4c9f-863a-23efbe9ff579'::ID AS my_pdf;
```

### Layout & Utility Commands

- **`SECTION`**: Groups subsequent cards/tables. Use `SELECT 'Section Title'::SECTION;`.
  - **Hiding Sections**: If a section query returns no rows (e.g., `WHERE FALSE`), the entire section is hidden.
  - **Section Subtitles**: Can be paired with `::SUBTITLE` to display explanatory text below the section title (e.g., `SELECT 'My Section'::SECTION, 'This is my section'::SUBTITLE;`).
- **`LABEL`**: Injects headers for cards or filters. Place right before the target card/filter query.
  - **Card/Widget Subtitles**: Can be paired with `::SUBTITLE` to display explanatory text below the card label (e.g., `SELECT 'My Label'::LABEL, 'Explanation for chart'::SUBTITLE;`).
- **`SUBTITLE`**: Adds extra explanation as text below a section title or a card label. Selected in the same query alongside a `::SECTION` or `::LABEL`.
- **`PLACEHOLDER`**: Injects blank spaces in the grid layout to align cards vertically.
- **`HEADER_IMAGE`**: Sets dashboard logo (URL or base64 URL) displayed on screens and every page of PDFs.
- **`FOOTER_LINK`**: Displays a footer link on screens and PDFs (URLs or mailto). You can set the text displayed for a footer link using a column alias (e.g. `SELECT 'https://example.com/moreinfo'::FOOTER_LINK AS "Click for more information";`).
- **`RELOAD`**: Sets auto-reload interval (TIMESTAMP or INTERVAL).

##### Examples:
```sql
-- 1. Section Header with Subtitle and Conditional Hiding
SELECT 'Revenue Metrics'::SECTION, 'Overview of financial performance'::SUBTITLE
WHERE (SELECT sum(revenue) FROM daily_sales) > 0;

-- 2. Section Header with Subtitle
SELECT 'My Section'::SECTION, 'This is my section'::SUBTITLE;

-- 3. Labeling a Single Value Card or Chart with Subtitle
SELECT 'My Label'::LABEL, 'Explanation for chart'::SUBTITLE;
SELECT 50000 AS "Target";

-- 4. Injecting a Grid Placeholder to align cards
SELECT 200 AS "This Week";
SELECT ''::PLACEHOLDER;
SELECT 150 AS "Last Week";

-- 5. Logo Header & Footer Link
SELECT 'https://example.com/logo.png'::HEADER_IMAGE;
SELECT 'https://example.com/moreinfo'::FOOTER_LINK AS "Click for more information";

-- 6. Auto Reload
SELECT (INTERVAL '5 minutes')::RELOAD;
```

### Non-SELECT Statements (Metadata & Exploration)

These DuckDB statements do not render UI cards but help organize code or explore schemas during development.

- **`DESCRIBE <table>`**: Returns schema details (columns, types, nullability) as a table.
- **`SUMMARIZE <table>`**: Returns statistics (mean, stddev, range) for columns.
- **`SHOW TABLES` / `SHOW ALL TABLES`**: Lists available tables.
- **`CREATE TEMPORARY TABLE <name> AS (<query>)`**: Caches intermediate results in memory for speed and reuse.
- **`CREATE TEMPORARY VIEW <name> AS (<query>)`**: Creates reusable logic without caching in memory.
- **`SET VARIABLE <name> = (<query>)`**: Assigns a variable value for subsequent queries.

##### Examples:
```sql
-- Cache pre-filtered data for reuse across multiple charts
CREATE TEMP TABLE dataset AS (
  SELECT * FROM sessions
  WHERE created_at BETWEEN getvariable('from') AND getvariable('to')
);

-- Show schema and database tables
DESCRIBE users;
SHOW TABLES;
```
