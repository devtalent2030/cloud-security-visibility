-- ===========================================================
-- AWS Athena CloudTrail Setup & Query
-- ===========================================================
-- This script contains:
--   1. Table DDL for CloudTrail logs in S3 (org-level trail)
--   2. Example query to retrieve recent events
-- 
-- Notes:
-- - Adjust bucket name, org-id, and account-id as needed.
-- - Must always include static filters for account/region/year/month/day.
-- - CROSS JOIN UNNEST(Records) is required to flatten CloudTrail JSON.
-- ===========================================================

-- 1) Drop table if it exists
DROP TABLE IF EXISTS logging.cloudtrail_org;

-- 2) Create external table for CloudTrail JSON logs
CREATE EXTERNAL TABLE logging.cloudtrail_org (
  Records array<struct<
    eventVersion:string,
    userIdentity:struct<
      type:string,
      principalId:string,
      arn:string,
      accountId:string,
      invokedBy:string,
      accessKeyId:string,
      sessionContext:struct<
        attributes:struct<mfaAuthenticated:string,creationDate:string>,
        sessionIssuer:struct<
          type:string,
          principalId:string,
          arn:string,
          accountId:string,
          userName:string
        >
      >
    >,
    eventTime:string,
    eventSource:string,
    eventName:string,
    awsRegion:string,
    sourceIPAddress:string
  >>
)
PARTITIONED BY (
  account string,
  region  string,
  year    string,
  month   string,
  day     string
)
ROW FORMAT SERDE 'org.openx.data.jsonserde.JsonSerDe'
LOCATION 's3://org-audit-logs-03017239529517181718178171718-us-east-1-demo/AWSLogs/'
TBLPROPERTIES (
  'projection.enabled'='true',
  'projection.account.type'='enum',
  'projection.account.values'='108271871935',
  'projection.region.type'='enum',
  'projection.region.values'='us-east-1',
  'projection.year.type'='integer',
  'projection.year.range'='2024,2030',
  'projection.year.format'='%04d',
  'projection.month.type'='integer',
  'projection.month.range'='1,12',
  'projection.month.format'='%02d',
  'projection.day.type'='integer',
  'projection.day.range'='1,31',
  'projection.day.format'='%02d',
  'storage.location.template'='s3://org-audit-logs-03017239529517181718178171718-us-east-1-demo/AWSLogs/o-jcnykaukey/${account}/CloudTrail/${region}/${year}/${month}/${day}/'
);

-- 3) Query Example: Fetch last 20 CloudTrail events for given day
SELECT
  from_iso8601_timestamp(r.eventTime) AS ts,
  r.eventName,
  r.eventSource,
  r.userIdentity.arn AS actor,
  r.sourceIPAddress
FROM logging.cloudtrail_org
CROSS JOIN UNNEST(Records) AS t(r)
WHERE account='108271871935'
  AND region='us-east-1'
  AND year='2025'
  AND month='08'
  AND day='31'
ORDER BY ts DESC
LIMIT 20;
