-- Restore Adventureworks
USE [master]
ALTER DATABASE [AdventureWorks2016] SET OFFLINE WITH ROLLBACK IMMEDIATE
GO
RESTORE DATABASE [AdventureWorks2016] 
FROM  DISK = N'AdventureWorks2016.bak' 
WITH  FILE = 2,  
MOVE N'AdventureWorks2016_Data' 
	TO N'C:\Program Files\Microsoft SQL Server\MSSQL14.SQL2017\MSSQL\DATA\AdventureWorks2016_Data.mdf',  
MOVE N'AdventureWorks2016_Log' 
	TO N'C:\Program Files\Microsoft SQL Server\MSSQL14.SQL2017\MSSQL\DATA\AdventureWorks2016_Log.ldf',  
NOUNLOAD,  REPLACE,  STATS = 5

GO

-- Remove audit file
USE [master]
GO
ALTER SERVER AUDIT [ObjectAccessLog] WITH (STATE = OFF) -- Disable Log
GO
DROP SERVER AUDIT [ObjectAccessLog]
GO

-- Remove audit job
USE [msdb]
GO
EXEC msdb.dbo.sp_delete_job @job_name = 'Daily - Persist Audit Operations', @delete_unused_schedule=1
GO

-- Remove audit database
USE [master]
GO
ALTER DATABASE [Audit] SET OFFLINE WITH ROLLBACK IMMEDIATE
ALTER DATABASE [Audit] SET ONLINE WITH ROLLBACK IMMEDIATE --so files are dropped
DROP DATABASE Audit
GO

/*
SELECT db_name(database_id), encryption_state,   
percent_complete, key_algorithm, key_length
FROM sys.dm_database_encryption_keys

SELECT * FROM sys.symmetric_keys;
SELECT * FROM sys.certificates;
SELECT * FROM sys.asymmetric_keys;
*/

-- Teardown

-- Delete cert and key backup files
EXEC sp_configure 'show advanced options',1
RECONFIGURE
EXEC sp_configure xp_cmdshell,1
RECONFIGURE
EXEC xp_cmdshell 'del "C:\Program Files\Microsoft SQL Server\MSSQL14.SQL2017\MSSQL\DATA\MyServerCert.crt"'
EXEC xp_cmdshell 'del "C:\Program Files\Microsoft SQL Server\MSSQL14.SQL2017\MSSQL\DATA\MyServerCert.pvk"'
EXEC sp_configure xp_cmdshell,0
RECONFIGURE
EXEC sp_configure 'show advanced options',0
RECONFIGURE
GO

-- Remove TDE from the Database
USE master
GO
ALTER DATABASE AdventureWorks2016 SET ENCRYPTION OFF
GO

-- Remove the Database Encryption Key
USE AdventureWorks2016
GO
DROP DATABASE ENCRYPTION KEY
GO

-- Remove the Server Certificate
USE master
GO
DROP CERTIFICATE MyServerCert

-- Remove the Database Master Key
USE master
GO
DROP MASTER KEY

