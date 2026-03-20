col INDEX_NAME for a30;
col INDEX_TYPE for a15;
col TABLE_NAME for a30;
select INDEX_NAME, INDEX_TYPE, TABLE_NAME, TABLE_TYPE, PARTITIONED, tablespace_name from user_indexes;
