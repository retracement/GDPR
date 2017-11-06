/************************************************************
*   All scripts contained within are Copyright � 2015 of    *
*   SQLCloud Limited, whether they are derived or actual    *
*   works of SQLCloud Limited or its representatives        *
*************************************************************
*   All rights reserved. No part of this work may be        *
*   reproduced or transmitted in any form or by any means,  *
*   electronic or mechanical, including photocopying,       *
*   recording, or by any information storage or retrieval   *
*   system, without the prior written permission of the     *
*   copyright owner and the publisher.                      *
************************************************************/

-- Create Audit Log
USE [master]
GO
CREATE SERVER AUDIT [ObjectAccessLog]
TO FILE
(	FILEPATH = N'C:\Program Files\Microsoft SQL Server\MSSQL14.SQL2017\MSSQL\Log\'
	,MAXSIZE = 200 MB
	,MAX_ROLLOVER_FILES = 4
	,RESERVE_DISK_SPACE = ON
)
WITH
(	QUEUE_DELAY = 1000
	,ON_FAILURE = CONTINUE
	,AUDIT_GUID = 'f74005ef-dca5-4a9d-b2b9-6198613bf533'
)
WHERE (NOT [schema_name] like 'sys') -- Ignore system schema events
GO

ALTER SERVER AUDIT [ObjectAccessLog] WITH (STATE = ON) -- Enable Log
GO


-- Create and enable audit specification for database
USE [AdventureWorks2016] -- Run this code block in any database you want to audit
GO
CREATE DATABASE AUDIT SPECIFICATION [ObjectAccessSpecification]
FOR SERVER AUDIT [ObjectAccessLog]
ADD (SCHEMA_OBJECT_ACCESS_GROUP) -- When an object is touched fire
WITH (STATE = ON)
GO


-- Run a few operations on AdventureWorks2016, 
-- Browse through GUI browse ObjectAccessLog


-- Not very useful in XML, so let's persist to relational!
-- Create database as audit repository
-- But consider cloud for data archival
CREATE DATABASE Audit
GO


-- Create audit events table
USE Audit
GO
CREATE TABLE [dbo].[user_operations](
	[event_time] [datetime2](7) NOT NULL,
	[sequence_number] [int] NOT NULL,
	[action_id] [varchar](4) NULL,
	[succeeded] [bit] NOT NULL,
	[is_column_permission] [bit] NOT NULL,
	[session_id] [smallint] NOT NULL,
	[server_principal_id] [int] NOT NULL,
	[session_server_principal_name] [nvarchar](128) NULL,
	[server_principal_name] [nvarchar](128) NULL,
	[server_principal_sid] [varbinary](85) NULL,
	[database_principal_name] [nvarchar](128) NULL,
	[target_server_principal_name] [nvarchar](128) NULL,
	[target_database_principal_name] [nvarchar](128) NULL,
	[server_instance_name] [nvarchar](128) NULL,
	[database_name] [nvarchar](128) NULL,
	[schema_name] [nvarchar](128) NULL,
	[object_name] [nvarchar](128) NULL,
	[statement] [nvarchar](4000) NULL,
	[additional_information] [nvarchar](4000) NULL
) ON [PRIMARY]

ALTER TABLE [dbo].[user_operations] REBUILD PARTITION = ALL  
WITH (DATA_COMPRESSION = PAGE);


-- Create regular job to persist audit log to database
USE [msdb]
GO
BEGIN TRANSACTION
DECLARE @ReturnCode INT
SELECT @ReturnCode = 0
IF NOT EXISTS (SELECT name FROM msdb.dbo.syscategories WHERE name=N'[Production - Continuous]' AND category_class=1)
BEGIN
EXEC @ReturnCode = msdb.dbo.sp_add_category @class=N'JOB', @type=N'LOCAL', @name=N'[Production - Continuous]'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback

END

