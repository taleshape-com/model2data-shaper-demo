-- shaperid:clinic-overview

-- 1. Main Header & Controls
SELECT 'Healthcare Clinic Network'::SECTION, 'Executive Overview & Clinical Operations'::SUBTITLE;

SELECT
  min(scheduled_for)::DATE::DATEPICKER_FROM AS start_date,
  max(scheduled_for)::DATE::DATEPICKER_TO AS end_date
FROM staging.stg_appointments;

SELECT 'Clinic'::LABEL;
SELECT 'All Clinics'::DROPDOWN AS selected_clinic
UNION ALL
(SELECT name FROM staging.stg_clinics ORDER BY name);

SELECT 'Channel'::LABEL;
SELECT 'All Channels'::DROPDOWN AS selected_channel
UNION ALL
(SELECT DISTINCT channel FROM staging.stg_appointments ORDER BY channel);

-- 2. Caching filtered dataset for high performance
CREATE TEMP TABLE filtered_appointments AS (
  SELECT
    a.id AS appointment_id,
    a.patient_id,
    a.practitioner_id,
    a.treatment_id,
    a.booking_source,
    a.channel,
    a.status,
    a.booked_at,
    a.scheduled_for,
    a.checked_in_at,
    a.cancelled_at,
    a.actual_duration_minutes,
    a.billed_amount,
    a.paid_at,
    c.id AS clinic_id,
    c.name AS clinic_name,
    p.first_name || ' ' || p.last_name AS practitioner_name,
    p.specialty AS practitioner_specialty,
    t.name AS treatment_name,
    pat.first_name || ' ' || pat.last_name AS patient_name,
    pat.date_of_birth AS patient_dob,
    COALESCE(i.name, 'Uninsured / Self-Pay') AS insurer_name,
    date_diff('day', a.booked_at, a.scheduled_for) AS lead_time_days,
    CASE
      WHEN a.status = 'completed' AND a.paid_at IS NOT NULL THEN 'Paid'
      WHEN a.status = 'completed' AND a.paid_at IS NULL THEN 'Unpaid'
      ELSE 'N/A'
    END AS payment_status
  FROM staging.stg_appointments a
  JOIN staging.stg_practitioners p ON a.practitioner_id = p.id
  JOIN staging.stg_clinics c ON p.clinic_id = c.id
  JOIN staging.stg_treatments t ON a.treatment_id = t.id
  JOIN staging.stg_patients pat ON a.patient_id = pat.id
  LEFT JOIN staging.stg_insurers i ON pat.insurer_id = i.id
  WHERE a.scheduled_for::DATE BETWEEN getvariable('start_date') AND getvariable('end_date')
    AND (getvariable('selected_clinic') = 'All Clinics' OR c.name = getvariable('selected_clinic'))
    AND (getvariable('selected_channel') = 'All Channels' OR a.channel = getvariable('selected_channel'))
);

-- 3. Data Download Action
SELECT ('appointments-export-' || today())::DOWNLOAD_CSV AS "Export CSV";
SELECT
  appointment_id AS "ID",
  scheduled_for::TIMESTAMP AS "Scheduled For",
  clinic_name AS "Clinic",
  practitioner_name AS "Practitioner",
  practitioner_specialty AS "Specialty",
  treatment_name AS "Treatment",
  status AS "Status",
  channel AS "Channel",
  booking_source AS "Source",
  actual_duration_minutes AS "Duration (min)",
  billed_amount AS "Billed ($)",
  payment_status AS "Payment Status"
FROM filtered_appointments
ORDER BY scheduled_for DESC;

-- 4. Executive KPIs
SELECT 'Executive Summary'::SECTION, 'High-level network volume, completion rate, and financial summary'::SUBTITLE;

SELECT count(*) AS "Total Appointments"
FROM filtered_appointments;

SELECT count(*) FILTER (WHERE status = 'completed') AS "Completed Visits"
FROM filtered_appointments;

SELECT (count(*) FILTER (WHERE status = 'completed')::DOUBLE / NULLIF(count(*), 0))::PERCENT AS "Completion Rate"
FROM filtered_appointments;

SELECT COALESCE(round(sum(billed_amount)), 0)::BIGINT AS "Billed Revenue ($)"
FROM filtered_appointments
WHERE status = 'completed';

SELECT COALESCE(round(sum(billed_amount) FILTER (WHERE paid_at IS NULL)), 0)::BIGINT AS "Outstanding Balance ($)"
FROM filtered_appointments
WHERE status = 'completed';

SELECT (COALESCE(sum(billed_amount) FILTER (WHERE paid_at IS NULL), 0) / NULLIF(sum(billed_amount), 0))::PERCENT AS "Unpaid Revenue %"
FROM filtered_appointments
WHERE status = 'completed';

