﻿--NOTE: DO NOT add a using statement for a specific database as we need to support the ability to apply the same script to multiple target databases.

SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

SET ANSI_PADDING ON
GO

CREATE TABLE [dbo].[WeatherModel] (

[WeatherModelId] [int] Identity(1,1) NOT NULL,
[ModelName] [varchar](50) NOT NULL,
--------------------------------------------------
--Footer attributes to be included in most entities
--------------------------------------------------
[GlobalId] [uniqueidentifier] NOT NULL, --Note: Be sure to add NONCLUSTERED INDEX IX_SOMETABLE below
[Created] [datetime] NOT NULL,
[CreatedBy] [varchar](25) NOT NULL,
[LastModified] [datetime] NOT NULL,
[LastModifiedBy] [varchar](25) NOT NULL,

 CONSTRAINT [PK_WeatherModel] PRIMARY KEY CLUSTERED 
(
	[WeatherModelId] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]

GO

SET ANSI_PADDING OFF
GO