DECLARE @jobId BINARY(16)
EXEC @ReturnCode =  msdb.dbo.sp_add_job @job_name=N'Daily - Persist Audit Operations', 
		@enabled=1, 
		@notify_level_eventlog=0, 
		@notify_level_email=2, 
		@notify_level_netsend=0, 
		@notify_level_page=0, 
		@delete_level=0, 
		@description=N'No description available.', 
		@category_name=N'[Production - Continuous]', 
		@owner_login_name=N'sa', 
		@notify_email_operator_name=N'', @job_id = @jobId OUTPUT
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobstep @job_id=@jobId, @step_name=N'Prepare staging table for load', 
		@step_id=1, 
		@cmdexec_success_code=0, 
		@on_success_action=3, 
		@on_success_step_id=0, 
		@on_fail_action=2, 
		@on_fail_step_id=0, 
		@retry_attempts=0, 
		@retry_interval=0, 
		@os_run_priority=0, @subsystem=N'TSQL', 
		@command=N'USE [Audit]
GO
IF NOT EXISTS (SELECT * FROM sys.objects --if stage table doesn''t exist, need to create it
			WHERE object_id = OBJECT_ID(N''[dbo].[user_operations_stage]'') 
			AND type IN (N''U''))

BEGIN
		CREATE TABLE [dbo].[user_operations_stage](
			[event_time] [datetime2](7) NOT NULL,
			[sequence_number] [int] NOT NULL,
			[action_id] [varchar](4) NULL,
			[succeeded] [bit] NOT NULL,
			[is_column_permission] [bit] NOT NULL,
			[session_id] [smallint] NOT NULL,
			[server_principal_id] [int] NOT NULL,
			[session_server_principal_name] [nvarchar](128) NULL,
			[server_principal_name] [nvarchar](128) NULL,
			[server_principal_sid] [varbinary](85) NULL,
			[database_principal_name] [nvarchar](128) NULL,
			[target_server_principal_name] [nvarchar](128) NULL,
			[target_database_principal_name] [nvarchar](128) NULL,
			[server_instance_name] [nvarchar](128) NULL,
			[database_name] [nvarchar](128) NULL,
			[schema_name] [nvarchar](128) NULL,
			[object_name] [nvarchar](128) NULL,
			[statement] [nvarchar](4000) NULL,
			[additional_information] [nvarchar](4000) NULL
		) ON [PRIMARY]

		ALTER TABLE [dbo].[user_operations_stage] REBUILD PARTITION = ALL  
		WITH (DATA_COMPRESSION = PAGE);  
		PRINT ''Missing [dbo].[user_operations_stage] table created successfully.''
	END 
ELSE
	IF EXISTS (SELECT * FROM sys.indexes --if index exists on table, drop it
		WHERE name = ''ix_user_operations_stage_event_time_sequence_number '' 
		AND object_id = OBJECT_ID(N''[dbo].[user_operations_stage]''))
	BEGIN
		DROP INDEX ix_user_operations_stage_event_time_sequence_number  ON [dbo].[user_operations_stage]
		PRINT ''Index on [dbo].[user_operations_stage] table dropped successfully.''
	END
GO

TRUNCATE TABLE [dbo].[user_operations_stage]', 
		@database_name=N'Audit', 
		@flags=0
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobstep @job_id=@jobId, @step_name=N'Load staging table from database audit', 
		@step_id=2, 
		@cmdexec_success_code=0, 
		@on_success_action=3, 
		@on_success_step_id=0, 
		@on_fail_action=2, 
		@on_fail_step_id=0, 
		@retry_attempts=0, 
		@retry_interval=0, 
		@os_run_priority=0, @subsystem=N'TSQL', 
		@command=N'SET QUOTED_IDENTIFIER ON
GO
USE [Audit]
GO
--insert audit records to stage table
INSERT INTO dbo.user_operations_stage
SELECT
	[event_time], 
	[sequence_number],
	[action_id],
	[succeeded],
	--[permission_bitmask],
	[is_column_permission],
	[session_id],
	[server_principal_id],
	--[database_principal_id],
	--[target_server_principal_id],
	--[target_database_principal_id],
	--[object_id],
	--[class_type],
	[session_server_principal_name],
	[server_principal_name],
	[server_principal_sid],
	[database_principal_name],
	[target_server_principal_name],
	--[target_server_principal_sid],
	[target_database_principal_name],
	[server_instance_name],
	[database_name],
	[schema_name],
	[object_name],
	[statement],
	[additional_information]
	--[file_name],
	--[audit_file_offset],
	--[user_defined_event_id],
	--[user_defined_information],
	--[audit_schema_version],
	--[sequence_group_id]