-- 5. Clinic Performance & Network Growth
SELECT 'Clinic Performance & Growth'::SECTION, 'Monthly appointment trends and clinic comparisons'::SUBTITLE;

SELECT 'Monthly Appointments by Status'::LABEL, 'Volume trajectory showing network growth across status categories'::SUBTITLE;
SELECT
  date_trunc('month', scheduled_for)::DATE::XAXIS,
  status::CATEGORY,
  count(*)::BARCHART_STACKED
FROM filtered_appointments
GROUP BY ALL
ORDER BY ALL;

SELECT 'Monthly Billed Revenue'::LABEL, 'Total billed revenue realized from completed appointments'::SUBTITLE;
SELECT
  date_trunc('month', scheduled_for)::DATE::XAXIS,
  round(sum(billed_amount))::LINECHART AS "Revenue ($)",
  '#2a9d8f'::COLOR
FROM filtered_appointments
WHERE status = 'completed'
GROUP BY ALL
ORDER BY ALL;

SELECT ''::SECTION;
SELECT 'Clinic Performance Summary'::LABEL, 'Key operational and financial metrics by clinic location'::SUBTITLE;
SELECT
  clinic_name AS "Clinic",
  count(*) AS "Appointments",
  (count(*) FILTER (WHERE status = 'completed')::DOUBLE / NULLIF(count(*), 0))::PERCENT AS "Completion Rate",
  (count(*) FILTER (WHERE status = 'no_show')::DOUBLE / NULLIF(count(*), 0))::PERCENT AS "No-Show Rate",
  round(COALESCE(sum(billed_amount), 0))::BIGINT AS "Billed ($)",
  round(COALESCE(sum(billed_amount) FILTER (WHERE paid_at IS NULL), 0))::BIGINT AS "Unpaid ($)",
  (round(COALESCE(sum(billed_amount) FILTER (WHERE paid_at IS NOT NULL), 0)) / NULLIF(sum(billed_amount), 0))::PERCENT AS "Collected %"
FROM filtered_appointments
GROUP BY clinic_name
ORDER BY "Appointments" DESC;

-- 6. Financials & Revenue Cycle
SELECT 'Financials & Revenue Cycle'::SECTION, 'Billed vs paid revenue, collection progress, and insurer balances'::SUBTITLE;

SELECT 'Overall Collection Rate'::LABEL, 'Percentage of completed appointment revenue successfully collected'::SUBTITLE;
SELECT
  (COALESCE(sum(billed_amount) FILTER (WHERE paid_at IS NOT NULL), 0) / NULLIF(sum(billed_amount), 0))::GAUGE_PERCENT AS "Collection Rate"
FROM filtered_appointments
WHERE status = 'completed';

SELECT 'Billed Revenue by Clinic & Payment Status'::LABEL, 'Collected revenue vs outstanding balance across clinics'::SUBTITLE;
SELECT
  clinic_name::YAXIS,
  payment_status::CATEGORY,
  round(sum(billed_amount))::BARCHART_STACKED
FROM filtered_appointments
WHERE status = 'completed'
GROUP BY ALL
ORDER BY sum(billed_amount) DESC;

SELECT 'Billed Revenue by Insurer'::LABEL, 'Revenue distribution across patient insurance coverage'::SUBTITLE;
SELECT
  insurer_name::CATEGORY,
  round(sum(billed_amount))::DONUTCHART
FROM filtered_appointments
WHERE status = 'completed'
GROUP BY insurer_name
ORDER BY sum(billed_amount) DESC;

-- 7. Operations & Attendance
SELECT 'Operations & Attendance'::SECTION, 'Attendance patterns, channels, booking lead times, and scheduling hours'::SUBTITLE;

SELECT 'Appointment Status Breakdown'::LABEL, 'Proportion of completed, cancelled, and no-show visits'::SUBTITLE;
SELECT
  status::CATEGORY,
  count(*)::DONUTCHART,
  CASE status
    WHEN 'completed' THEN '#2a9d8f'
    WHEN 'cancelled' THEN '#e76f51'
    WHEN 'no_show' THEN '#f4a261'
    ELSE '#457b9d'
  END::COLOR
FROM filtered_appointments
GROUP BY status;

SELECT 'Appointments by Channel'::LABEL, 'In-person vs video vs phone visits'::SUBTITLE;
SELECT
  channel::CATEGORY,
  count(*)::PIECHART
FROM filtered_appointments
GROUP BY channel;

SELECT 'Booking Source Breakdown'::LABEL, 'Appointment acquisition channels'::SUBTITLE;
SELECT
  booking_source::YAXIS,
  count(*)::BARCHART
FROM filtered_appointments
GROUP BY booking_source
ORDER BY count(*) DESC;

