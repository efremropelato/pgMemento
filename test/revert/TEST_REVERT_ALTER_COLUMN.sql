-- TEST_REVERT_ALTER_COLUMN.sql
--
-- Author:      Felix Kunde <felix-kunde@gmx.de>
--
--              This script is free software under the LGPL Version 3
--              See the GNU Lesser General Public License at
--              http://www.gnu.org/copyleft/lgpl.html
--              for more details.
-------------------------------------------------------------------------------
-- About:
-- Script that checks log tables when an ALTER COLUMN event is reverted
-------------------------------------------------------------------------------
--
-- ChangeLog:
--
-- Version | Date       | Description                                    | Author
-- 0.1.0     2018-10-03   initial commit                                   FKun
--

-- get test number
SELECT nextval('pgmemento.test_seq') AS n \gset

\echo
\echo 'TEST ':n': pgMemento revert ALTER COLUMN event'

\echo
\echo 'TEST ':n'.1: Revert RENAME COLUMN event'
DO
$$
DECLARE
  test_transaction INTEGER;
BEGIN
  -- set session_info to query logged transaction later
  PERFORM set_config('pgmemento.session_info', '{"message":"Reverting rename column"}'::text, FALSE);

  -- get transaction_id of last rename column event
  PERFORM
    pgmemento.revert_transaction(transaction_id)
  FROM
    pgmemento.table_event_log
  WHERE
    op_id = 22;

  -- query for logged transaction
  SELECT
    id
  INTO
    test_transaction
  FROM
    pgmemento.transaction_log
  WHERE
    session_info @> '{"message":"Reverting rename column"}'::jsonb;

  ASSERT test_transaction IS NOT NULL, 'Error: Did not find test entry in transaction_log table!';

  -- save transaction_id for next tests
  PERFORM set_config('pgmemento.revert_rename_column_test', test_transaction::text, FALSE);

  -- query for logged table event
  ASSERT (
    SELECT EXISTS (
      SELECT
        id
      FROM
        pgmemento.table_event_log
      WHERE
        transaction_id = test_transaction
        AND op_id = 22
    )
  ), 'Error: Did not find test entry in table_event_log table!';
END;
$$
LANGUAGE plpgsql;


\echo
\echo 'TEST ':n'.2: Check entries in audit_column_log table'
DO
$$
DECLARE
  test_transaction INTEGER;
  colnames TEXT[];
  datatypes TEXT[];
  tid_ranges numrange[];
BEGIN
  test_transaction := current_setting('pgmemento.revert_rename_column_test')::int;

  -- get logs of altered column
  SELECT
    array_agg(column_name ORDER BY id),
    array_agg(data_type ORDER BY id),
    array_agg(txid_range ORDER BY id)
  INTO
    colnames,
    datatypes,
    tid_ranges
  FROM
    pgmemento.audit_column_log
  WHERE
    upper(txid_range) = test_transaction
    OR lower(txid_range) = test_transaction;

  ASSERT colnames[1] = 'test_tstzrange_column', 'Did not find column ''%'' in audit_column_log', colnames[1];
  ASSERT colnames[2] = 'test_tsrange_column', 'Did not find column ''%'' in audit_column_log', colnames[2];
  ASSERT datatypes[1] = datatypes[2], 'Error: Logged data types of renamed column in audit_column_log is not identical.';
  ASSERT upper(tid_ranges[1]) = test_transaction, 'Error: Upper transaction id % does not match the id % of ALTER COLUMN event', upper(tid_ranges[1]), test_transaction;
  ASSERT lower(tid_ranges[2]) = test_transaction, 'Error: Starting transaction id % does not match the id % of ALTER COLUMN event', lower(tid_ranges[2]), test_transaction;
END;
$$
LANGUAGE plpgsql;


\echo
\echo 'TEST ':n'.3: Revert ALTER COLUMN event'
DO
$$
DECLARE
  test_txid BIGINT := txid_current();
  test_transaction INTEGER;
  test_event INTEGER;
  test_tsrange tsrange;
BEGIN
  -- set session_info to query logged transaction later
  PERFORM set_config('pgmemento.session_info', '{"message":"Reverting alter column"}'::text, FALSE);

  -- get transaction_id of last alter column event
  PERFORM
    pgmemento.revert_transaction(transaction_id)
  FROM
    pgmemento.table_event_log
  WHERE
    op_id = 5;

  -- query for logged transaction
  SELECT
    id
  INTO
    test_transaction
  FROM
    pgmemento.transaction_log
  WHERE
    session_info @> '{"message":"Reverting alter column"}'::jsonb;

  ASSERT test_transaction IS NOT NULL, 'Error: Did not find test entry in transaction_log table!';

  -- save transaction_id for next tests
  PERFORM set_config('pgmemento.revert_alter_column_test', test_transaction::text, FALSE);

  -- query for logged table event
  SELECT
    id
  INTO
    test_event
  FROM
    pgmemento.table_event_log
  WHERE
    transaction_id = test_transaction
    AND op_id = 5;

  ASSERT test_event IS NOT NULL, 'Error: Did not find test entry in table_event_log table!';

  -- save event_id for next test
  PERFORM set_config('pgmemento.revert_alter_column_test_event', test_event::text, FALSE);
END;
$$
LANGUAGE plpgsql;


\echo
\echo 'TEST ':n'.4: Check entries in audit_column_log table'
DO
$$
DECLARE
  test_transaction INTEGER;
  colnames TEXT[];
  datatypes TEXT[];
  tid_ranges numrange[];
BEGIN
  test_transaction := current_setting('pgmemento.revert_alter_column_test')::int;

  -- get logs of altered column
  SELECT
    array_agg(column_name ORDER BY id),
    array_agg(data_type ORDER BY id),
    array_agg(txid_range ORDER BY id)
  INTO
    colnames,
    datatypes,
    tid_ranges
  FROM
    pgmemento.audit_column_log
  WHERE
    upper(txid_range) = test_transaction
    OR lower(txid_range) = test_transaction;

  ASSERT colnames[1] = colnames[2], 'Error: Logged names of altered column in audit_column_log is not identical.';
  ASSERT datatypes[1] = 'tstzrange', 'Expected tstzrange data type, but found ''%'' instead', datatypes[1];
  ASSERT datatypes[2] = 'tsrange', 'Expected tsrange data type, but found ''%'' instead', datatypes[2];
  ASSERT upper(tid_ranges[1]) = test_transaction, 'Error: Upper transaction id % does not match the id % of ALTER COLUMN event', lower(tid_ranges[1]), test_transaction;
  ASSERT lower(tid_ranges[2]) = test_transaction, 'Error: Starting transaction id % does not match the id % of ALTER COLUMN event', lower(tid_ranges[2]), test_transaction;
END;
$$
LANGUAGE plpgsql;