FROM sys.fn_get_audit_file (N''C:\Program Files\Microsoft SQL Server\MSSQL14.SQL2017\MSSQL\Log\ObjectAccessLog*'', default, default)
GO

CREATE CLUSTERED INDEX ix_user_operations_stage_event_time_sequence_number 
ON [dbo].[user_operations_stage] ([event_time],[sequence_number])
GO', 
		@database_name=N'Audit', 
		@flags=0
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobstep @job_id=@jobId, @step_name=N'Upload new records to user_operations table', 
		@step_id=3, 
		@cmdexec_success_code=0, 
		@on_success_action=3, 
		@on_success_step_id=0, 
		@on_fail_action=2, 
		@on_fail_step_id=0, 
		@retry_attempts=0, 
		@retry_interval=0, 
		@os_run_priority=0, @subsystem=N'TSQL', 
		@command=N'SET QUOTED_IDENTIFIER ON
GO
USE [Audit]
GO
--upload all records from stage not currently present in audit
INSERT INTO dbo.user_operations (
[event_time], 
	[sequence_number],
	[action_id],
	[succeeded],
	[is_column_permission],
	[session_id],
	[server_principal_id],
	[session_server_principal_name],
	[server_principal_name],
	[server_principal_sid],
	[database_principal_name],
	[target_server_principal_name],
	[target_database_principal_name],
	[server_instance_name],
	[database_name],
	[schema_name],
	[object_name],
	[statement],
	[additional_information])
SELECT 
	stage.[event_time], 
	stage.[sequence_number],
	stage.[action_id],
	stage.[succeeded],
	stage.[is_column_permission],
	stage.[session_id],
	stage.[server_principal_id],
	stage.[session_server_principal_name],
	stage.[server_principal_name],
	stage.[server_principal_sid],
	stage.[database_principal_name],
	stage.[target_server_principal_name],
	stage.[target_database_principal_name],
	stage.[server_instance_name],
	stage.[database_name],
	stage.[schema_name],
	stage.[object_name],
	stage.[statement],
	stage.[additional_information]
FROM dbo.user_operations_stage stage LEFT JOIN dbo.user_operations main
ON
	main.event_time = stage.event_time AND
	main.sequence_number = stage.sequence_number
WHERE main.event_time IS NULL
GO
TRUNCATE TABLE [dbo].[user_operations_stage]', 
		@database_name=N'Audit', 
		@flags=0
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobstep @job_id=@jobId, @step_name=N'Drop the staging table', 
		@step_id=4, 
		@cmdexec_success_code=0, 
		@on_success_action=1, 
		@on_success_step_id=0, 
		@on_fail_action=2, 
		@on_fail_step_id=0, 
		@retry_attempts=0, 
		@retry_interval=0, 
		@os_run_priority=0, @subsystem=N'TSQL', 
		@command=N'USE [Audit]
GO
IF EXISTS (SELECT * FROM sys.objects --if stage table doesn''t exist, need to create it
			WHERE object_id = OBJECT_ID(N''[dbo].[user_operations_stage]'') 
			AND type IN (N''U''))
DROP TABLE [dbo].[user_operations_stage]', 
		@database_name=N'Audit', 
		@flags=0
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_update_job @job_id = @jobId, @start_step_id = 1
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobschedule @job_id=@jobId, @name=N'Every 30 seconds', 
		@enabled=1, 
		@freq_type=4, 
		@freq_interval=1, 
		@freq_subday_type=2, 
		@freq_subday_interval=30, 
		@freq_relative_interval=0, 
		@freq_recurrence_factor=0, 
		@active_start_date=20170228, 
		@active_end_date=99991231, 
		@active_start_time=0, 
		@active_end_time=235959, 
		@schedule_uid=N'd4d38f67-04a9-4e0d-a0dc-decbce4eca80'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobserver @job_id = @jobId, @server_name = N'(local)'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
COMMIT TRANSACTION
GOTO EndSave
QuitWithRollback:
    IF (@@TRANCOUNT > 0) ROLLBACK TRANSACTION
EndSave:
GO

-- Once job has executed, browse user_operations table
