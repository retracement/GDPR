-- Run VA Tool against AdventureWorks2016


/*******************************************************/
/* VA1245 - The dbo information should be              */
/* consistent between the target DB and master         */
/* Remediation: Use ALTER AUTHORIZATION DDL to specify */
/* the user that should be the dbo for the database    */
/*******************************************************/
SELECT name, owner_sid FROM sys.databases 
	WHERE name = 'AdventureWorks2016' --owner_sid should equal 0x01 for sa;


-- Change Database Owner
USE AdventureWorks2016
GO
EXEC sp_changedbowner 'sa'


-- Run VA Tool against AdventureWorks2016


/**********************************************/
/* VA1143 - 'dbo' user should not be used for */
/* normal service operation                   */
/* Remediation:Create users with low          */
/* privileges to access the DB and any data   */
/* stored in it with the appropriate set of   */
/* permissions.                               */
/**********************************************/
-- Look at database users via GUI and add low 
-- privilaged user retracement as db_datareader


-- Run VA Tool against AdventureWorks2016
-- Run remediation script via GUI for the following vulnerability:
-- VA1054 - Excessive permissions should not be 
-- granted to PUBLIC role on objects or columns
/*
REVOKE SELECT ON [sys].[external_libraries] FROM PUBLIC
REVOKE SELECT ON [sys].[external_library_files] FROM PUBLIC
*/


-- Run VA Tool against AdventureWorks2016


/***********************************************************/
/* VA1219 - Transparent data encryption should be enabled  */
/* Remediation:Enable TDE on the affected database.        */
/* Please follow the instructions on http://bit.ly/2gXMsaQ */
/***********************************************************/

-- Service Master Key created at SQL Server Setup

-- Create Database Master Key (itself encrypted by Service Master Key)
USE MASTER
GO
CREATE MASTER KEY ENCRYPTION BY PASSWORD = 'Password1'
GO


-- Create Certificate (from Database Master Key)
USE MASTER
GO
CREATE CERTIFICATE MyServerCert WITH SUBJECT = 'My DEK Certificate';  
GO


-- Create Database Encryption key (itself encrypted by the Certificate)
USE AdventureWorks2016;  
GO 
CREATE DATABASE ENCRYPTION KEY  
WITH ALGORITHM = AES_128  
ENCRYPTION BY SERVER CERTIFICATE MyServerCert;  
GO


-- Backup Certificate
USE master
GO
BACKUP CERTIFICATE MyServerCert TO FILE = 'MyServerCert.crt'
	WITH PRIVATE KEY(FILE='MyServerCert.pvk',  
	ENCRYPTION BY PASSWORD='MyUltraSecurePassword1');


-- Turn on TDE
ALTER DATABASE AdventureWorks2016  
SET ENCRYPTION ON;  
GO  


-- Run VA Tool against AdventureWorks2016