SELECT 'Booking Lead Time'::LABEL, 'Advance booking window (days from booking to appointment)'::SUBTITLE;
SELECT
  CASE
    WHEN lead_time_days = 0 THEN '0: Same day'
    WHEN lead_time_days = 1 THEN '1: 1 day'
    WHEN lead_time_days = 2 THEN '2: 2 days'
    WHEN lead_time_days = 3 THEN '3: 3 days'
    WHEN lead_time_days BETWEEN 4 AND 7 THEN '4: 4-7 days'
    ELSE '5: 8+ days'
  END::XAXIS,
  count(*)::BARCHART
FROM filtered_appointments
GROUP BY ALL
ORDER BY ALL;

SELECT 'Appointments by Hour of Day'::LABEL, 'Peak appointment activity across clinic operating hours'::SUBTITLE;
SELECT
  strftime(scheduled_for, '%H:00')::XAXIS,
  count(*)::BARCHART
FROM filtered_appointments
GROUP BY strftime(scheduled_for, '%H:00')
ORDER BY strftime(scheduled_for, '%H:00');

SELECT 'Appointments by Day of Week'::LABEL, 'Visit distribution across the week'::SUBTITLE;
SELECT
  strftime(scheduled_for, '%A')::XAXIS,
  count(*)::BARCHART
FROM filtered_appointments
GROUP BY strftime(scheduled_for, '%A')
ORDER BY min(extract(isodow FROM scheduled_for));


-- 8. Clinical Utilization & Practitioners
SELECT 'Clinical Utilization & Practitioners'::SECTION, 'Visit durations, practitioner workload, and treatment frequencies'::SUBTITLE;

SELECT 'Visit Duration by Specialty'::LABEL, 'Actual duration in minutes for completed visits'::SUBTITLE;
SELECT
  practitioner_specialty::XAXIS,
  BOXPLOT(actual_duration_minutes)
FROM filtered_appointments
WHERE status = 'completed' AND actual_duration_minutes IS NOT NULL
GROUP BY practitioner_specialty;

SELECT 'Top Treatments Administered'::LABEL, 'Volume count of completed treatments'::SUBTITLE;
SELECT
  treatment_name::YAXIS,
  count(*)::BARCHART
FROM filtered_appointments
WHERE status = 'completed'
GROUP BY treatment_name
ORDER BY count(*) DESC;

SELECT ''::SECTION;
SELECT 'Practitioner Activity & Productivity'::LABEL, 'Workload, completed visits, and average duration per practitioner'::SUBTITLE;
SELECT
  practitioner_name AS "Practitioner",
  practitioner_specialty AS "Specialty",
  clinic_name AS "Clinic",
  count(*) AS "Total Appointments",
  count(*) FILTER (WHERE status = 'completed') AS "Completed Visits",
  round(avg(actual_duration_minutes) FILTER (WHERE status = 'completed'), 1) AS "Avg Duration (min)"
FROM filtered_appointments
GROUP BY practitioner_name, practitioner_specialty, clinic_name
ORDER BY "Completed Visits" DESC;

-- 9. Patient & Insurer Demographics
SELECT 'Patient & Insurer Demographics'::SECTION, 'Patient roster growth and insurance landscape'::SUBTITLE;

SELECT 'Cumulative Registered Patients'::LABEL, 'Monthly patient registrations through end of period'::SUBTITLE;
SELECT
  date_trunc('month', p.registered_at)::DATE::XAXIS,
  count(*)::BARCHART
FROM staging.stg_patients p
JOIN staging.stg_clinics c ON p.home_clinic_id = c.id
WHERE p.registered_at::DATE <= getvariable('end_date')
  AND (getvariable('selected_clinic') = 'All Clinics' OR c.name = getvariable('selected_clinic'))
GROUP BY ALL
ORDER BY ALL;

SELECT 'Patients by Health Insurer'::LABEL, 'Primary coverage distribution of registered patients'::SUBTITLE;
SELECT
  COALESCE(i.name, 'Uninsured / Self-Pay')::CATEGORY,
  count(*)::DONUTCHART
FROM staging.stg_patients p
JOIN staging.stg_clinics c ON p.home_clinic_id = c.id
LEFT JOIN staging.stg_insurers i ON p.insurer_id = i.id
WHERE (getvariable('selected_clinic') = 'All Clinics' OR c.name = getvariable('selected_clinic'))
GROUP BY ALL
ORDER BY count(*) DESC;

SELECT 'Registered Patients by Home Clinic'::LABEL, 'Patient roster size by assigned home clinic'::SUBTITLE;
SELECT
  c.name::YAXIS,
  count(*)::BARCHART
FROM staging.stg_patients p
JOIN staging.stg_clinics c ON p.home_clinic_id = c.id
WHERE (getvariable('selected_clinic') = 'All Clinics' OR c.name = getvariable('selected_clinic'))
GROUP BY c.name
ORDER BY count(*) DESC;
