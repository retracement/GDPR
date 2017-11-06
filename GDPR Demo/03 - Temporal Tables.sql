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

-- Convert table into a system managed temporal table
USE [AdventureWorks2016]
GO
ALTER TABLE [Person].[Person] ADD 
	/* record validity start time column */
	SysStartTime datetime2 GENERATED ALWAYS AS ROW START HIDDEN -- if hidden not used, columns visible on select
		NOT NULL DEFAULT '1 jan 2010', -- must be datetime2 and NOT NULL (will default to this if not specified)
	/* record validity end time column */
	SysEndTime datetime2 GENERATED ALWAYS AS ROW END HIDDEN 
		NOT NULL DEFAULT CONVERT(DATETIME2, '9999-12-31 23:59:59.9999999'),
	PERIOD FOR SYSTEM_TIME (SysStartTime,SysEndTime);

ALTER TABLE [Person].[Person]
    SET (SYSTEM_VERSIONING = ON (HISTORY_TABLE = dbo.Person_History)) --not needed;
GO


-- Take a look at the table
SELECT TOP 10 * FROM [Person].[Person] -- Notice the "hidden" columns are missing


-- Lets see how many Richards we have
SELECT FirstName, COUNT(*) 'Count' FROM [Person].[Person]
	GROUP BY FirstName
	ORDER BY 2 DESC


-- Lets maliciously update our Richards
UPDATE [Person].[Person] SET FirstName = 'Ricky'
WHERE FirstName = 'Richard'


-- Lets see how many Richards we have now
SELECT FirstName, COUNT(*) 'Count' FROM [Person].[Person]
	GROUP BY FirstName
	ORDER BY 2 DESC


-- We can query the history table directly (if we want)
SELECT * FROM [dbo].[Person_History]


-- Lets look at our data a few days ago
SELECT FirstName, COUNT(*) 'Count' FROM [Person].[Person]
	FOR SYSTEM_TIME AS OF '2017-10-31'
	GROUP BY FirstName
	ORDER BY 2 DESC;


-- Lets repair our data!
UPDATE p
	SET FirstName = t.FirstName
	FROM [Person].[Person] p
	JOIN [Person].[Person] FOR SYSTEM_TIME AS OF '2017-10-31' t
	ON p.BusinessEntityID = t.BusinessEntityID
	WHERE p.FirstName <> t.FirstName;


-- Lets look at our data now
SELECT FirstName, COUNT(*) 'Count' FROM [Person].[Person]
	GROUP BY FirstName
	ORDER BY 2 DESC;


-- Turn off temporal and delete history
ALTER TABLE [Person].[Person] SET (SYSTEM_VERSIONING = OFF);
GO
DELETE FROM [dbo].[Person_History]


-- Turn temporal back on
ALTER TABLE [Person].[Person] SET (SYSTEM_VERSIONING = ON
 (HISTORY_TABLE=[dbo].[Person_History],DATA_CONSISTENCY_CHECK=ON)
);

