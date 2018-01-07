# Warning! This script with delete and recreate your database and seed it with test data!
# To execute this script:
#   1) Rebuild the solution.  This is needed to compile the dlls to the \bin folder that is referenced in this script.
#   2) Right click this script and select "Open with PowerShell ISE" or "Run With Powershell"
#
# Note: You may need to run the execution policy below for the first time you use this script so that it is allowed to run
#       Set-ExecutionPolicy Unrestricted -Scope CurrentUser

#----------------------------------------------------------
# User Custom - Variables 
#----------------------------------------------------------
$DEPLOYMENT_ENVIRONMENT = "LOCAL" #Valid Environments: LOCAL, TESTHCA, PRODUCTION
$SQLDATAPATH = "C:\Program Files\Microsoft SQL Server\MSSQL11.MSSQLSERVER\MSSQL\DATA\"
#$SQLDATAPATH = "C:\Program Files\Microsoft SQL Server\MSSQL10_50.MSSQLSERVER\MSSQL\DATA\"
#$SQLDATAPATH = "C:\Program Files\Microsoft SQL Server\MSSQL12.MSSQLSERVER\MSSQL\DATA\"
#$SQLDATAPATH = "C:\Program Files (x86)\Microsoft SQL Server\MSSQL11.MSSQLSERVER\MSSQL\DATA\"
#----------------------------------------------------------

$DB_NAME = "DB_WeatherForecaster"
function Get-ScriptDirectory
{
    Split-Path $script:MyInvocation.MyCommand.Path
}
$ROOTPATH = ((Get-ScriptDirectory) + "\")
if($DEPLOYMENT_ENVIRONMENT -eq "LOCAL" -or $DEPLOYMENT_ENVIRONMENT -eq "TEST")
{
	$DB_SERVER = "."
	$BULKIMPORTROOT = $ROOTPATH
	#$BULKIMPORTUNCROOT
	#$BULKIMPORTUNCRAWDATAPATH
	#$BULKIMPORTUNCMINIFIEDPATH
	$TEMPPATH = "C:\workspaces\Temp\"
}
if($DEPLOYMENT_ENVIRONMENT -eq "PRODUCTION")
{
	$DB_SERVER = "." 
	$BULKIMPORTROOT = "."
	$BULKIMPORTUNCROOT = "\\.\"
	$BULKIMPORTUNCRAWDATAPATH = $BULKIMPORTUNCROOT+".\" 
	$BULKIMPORTUNCMINIFIEDPATH = $BULKIMPORTUNCRAWDATAPATH+".\" 
	$TEMPPATH = $BULKIMPORTUNCROOT+"Temp\"
}

$DB_SQLCONNECTIONSTRING = "server=$DB_SERVER;database=$DB_NAME;trusted_connection=true;multipleactiveresultsets=True;"
$startTime = Get-Date
Write-Host ("Database deploy script started: " + $startTime)

$TABLESPATH = $ROOTPATH+"Schemas\dbo\Tables\"
$VIEWSPATH = $ROOTPATH+"Schemas\dbo\Views\"
$TBLTYPESPATH = $ROOTPATH+"Schemas\dbo\Programmability\Types\User-Defined Table Types\"
$FUNCSPATH = $ROOTPATH+"Schemas\dbo\Programmability\Functions\"
$PROCSPATH = $ROOTPATH+"Schemas\dbo\Programmability\Procedures\"
$SCHEMASPATH = $ROOTPATH+"Schemas\"
$POWERSHELLPATH = $ROOTPATH+"Powershell\"
$TABLEDATAPATH = $ROOTPATH+"Scripts\Data\"
$DATAPATHXML = $ROOTPATH+"Scripts\XMLData\"
$DATAPATHJSON = $ROOTPATH+"Scripts\JSONData\"

$SILENTMODE = ($args[0] -eq "-s")
#----------------------------------------------------------

if(!$SILENTMODE)
{
    Do 
    {
        Write-Host "
        ----------Deploy Database----------
        YES = Drop and recreate database $DB_NAME on server $DB_SERVER . Warning all data will be irrecoverable!
        NO = EXIT
        ----------------------------------------"
        $choice1 = read-host -prompt "Do you wish to drop and recreate database $DB_NAME on server $DB_SERVER ? Type YES to continue or NO to exit"
    } 
    until ($choice1 -eq "YES" -or $choice1 -eq "NO" )

    if($choice1 -eq "NO"){
	    EXIT
    }
}

#Note: this helps powershell resolve specific dependencies that were failing due to different versions bound to different assembly dependencies
#      it takes the place of the runtime assembly binding configuration you see in zapi and other non-powershell config files.
#------------------------------------------------------------------------------------------
$OnAssemblyResolve = [System.ResolveEventHandler] {
  param($sender, $e)
  foreach($a in [System.AppDomain]::CurrentDomain.GetAssemblies())
  {
	if($e.Name -like "*Newtonsoft.Json*" -and $a.FullName -like "*Newtonsoft.Json*" )
    {
	  return $a
    }
  }
  return $null
}
[System.AppDomain]::CurrentDomain.add_AssemblyResolve($OnAssemblyResolve)
#------------------------------------------------------------------------------------------

Try
{
	Write-Host "Preparing to import solution assemblies needed to execute this script ..."
    Write-Host ""

    Write-Host "Attempting to import: C:\workspaces\zerver\ZCore\ZH.Utilities\bin\Debug\ZH.Data.dll"
    Add-Type -Path "C:\workspaces\zerver\ZCore\ZH.Utilities\bin\Debug\ZH.Data.dll"

	Write-Host "Attempting to import: C:\workspaces\zerver\ZCore\ZH.Utilities\bin\Debug\ZH.Domain.dll"
    Add-Type -Path "C:\workspaces\zerver\ZCore\ZH.Utilities\bin\Debug\ZH.Domain.dll"
    
	#Note: force Newtonsoft to load into the powershell current app domain so that it exists in CurrentDomain.GetAssemblies()
	Write-Host "Attempting to import:C:\workspaces\zerver\ZCore\ZH.Utilities\bin\Debug\Newtonsoft.Json.dll"
	Add-Type -Path "C:\workspaces\zerver\ZCore\ZH.Utilities\bin\Debug\Newtonsoft.Json.dll"

	Write-Host "Attempting to import:C:\workspaces\zerver\ZCore\ZH.Utilities\bin\Debug\ZH.Utilities.dll"
    Add-Type -Path "C:\workspaces\zerver\ZCore\ZH.Utilities\bin\Debug\ZH.Utilities.dll"
	    
    Write-Host ""
    Write-Host "Attempting to load ZH.Data.Common..ConnectionManager from C:\workspaces\zerver\ZCore\ZH.Utilities\bin\Debug\ZH.Data.dll"
    [ZH.Data.Common.ConnectionManager]::ConnectionString = $DB_SQLCONNECTIONSTRING
    Write-Host ("Successfully loaded ConnectionManager and set connection string: " + [ZH.Data.Common.ConnectionManager]::ConnectionString)
    Write-Host ""
    
	Write-Host "Attempting to load ZH.Utilities.DatabaseManager from C:\workspaces\zerver\ZCore\ZH.Utilities\bin\Debug\ZH.Utilities.dll"
    $dbMgr = New-Object ZH.Utilities.DatabaseManager -ArgumentList @($DB_SERVER, $SQLDATAPATH, $ROOTPATH, $DB_NAME)
    Write-Host "Successfully loaded DatabaseManager"
	$dbExists = $dbMgr.DatabaseExists($DB_NAME)
	if($dbExists)
    {
		Write-Host "Skipping database " $DB_NAME " creation"
    }
	else
	{
		Write-Host "Creating missing database " $DB_NAME
		$dbCreationSucceeded = $dbMgr.CreateDatabaseIfNotExists()
		if(!$dbCreationSucceeded)
		{
			Write-Host "Failed Attempting to create database " $DB_NAME
			EXIT
		}
		Write-Host "Successfully created database "  $DB_NAME
	}	
    Write-Host ""

	Write-Host ("Attempting to load ZH.Data.UnitOfWork from C:\workspaces\zerver\ZCore\ZH.Utilities\bin\Debug\ZH.Data.dll")
    $uow = New-Object ZH.Data.UnitOfWork
    Write-Host "Successfully loaded UnitOfWork"
    Write-Host ""
    
	Write-Host "Attempting to load ZH.Data.Common.ZDBLogger from C:\workspaces\zerver\ZCore\ZH.Utilities\bin\Debug\ZH.Data.dll"
    $logger = New-Object ZH.Data.Common.ZDBLogger -ArgumentList @($uow,"SYSTEM")
    Write-Host "Successfully loaded ZDBLogger"
    Write-Host ""

    Write-Host "Attempting to load ZH.Domain.Publishing.DataVersionManager from C:\workspaces\zerver\ZCore\ZH.Utilities\bin\Debug\ZH.Domain.dll"
    $dvMgr = New-Object ZH.Domain.Publishing.DataVersionManager -ArgumentList @($logger, $uow, $null)    
    $dvMgr.GetMessages()
    Write-Host "Successfully loaded DataVersionManager"
    Write-Host ""

	Write-Host ("Attempting to load ZH.Domain.Publishing.ChargeCodeManager from C:\workspaces\zerver\ZCore\ZH.Domain\bin\Debug\ZH.Domain.dll")
    $ccMgr = New-Object ZH.Domain.Publishing.ChargeCodeManager -ArgumentList @($logger, $uow, $DEPLOYMENT_ENVIRONMENT, $FACILITY_MAP_KEY, $false)
	Write-Host "Successfully loaded ChargeCodeManager"
    Write-Host ""

    Write-Host "Successfully imported all solution assemblies"
    Write-Host ""
		 
}
Catch [system.exception]
{
    Write-Host "Failed to load solution assemblies. Please ensure you rebuild the solution prior to running this script."
	Write-Host ""
	Write-Host $_.Exception.ToString()
    EXIT
}

#preserve database, but drop and recreate the database objects
$dbMgr.PreserveDatabaseDropObjectsOnly([ZH.Utilities.DatabaseManager]::ZDBSchemas)
$dbMgr.GetMessages()

#----------------------------------------------------------
#--Create Database Roles
#----------------------------------------------------------
Write-Host ("creating database roles "+$SCHEMASPATH+"CreateRoles.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($SCHEMASPATH+"CreateRoles.sql")
#--
#--End Create Database Roles ---

#----------------------------------------------------------
#--Create Database tables
#----------------------------------------------------------
#--Begin stghl7 schema ---
Write-Host ("creating "+$TABLESPATHSTAGEHL7+"stghl7.Msg.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLESPATHSTAGEHL7+"stghl7.Msg.sql")
#--
Write-Host ("creating "+$TABLESPATHSTAGEHL7+"stghl7.Ack.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLESPATHSTAGEHL7+"stghl7.Ack.sql")
#--
Write-Host ("creating "+$TABLESPATHSTAGEHL7+"stghl7.MSHSegment.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLESPATHSTAGEHL7+"stghl7.MSHSegment.sql")
#--
Write-Host ("creating "+$TABLESPATHSTAGEHL7+"stghl7.EVNSegment.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLESPATHSTAGEHL7+"stghl7.EVNSegment.sql")
#--
Write-Host ("creating "+$TABLESPATHSTAGEHL7+"stghl7.HCA_TransportationModeLookup.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLESPATHSTAGEHL7+"stghl7.HCA_TransportationModeLookup.sql")
#--
Write-Host ("creating "+$TABLESPATHSTAGEHL7+"stghl7.HCA_PatientLocationLookup.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLESPATHSTAGEHL7+"stghl7.HCA_PatientLocationLookup.sql")
#--
#--End stghl7 schema ---

#--Begin stg schema ---
Write-Host ("creating "+$TABLESPATHSTAGE+"stg.Blk_StudyType.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLESPATHSTAGE+"stg.Blk_StudyType.sql")
#--
Write-Host ("creating "+$TABLESPATHSTAGE+"stg.Blk_DeviceType.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLESPATHSTAGE+"stg.Blk_DeviceType.sql")
#--
Write-Host ("creating "+$TABLESPATHSTAGE+"stg.Blk_DeviceCategory.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLESPATHSTAGE+"stg.Blk_DeviceCategory.sql")
#--
Write-Host ("creating "+$TABLESPATHSTAGE+"stg.Blk_DeviceMaster.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLESPATHSTAGE+"stg.Blk_DeviceMaster.sql")
#--
Write-Host ("creating "+$TABLESPATHSTAGE+"stg.Blk_MedicalCode.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLESPATHSTAGE+"stg.Blk_MedicalCode.sql")
#--
Write-Host ("creating "+$TABLESPATHSTAGE+"stg.Blk_VesselHotspotMap.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLESPATHSTAGE+"stg.Blk_VesselHotspotMap.sql")
#--
Write-Host ("creating "+$TABLESPATHSTAGE+"stg.Blk_GroupStudyType.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLESPATHSTAGE+"stg.Blk_GroupStudyType.sql")
#--
Write-Host ("creating "+$TABLESPATHSTAGE+"stg.Blk_Group.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLESPATHSTAGE+"stg.Blk_Group.sql")
#--
Write-Host ("creating "+$TABLESPATHSTAGE+"stg.Blk_BillableItem.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLESPATHSTAGE+"stg.Blk_BillableItem.sql")
#--
Write-Host ("creating "+$TABLESPATHSTAGE+"stg.Min_StudyType.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLESPATHSTAGE+"stg.Min_StudyType.sql")
#--
Write-Host ("creating "+$TABLESPATHSTAGE+"stg.Min_DeviceType.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLESPATHSTAGE+"stg.Min_DeviceType.sql")
#--
Write-Host ("creating "+$TABLESPATHSTAGE+"stg.Min_DeviceCategory.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLESPATHSTAGE+"stg.Min_DeviceCategory.sql")
#--
Write-Host ("creating "+$TABLESPATHSTAGE+"stg.Min_DeviceMaster.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLESPATHSTAGE+"stg.Min_DeviceMaster.sql")
#--
Write-Host ("creating "+$TABLESPATHSTAGE+"stg.Min_MedicalCode.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLESPATHSTAGE+"stg.Min_MedicalCode.sql")
#--
Write-Host ("creating "+$TABLESPATHSTAGE+"stg.Min_VesselHotspotMap.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLESPATHSTAGE+"stg.Min_VesselHotspotMap.sql")
#--
Write-Host ("creating "+$TABLESPATHSTAGE+"stg.Min_GroupStudyType.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLESPATHSTAGE+"stg.Min_GroupStudyType.sql")
#--
Write-Host ("creating "+$TABLESPATHSTAGE+"stg.Min_Group.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLESPATHSTAGE+"stg.Min_Group.sql")
#--
Write-Host ("creating "+$TABLESPATHSTAGE+"stg.StudyType.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLESPATHSTAGE+"stg.StudyType.sql")
#--
Write-Host ("creating "+$TABLESPATHSTAGE+"stg.DeviceType.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLESPATHSTAGE+"stg.DeviceType.sql")
#--
Write-Host ("creating "+$TABLESPATHSTAGE+"stg.DeviceCategory.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLESPATHSTAGE+"stg.DeviceCategory.sql")
#--
Write-Host ("creating "+$TABLESPATHSTAGE+"stg.DeviceMaster.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLESPATHSTAGE+"stg.DeviceMaster.sql")
#--
Write-Host ("creating "+$TABLESPATHSTAGE+"stg.MedicalCode.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLESPATHSTAGE+"stg.MedicalCode.sql")
#--
Write-Host ("creating "+$TABLESPATHSTAGE+"stg.VesselHotspotMap.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLESPATHSTAGE+"stg.VesselHotspotMap.sql")
#--
Write-Host ("creating "+$TABLESPATHSTAGE+"stg.GroupStudyType.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLESPATHSTAGE+"stg.GroupStudyType.sql")
#--
Write-Host ("creating "+$TABLESPATHSTAGE+"stg.Group.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLESPATHSTAGE+"stg.Group.sql")
#--
Write-Host ("creating "+$TABLESPATHSTAGE+"stg.GroupParent.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLESPATHSTAGE+"stg.GroupParent.sql")
#--
Write-Host ("creating "+$TABLESPATHSTAGE+"stg.BillableItem.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLESPATHSTAGE+"stg.BillableItem.sql")
#--
#--End stg schema ---

#--Begin inv schema ---
Write-Host ("creating "+$TABLESPATHINV+"inv.ItemType.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLESPATHINV+"inv.ItemType.sql")
#--
Write-Host ("creating "+$TABLESPATHINV+"inv.DeviceType.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLESPATHINV+"inv.DeviceType.sql")
#--
Write-Host ("creating "+$TABLESPATHINV+"inv.DeviceCategory.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLESPATHINV+"inv.DeviceCategory.sql")
#--
Write-Host ("creating "+$TABLESPATHINV+"inv.Item.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLESPATHINV+"inv.Item.sql")
#--
Write-Host ("creating "+$TABLESPATHINV+"inv.DeviceMaster.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLESPATHINV+"inv.DeviceMaster.sql")
#--
Write-Host ("creating "+$TABLESPATHINV+"inv.Device.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLESPATHINV+"inv.Device.sql")
#--
#--End inv schema ---

#--Begin dbo schema ---
Write-Host ("creating "+$TABLESPATH+"dbo.SchemaVersions.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLESPATH+"dbo.SchemaVersions.sql")
#--
Write-Host ("creating "+$TABLESPATH+"dbo.Group.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLESPATH+"dbo.Group.sql")
#--
Write-Host ("creating "+$TABLESPATH+"dbo.GroupParent.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLESPATH+"dbo.GroupParent.sql")
#--
Write-Host ("creating "+$TABLESPATH+"dbo.SystemVersionHistory.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLESPATH+"dbo.SystemVersionHistory.sql")
#--
Write-Host ("creating "+$TABLESPATH+"dbo.SystemComponent.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLESPATH+"dbo.SystemComponent.sql")
#--
Write-Host ("creating "+$TABLESPATH+"dbo.SystemConfiguration.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLESPATH+"dbo.SystemConfiguration.sql")
#--
Write-Host ("creating "+$TABLESPATH+"dbo.EnlargementSizeType.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLESPATH+"dbo.EnlargementSizeType.sql")
#--
Write-Host ("creating "+$TABLESPATH+"dbo.AppearanceType.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLESPATH+"dbo.AppearanceType.sql")
#--
Write-Host ("creating "+$TABLESPATH+"dbo.BillableItemType.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLESPATH+"dbo.BillableItemType.sql")
#--
Write-Host ("creating "+$TABLESPATH+"dbo.SeverityType.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLESPATH+"dbo.SeverityType.sql")
#--
Write-Host ("creating "+$TABLESPATH+"dbo.ContactInfoType.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLESPATH+"dbo.ContactInfoType.sql")
#--
Write-Host ("creating "+$TABLESPATH+"dbo.CardiacOutputType.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLESPATH+"dbo.CardiacOutputType.sql")
#--
Write-Host ("creating "+$TABLESPATH+"dbo.MeasureSiteType.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLESPATH+"dbo.MeasureSiteType.sql")
#--
Write-Host ("creating "+$TABLESPATH+"dbo.MedicalPersonnelType.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLESPATH+"dbo.MedicalPersonnelType.sql")
#--
Write-Host ("creating "+$TABLESPATH+"dbo.MedicalCodeType.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLESPATH+"dbo.MedicalCodeType.sql")
#--
Write-Host ("creating "+$TABLESPATH+"dbo.RecommendationType.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLESPATH+"dbo.RecommendationType.sql")
#--
Write-Host ("creating "+$TABLESPATH+"dbo.Log.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLESPATH+"dbo.Log.sql")
#--
Write-Host ("creating "+$TABLESPATH+"dbo.PathologyCategoryType.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLESPATH+"dbo.PathologyCategoryType.sql")
#--
Write-Host ("creating "+$TABLESPATH+"dbo.PathologyType.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLESPATH+"dbo.PathologyType.sql")
#--
Write-Host ("creating "+$TABLESPATH+"dbo.ProcedureType.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLESPATH+"dbo.ProcedureType.sql")
#--
Write-Host ("creating "+$TABLESPATH+"dbo.CaseStatusType.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLESPATH+"dbo.CaseStatusType.sql")
#--
Write-Host ("creating "+$TABLESPATH+"dbo.GenderMap.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLESPATH+"dbo.GenderMap.sql")
#--
Write-Host ("creating "+$TABLESPATH+"dbo.GenderType.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLESPATH+"dbo.GenderType.sql")
#--
Write-Host ("creating "+$TABLESPATH+"dbo.PropertyValueType.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLESPATH+"dbo.PropertyValueType.sql")
#--
Write-Host ("creating "+$TABLESPATH+"dbo.StudyType.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLESPATH+"dbo.StudyType.sql")
#--
Write-Host ("creating "+$TABLESPATH+"dbo.AngiogramType.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLESPATH+"dbo.AngiogramType.sql")
#--
Write-Host ("creating "+$TABLESPATH+"dbo.DispositionType.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLESPATH+"dbo.DispositionType.sql")
#--
Write-Host ("creating "+$TABLESPATH+"dbo.ApproachType.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLESPATH+"dbo.ApproachType.sql")
#--
Write-Host ("creating "+$TABLESPATH+"dbo.CatheterContextType.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLESPATH+"dbo.CatheterContextType.sql")
#--
Write-Host ("creating "+$TABLESPATH+"dbo.StentType.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLESPATH+"dbo.StentType.sql")
#--
Write-Host ("creating "+$TABLESPATH+"dbo.PathologyProperty.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLESPATH+"dbo.PathologyProperty.sql")
#--
Write-Host ("creating "+$TABLESPATH+"dbo.Patient.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLESPATH+"dbo.Patient.sql")
#--
Write-Host ("creating "+$TABLESPATH+"dbo.VariantAnatomy.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLESPATH+"dbo.VariantAnatomy.sql")
#--
Write-Host ("creating "+$TABLESPATH+"dbo.Case.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLESPATH+"dbo.Case.sql")
#--
Write-Host ("creating "+$TABLESPATH+"dbo.CaseProperty.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLESPATH+"dbo.CaseProperty.sql")
#--
Write-Host ("creating "+$TABLESPATH+"dbo.Workflow.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLESPATH+"dbo.Workflow.sql")
#--
Write-Host ("creating "+$TABLESPATH+"dbo.WorkflowStateMachine.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLESPATH+"dbo.WorkflowStateMachine.sql")
#--
Write-Host ("creating "+$TABLESPATH+"dbo.CaseWorkflowHistory.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLESPATH+"dbo.CaseWorkflowHistory.sql")
#--
Write-Host ("creating "+$TABLESPATH+"dbo.Pathology.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLESPATH+"dbo.Pathology.sql")
#--
Write-Host ("creating "+$TABLESPATH+"dbo.PathologyObservation.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLESPATH+"dbo.PathologyObservation.sql")
#--
Write-Host ("creating "+$TABLESPATH+"dbo.PathologyObservationProperty.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLESPATH+"dbo.PathologyObservationProperty.sql")
#--
Write-Host ("creating "+$TABLESPATH+"dbo.CatheterContext.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLESPATH+"dbo.CatheterContext.sql")
#--
Write-Host ("creating "+$TABLESPATH+"dbo.CardiacOutput.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLESPATH+"dbo.CardiacOutput.sql")
#--
Write-Host ("creating "+$TABLESPATH+"dbo.CatheterResistance.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLESPATH+"dbo.CatheterResistance.sql")
#--
Write-Host ("creating "+$TABLESPATH+"dbo.PressureSample.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLESPATH+"dbo.PressureSample.sql")
#--
Write-Host ("creating "+$TABLESPATH+"dbo.O2Saturation.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLESPATH+"dbo.O2Saturation.sql")
#--
Write-Host ("creating "+$TABLESPATH+"dbo.CathCtxMeasurement.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLESPATH+"dbo.CathCtxMeasurement.sql")
#--
Write-Host ("creating "+$TABLESPATH+"dbo.CatheterResistanceCathCtxMeas.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLESPATH+"dbo.CatheterResistanceCathCtxMeas.sql")
#--
Write-Host ("creating "+$TABLESPATH+"dbo.CardiacOutputCathCtxMeas.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLESPATH+"dbo.CardiacOutputCathCtxMeas.sql")
#--
Write-Host ("creating "+$TABLESPATH+"dbo.PressureSampleCathCtxMeas.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLESPATH+"dbo.PressureSampleCathCtxMeas.sql")
#--
Write-Host ("creating "+$TABLESPATH+"dbo.Procedure.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLESPATH+"dbo.Procedure.sql")
#--
Write-Host ("creating "+$TABLESPATH+"dbo.ProcedureStent.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLESPATH+"dbo.ProcedureStent.sql")
#--
Write-Host ("creating "+$TABLESPATH+"dbo.ProcedureStentGraft.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLESPATH+"dbo.ProcedureStentGraft.sql")
#--
Write-Host ("creating "+$TABLESPATH+"dbo.ProcedureAtherectomy.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLESPATH+"dbo.ProcedureAtherectomy.sql")
#--
Write-Host ("creating "+$TABLESPATH+"dbo.ProcedureAngioplasty.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLESPATH+"dbo.ProcedureAngioplasty.sql")
#--
Write-Host ("creating "+$TABLESPATH+"dbo.ProcedurePathologyObservation.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLESPATH+"dbo.ProcedurePathologyObservation.sql")
#--
Write-Host ("creating "+$TABLESPATH+"dbo.CaseProcedure.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLESPATH+"dbo.CaseProcedure.sql")
#--
Write-Host ("creating "+$TABLESPATH+"dbo.ProcedureThrombectomy.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLESPATH+"dbo.ProcedureThrombectomy.sql")
#--
Write-Host ("creating "+$TABLESPATH+"dbo.ProcedureThrombolysis.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLESPATH+"dbo.ProcedureThrombolysis.sql")
#--
Write-Host ("creating "+$TABLESPATH+"dbo.ProcedureRightHeartCath.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLESPATH+"dbo.ProcedureRightHeartCath.sql")
#--
Write-Host ("creating "+$TABLESPATH+"dbo.ProcedurePercutaneousLVAD.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLESPATH+"dbo.ProcedurePercutaneousLVAD.sql")
#--
Write-Host ("creating "+$TABLESPATH+"dbo.ProcedurePercutaneousRVAD.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLESPATH+"dbo.ProcedurePercutaneousRVAD.sql")
#--
Write-Host ("creating "+$TABLESPATH+"dbo.ProcedureMitralValveRepair.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLESPATH+"dbo.ProcedureMitralValveRepair.sql")
#--
Write-Host ("creating "+$TABLESPATH+"dbo.ProcedureMitralValveReplacement.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLESPATH+"dbo.ProcedureMitralValveReplacement.sql")
#--
Write-Host ("creating "+$TABLESPATH+"dbo.ProcedureParavalvularLeakRepair.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLESPATH+"dbo.ProcedureParavalvularLeakRepair.sql")
#--
Write-Host ("creating "+$TABLESPATH+"dbo.ProcedureTAVR.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLESPATH+"dbo.ProcedureTAVR.sql")
#--
Write-Host ("creating "+$TABLESPATH+"dbo.ProcedureCoolingDevice.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLESPATH+"dbo.ProcedureCoolingDevice.sql")
#--
Write-Host ("creating "+$TABLESPATH+"dbo.ProcedureLeftHeartCath.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLESPATH+"dbo.ProcedureLeftHeartCath.sql")
#--
Write-Host ("creating "+$TABLESPATH+"dbo.ProcedureIVUS.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLESPATH+"dbo.ProcedureIVUS.sql")
#--
Write-Host ("creating "+$TABLESPATH+"dbo.ProcedureOCT.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLESPATH+"dbo.ProcedureOCT.sql")
#--
Write-Host ("creating "+$TABLESPATH+"dbo.ProcedureICE.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLESPATH+"dbo.ProcedureICE.sql")
#--
Write-Host ("creating "+$TABLESPATH+"dbo.ProcedureFFR.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLESPATH+"dbo.ProcedureFFR.sql")
#--
Write-Host ("creating "+$TABLESPATH+"dbo.ProcedureIABP.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLESPATH+"dbo.ProcedureIABP.sql")
#--
Write-Host ("creating "+$TABLESPATH+"dbo.ProcedureCoolingCatheterPlacement.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLESPATH+"dbo.ProcedureCoolingCatheterPlacement.sql")
#--
Write-Host ("creating "+$TABLESPATH+"dbo.ProcedureEmbolization.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLESPATH+"dbo.ProcedureEmbolization.sql")
#--
Write-Host ("creating "+$TABLESPATH+"dbo.ProcedurePriorDiagnostic.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLESPATH+"dbo.ProcedurePriorDiagnostic.sql")
#--
Write-Host ("creating "+$TABLESPATH+"dbo.ProcedureAngiogram.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLESPATH+"dbo.ProcedureAngiogram.sql")
#--
Write-Host ("creating "+$TABLESPATH+"dbo.ProcedureVenogram.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLESPATH+"dbo.ProcedureVenogram.sql")
#--
Write-Host ("creating "+$TABLESPATH+"dbo.ProcedureLeftVentriculography.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLESPATH+"dbo.ProcedureLeftVentriculography.sql")
#--
Write-Host ("creating "+$TABLESPATH+"dbo.ProcedureRightVentriculography.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLESPATH+"dbo.ProcedureRightVentriculography.sql")
#--
Write-Host ("creating "+$TABLESPATH+"dbo.ProcedureLeftAtrialAngiogram.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLESPATH+"dbo.ProcedureLeftAtrialAngiogram.sql")
#--
Write-Host ("creating "+$TABLESPATH+"dbo.ProcedureRightAtrialAngiogram.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLESPATH+"dbo.ProcedureRightAtrialAngiogram.sql")
#--
Write-Host ("creating "+$TABLESPATH+"dbo.ProcedureAccessSite.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLESPATH+"dbo.ProcedureAccessSite.sql")
#--
Write-Host ("creating "+$TABLESPATH+"dbo.ProcedurePericardiocentesis.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLESPATH+"dbo.ProcedurePericardiocentesis.sql")
#--
Write-Host ("creating "+$TABLESPATH+"dbo.ProcedureSwanGanzCatheterPlacement.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLESPATH+"dbo.ProcedureSwanGanzCatheterPlacement.sql")
#--
Write-Host ("creating "+$TABLESPATH+"dbo.ProcedureTemporaryPacemaker.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLESPATH+"dbo.ProcedureTemporaryPacemaker.sql")
#--
Write-Host ("creating "+$TABLESPATH+"dbo.ProcedureEndomyocardialBiopsy.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLESPATH+"dbo.ProcedureEndomyocardialBiopsy.sql")
#--
Write-Host ("creating "+$TABLESPATH+"dbo.CaseDevice.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLESPATH+"dbo.CaseDevice.sql")
#--
Write-Host ("creating "+$TABLESPATH+"dbo.DeviceUsageProperty.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLESPATH+"dbo.DeviceUsageProperty.sql")
#--
Write-Host ("creating "+$TABLESPATH+"dbo.ProcedureDeviceRecord.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLESPATH+"dbo.ProcedureDeviceRecord.sql")
#--
Write-Host ("creating "+$TABLESPATH+"dbo.ProcedureDeviceRecordProperty.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLESPATH+"dbo.ProcedureDeviceRecordProperty.sql")
#--
Write-Host ("creating "+$TABLESPATH+"dbo.ProcedureLeftAtrialAppendageClosure.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLESPATH+"dbo.ProcedureLeftAtrialAppendageClosure.sql")
#--
Write-Host ("creating "+$TABLESPATH+"dbo.MedicalRecord.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLESPATH+"dbo.MedicalRecord.sql")
#--
Write-Host ("creating "+$TABLESPATH+"dbo.ContactInfo.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLESPATH+"dbo.ContactInfo.sql")
#--
Write-Host ("creating "+$TABLESPATH+"dbo.Organization.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLESPATH+"dbo.Organization.sql")
#--
Write-Host ("creating "+$TABLESPATH+"dbo.OrganizationContactInfo.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLESPATH+"dbo.OrganizationContactInfo.sql")
#--
Write-Host ("creating "+$TABLESPATH+"dbo.MedicalRecordContactInfo.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLESPATH+"dbo.MedicalRecordContactInfo.sql")
#--
Write-Host ("creating "+$TABLESPATH+"dbo.Order.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLESPATH+"dbo.Order.sql")
#--
Write-Host ("creating "+$TABLESPATH+"dbo.ObservationRequest.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLESPATH+"dbo.ObservationRequest.sql")
#--
Write-Host ("creating "+$TABLESPATH+"dbo.Note.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLESPATH+"dbo.Note.sql")
#--
Write-Host ("creating "+$TABLESPATH+"dbo.PatientVisit.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLESPATH+"dbo.PatientVisit.sql")
#--
Write-Host ("creating "+$TABLESPATH+"dbo.Person.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLESPATH+"dbo.Person.sql")
#--
Write-Host ("creating "+$TABLESPATH+"dbo.PersonContactInfo.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLESPATH+"dbo.PersonContactInfo.sql")
#--
Write-Host ("creating "+$TABLESPATH+"dbo.PersonOrganization.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLESPATH+"dbo.PersonOrganization.sql")
#--
Write-Host ("creating "+$TABLESPATH+"dbo.PatientRelation.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLESPATH+"dbo.PatientRelation.sql")
#--
Write-Host ("creating "+$TABLESPATH+"dbo.BillableItem.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLESPATH+"dbo.BillableItem.sql")
#--
Write-Host ("creating "+$TABLESPATH+"dbo.GroupStudyType.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLESPATH+"dbo.GroupStudyType.sql")
#--
Write-Host ("creating "+$TABLESPATH+"dbo.VesselHotspotMap.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLESPATH+"dbo.VesselHotspotMap.sql")
#--
Write-Host ("creating "+$TABLESPATH+"dbo.MedicalCode.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLESPATH+"dbo.MedicalCode.sql")
#--
Write-Host ("creating "+$TABLESPATH+"dbo.MedicalPersonnel.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLESPATH+"dbo.MedicalPersonnel.sql")
#--
Write-Host ("creating "+$TABLESPATH+"dbo.Strategy.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLESPATH+"dbo.Strategy.sql")
#--
Write-Host ("creating "+$TABLESPATH+"dbo.Medication.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLESPATH+"dbo.Medication.sql")
#--
Write-Host ("creating "+$TABLESPATH+"dbo.LabData.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLESPATH+"dbo.LabData.sql")
#--
Write-Host ("creating "+$TABLESPATH+"dbo.ContrastTotal.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLESPATH+"dbo.ContrastTotal.sql")
#--
Write-Host ("creating "+$TABLESPATH+"dbo.Recommendation.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLESPATH+"dbo.Recommendation.sql")
#--
Write-Host ("creating "+$TABLESPATH+"dbo.AdverseEvent.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLESPATH+"dbo.AdverseEvent.sql")
#--
Write-Host ("creating "+$TABLESPATH+"dbo.Graft.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLESPATH+"dbo.Graft.sql")
#--
Write-Host ("creating "+$TABLESPATH+"dbo.CaseGraft.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLESPATH+"dbo.CaseGraft.sql")
#--
Write-Host ("creating "+$TABLESPATH+"dbo.ActionHandler.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLESPATH+"dbo.ActionHandler.sql")
#--
Write-Host ("creating "+$TABLESPATH+"dbo.CaseOutputHistory.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLESPATH+"dbo.CaseOutputHistory.sql")
#--
Write-Host ("creating "+$TABLESPATH+"dbo.ComplianceFlag.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLESPATH+"dbo.ComplianceFlag.sql")
#--
Write-Host ("creating "+$TABLESPATH+"dbo.Addendum.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLESPATH+"dbo.Addendum.sql")
#--
Write-Host ("creating "+$TABLESPATH+"dbo.ProcedureSeptalAblation.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLESPATH+"dbo.ProcedureSeptalAblation.sql")
#--
Write-Host ("creating "+$TABLESPATH+"dbo.HIPAALog.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLESPATH+"dbo.HIPAALog.sql")
#--
Write-Host ("creating "+$TABLESPATH+"dbo.UserProperty.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLESPATH+"dbo.UserProperty.sql")

#--End dbo schema ---
#----------------------------------------------------------


#--Begin stgmerge schema ---
Write-Host ("creating "+$TABLESPATHSTAGEMERGE+"stgmerge.Message.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLESPATHSTAGEMERGE+"stgmerge.Message.sql")
#--
Write-Host ("creating "+$TABLESPATHSTAGEMERGE+"stgmerge.StageStateType.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLESPATHSTAGEMERGE+"stgmerge.StageStateType.sql")
#--
Write-Host ("creating "+$TABLESPATHSTAGEMERGE+"stgmerge.Case.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLESPATHSTAGEMERGE+"stgmerge.Case.sql")
#--
Write-Host ("creating "+$TABLESPATHSTAGEMERGE+"stgmerge.Device.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLESPATHSTAGEMERGE+"stgmerge.Device.sql")
#--
Write-Host ("creating "+$TABLESPATHSTAGEMERGE+"stgmerge.CatheterContext.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLESPATHSTAGEMERGE+"stgmerge.CatheterContext.sql")
#--
Write-Host ("creating "+$TABLESPATHSTAGEMERGE+"stgmerge.Medication.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLESPATHSTAGEMERGE+"stgmerge.Medication.sql")
#--
Write-Host ("creating "+$TABLESPATHSTAGEMERGE+"stgmerge.ContrastTotal.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLESPATHSTAGEMERGE+"stgmerge.ContrastTotal.sql")
#--
Write-Host ("creating "+$TABLESPATHSTAGEMERGE+"stgmerge.LabData.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLESPATHSTAGEMERGE+"stgmerge.LabData.sql")
#--
Write-Host ("creating "+$TABLESPATHSTAGEMERGE+"stgmerge.PressureSample.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLESPATHSTAGEMERGE+"stgmerge.PressureSample.sql")
#--
Write-Host ("creating "+$TABLESPATHSTAGEMERGE+"stgmerge.CardiacOutput.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLESPATHSTAGEMERGE+"stgmerge.CardiacOutput.sql")
#--
Write-Host ("creating "+$TABLESPATHSTAGEMERGE+"stgmerge.O2Saturation.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLESPATHSTAGEMERGE+"stgmerge.O2Saturation.sql")
#--
Write-Host ("creating "+$TABLESPATHSTAGEMERGE+"stgmerge.CatheterResistance.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLESPATHSTAGEMERGE+"stgmerge.CatheterResistance.sql")
#--
Write-Host ("creating "+$TABLESPATHSTAGEMERGE+"stgmerge.CathCtxMeasurement.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLESPATHSTAGEMERGE+"stgmerge.CathCtxMeasurement.sql")
#--
Write-Host ("creating "+$TABLESPATHSTAGEMERGE+"stgmerge.PressureSampleCathCtxMeas.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLESPATHSTAGEMERGE+"stgmerge.PressureSampleCathCtxMeas.sql")
#--
Write-Host ("creating "+$TABLESPATHSTAGEMERGE+"stgmerge.CardiacOutputCathCtxMeas.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLESPATHSTAGEMERGE+"stgmerge.CardiacOutputCathCtxMeas.sql")
#--
Write-Host ("creating "+$TABLESPATHSTAGEMERGE+"stgmerge.CatheterResistanceCathCtxMeas.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLESPATHSTAGEMERGE+"stgmerge.CatheterResistanceCathCtxMeas.sql")
#--
Write-Host ("creating "+$TABLESPATHSTAGEMERGE+"stgmerge.CaseProperty.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLESPATHSTAGEMERGE+"stgmerge.CaseProperty.sql")
#--
#--End stgmerge schema ---

#--Begin stgge schema ---
Write-Host ("creating "+$TABLESPATHSTAGEGE+"stgge.Message.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLESPATHSTAGEGE+"stgge.Message.sql")
#--
Write-Host ("creating "+$TABLESPATHSTAGEGE+"stgge.StageStateType.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLESPATHSTAGEGE+"stgge.StageStateType.sql")
#--
Write-Host ("creating "+$TABLESPATHSTAGEGE+"stgge.Case.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLESPATHSTAGEGE+"stgge.Case.sql")
#--
#--End stgge schema ---

#--Begin archive schema ---
Write-Host ("creating "+$TABLESPATHARCHIVE+"archive.Log.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLESPATHARCHIVE+"archive.Log.sql")
#--
Write-Host ("creating "+$TABLESPATHARCHIVE+"archive.Hl7Msg.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLESPATHARCHIVE+"archive.Hl7Msg.sql")
#--
Write-Host ("creating "+$TABLESPATHARCHIVE+"archive.Hl7Ack.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLESPATHARCHIVE+"archive.Hl7Ack.sql")
#--
Write-Host ("creating "+$TABLESPATHARCHIVE+"archive.Hl7MSHSegment.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLESPATHARCHIVE+"archive.Hl7MSHSegment.sql")
#--
Write-Host ("creating "+$TABLESPATHARCHIVE+"archive.Hl7EVNSegment.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLESPATHARCHIVE+"archive.Hl7EVNSegment.sql")
#--
#--End archive schema ---


#----------------------------------------------------------
#--Create Database functions
#----------------------------------------------------------
#Write-Host ("creating "+$FUNCSPATH+"dbo.fnAllPatientFindings.sql")
#Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($FUNCSPATH+"dbo.fnAllPatientFindings.sql")
#----------------------------------------------------------

#----------------------------------------------------------
#--Create Database views
#----------------------------------------------------------
Write-Host ("creating "+$VIEWSPATH+"dbo.vwExportCaseORMMessages.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($VIEWSPATH+"dbo.vwExportCaseORMMessages.sql")
#--
Write-Host ("creating "+$VIEWSPATH+"dbo.vwExportCaseADTMessages.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($VIEWSPATH+"dbo.vwExportCaseADTMessages.sql")
#--
Write-Host ("creating "+$VIEWSPATHSTAGEHL7+"stghl7.vwHCA_MasterLookup.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($VIEWSPATHSTAGEHL7+"stghl7.vwHCA_MasterLookup.sql")
#--
Write-Host ("creating "+$VIEWSPATH+"dbo.vwPatientMedicalRecord.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($VIEWSPATH+"dbo.vwPatientMedicalRecord.sql")
#--
Write-Host ("creating "+$VIEWSPATH+"dbo.vwPatientMedicalRecordRelation.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($VIEWSPATH+"dbo.vwPatientMedicalRecordRelation.sql")
#--
Write-Host ("creating "+$VIEWSPATH+"dbo.vwPatientMedicalRecordVisit.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($VIEWSPATH+"dbo.vwPatientMedicalRecordVisit.sql")
#--
Write-Host ("creating "+$VIEWSPATH+"dbo.vwPatientMedicalRecordOrder.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($VIEWSPATH+"dbo.vwPatientMedicalRecordOrder.sql")
#--
Write-Host ("creating "+$VIEWSPATHARCHIVE+"archive.vwGetLogAll.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($VIEWSPATHARCHIVE+"archive.vwGetLogAll.sql")
#--
Write-Host ("creating "+$VIEWPATHINV+"inv.vwGetDevicesNotInDeviceMaster.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($VIEWPATHINV+"inv.vwGetDevicesNotInDeviceMaster.sql")
#--

#----------------------------------------------------------

#----------------------------------------------------------
#--Create Database table types
#----------------------------------------------------------
#Write-Host ("creating "+$TBLTYPESPATH+"dbo.IDList.sql")
#Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TBLTYPESPATH+"dbo.IDList.sql")
#----------------------------------------------------------

#----------------------------------------------------------
#--Create Database stored procedures - dbo
#----------------------------------------------------------
Write-Host ("creating "+$PROCSPATH+"dbo.procAddLog.sql ")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($PROCSPATH+"dbo.procAddLog.sql ")
#--
Write-Host ("creating "+$PROCSPATH+"dbo.procAddSystemVersionHistory.sql ")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($PROCSPATH+"dbo.procAddSystemVersionHistory.sql ")
#--
Write-Host ("creating "+$PROCSPATH+"dbo.procGetLatestPathologyObservationPropVal.sql ")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($PROCSPATH+"dbo.procGetLatestPathologyObservationPropVal.sql ")
#--
Write-Host ("creating "+$PROCSPATH+"dbo.procGetProcedures.sql ")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($PROCSPATH+"dbo.procGetProcedures.sql ")
#--
Write-Host ("creating "+$PROCSPATH+"dbo.procGetPathologies.sql ")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($PROCSPATH+"dbo.procGetPathologies.sql ")
#--
Write-Host ("creating "+$PROCSPATH+"dbo.procGetProcedureDeviceRecords.sql ")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($PROCSPATH+"dbo.procGetProcedureDeviceRecords.sql ")
#--
Write-Host ("creating "+$PROCSPATH+"dbo.procGetDeepCatheterContexts.sql ")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($PROCSPATH+"dbo.procGetDeepCatheterContexts.sql ")
#--
Write-Host ("creating "+$PROCSPATHSTAGE+"stg.procVersionAndStageVesselHotspot.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($PROCSPATHSTAGE+"stg.procVersionAndStageVesselHotspot.sql")
#--
Write-Host ("creating "+$PROCSPATHSTAGE+"stg.procVersionAndStageMedicalCode.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($PROCSPATHSTAGE+"stg.procVersionAndStageMedicalCode.sql")
#--
Write-Host ("creating "+$PROCSPATHSTAGE+"stg.procVersionAndStageStudyType.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($PROCSPATHSTAGE+"stg.procVersionAndStageStudyType.sql")
#--
Write-Host ("creating "+$PROCSPATHSTAGE+"stg.procVersionAndStageDeviceCategory.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($PROCSPATHSTAGE+"stg.procVersionAndStageDeviceCategory.sql")
#--
Write-Host ("creating "+$PROCSPATHSTAGE+"stg.procVersionAndStageDeviceMaster.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($PROCSPATHSTAGE+"stg.procVersionAndStageDeviceMaster.sql")
#--
Write-Host ("creating "+$PROCSPATHSTAGE+"stg.procVersionAndStageDeviceType.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($PROCSPATHSTAGE+"stg.procVersionAndStageDeviceType.sql")
#--
Write-Host ("creating "+$PROCSPATHSTAGE+"stg.procVersionAndStageGroup.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($PROCSPATHSTAGE+"stg.procVersionAndStageGroup.sql")
#--
Write-Host ("creating "+$PROCSPATHSTAGE+"stg.procVersionAndStageGroupStudyType.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($PROCSPATHSTAGE+"stg.procVersionAndStageGroupStudyType.sql")
#--
#----------------------------------------------------------

#----------------------------------------------------------
#--Create Database stored procedures - stgmerge
#----------------------------------------------------------
Write-Host ("creating "+$PROCSPATHSTAGEMERGE+"stgmerge.procPublishStageCase.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($PROCSPATHSTAGEMERGE+"stgmerge.procPublishStageCase.sql")
#--
Write-Host ("creating "+$PROCSPATHSTAGEMERGE+"stgmerge.procPublishStageDevice.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($PROCSPATHSTAGEMERGE+"stgmerge.procPublishStageDevice.sql")
#--
Write-Host ("creating "+$PROCSPATHSTAGEMERGE+"stgmerge.procPublishStageCatheterContext.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($PROCSPATHSTAGEMERGE+"stgmerge.procPublishStageCatheterContext.sql")
#--
Write-Host ("creating "+$PROCSPATHSTAGEMERGE+"stgmerge.procPublishStageMedication.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($PROCSPATHSTAGEMERGE+"stgmerge.procPublishStageMedication.sql")
#--
Write-Host ("creating "+$PROCSPATHSTAGEMERGE+"stgmerge.procPublishStageContrastTotal.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($PROCSPATHSTAGEMERGE+"stgmerge.procPublishStageContrastTotal.sql")
#--
Write-Host ("creating "+$PROCSPATHSTAGEMERGE+"stgmerge.procPublishStageLabData.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($PROCSPATHSTAGEMERGE+"stgmerge.procPublishStageLabData.sql")
#--
Write-Host ("creating "+$PROCSPATHSTAGEMERGE+"stgmerge.procPublishStagePressureSample.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($PROCSPATHSTAGEMERGE+"stgmerge.procPublishStagePressureSample.sql")
#--
Write-Host ("creating "+$PROCSPATHSTAGEMERGE+"stgmerge.procPublishStageCatheterResistance.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($PROCSPATHSTAGEMERGE+"stgmerge.procPublishStageCatheterResistance.sql")
#--
Write-Host ("creating "+$PROCSPATHSTAGEMERGE+"stgmerge.procPublishStageCardiacOutput.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($PROCSPATHSTAGEMERGE+"stgmerge.procPublishStageCardiacOutput.sql")
#--
Write-Host ("creating "+$PROCSPATHSTAGEMERGE+"stgmerge.procPublishStageO2Saturation.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($PROCSPATHSTAGEMERGE+"stgmerge.procPublishStageO2Saturation.sql")
#--
Write-Host ("creating "+$PROCSPATHSTAGEMERGE+"stgmerge.procPublishStageCaseProperty.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($PROCSPATHSTAGEMERGE+"stgmerge.procPublishStageCaseProperty.sql")
#--
#----------------------------------------------------------

#----------------------------------------------------------
#--Create Database stored procedures - stgge
#----------------------------------------------------------
Write-Host ("creating "+$PROCSPATHSTAGEGE+"stgge.procPublishStageCase.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($PROCSPATHSTAGEGE+"stgge.procPublishStageCase.sql")
#--
#----------------------------------------------------------

#----------------------------------------------------------
#--Create Database stored procedures - inv
#----------------------------------------------------------
Write-Host ("creating "+$PROCSPATHINVENTORY+"inv.procGetDeviceMasterRecord.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($PROCSPATHINVENTORY+"inv.procGetDeviceMasterRecord.sql")
#--
Write-Host ("creating "+$PROCSPATHINVENTORY+"inv.procPublishDeviceMaster.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($PROCSPATHINVENTORY+"inv.procPublishDeviceMaster.sql")
#--
#----------------------------------------------------------
#--Create Database stored procedures - archive
#----------------------------------------------------------
Write-Host ("creating "+$PROCSPATHARCHIVE+"archive.procArchiveLog.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($PROCSPATHARCHIVE+"archive.procArchiveLog.sql")
#--
Write-Host ("creating "+$PROCSPATHARCHIVE+"archive.procArchiveHl7MsgTables.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($PROCSPATHARCHIVE+"archive.procArchiveHl7MsgTables.sql")
#--

#----------------------------------------------------------
#--Load Database Table Data
#----------------------------------------------------------
Write-Host ("loading data from "+$TABLEDATAPATH+"dbo.SystemVersionHistory.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLEDATAPATH+"dbo.SystemVersionHistory.sql")
#--
Write-Host ("loading data from "+$TABLEDATAPATH+"dbo.EnlargementSizeType.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLEDATAPATH+"dbo.EnlargementSizeType.sql")
#--
Write-Host ("loading data from "+$TABLEDATAPATH+"dbo.AppearanceType.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLEDATAPATH+"dbo.AppearanceType.sql")
#--
Write-Host ("loading data from "+$TABLEDATAPATH+"dbo.BillableItemType.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLEDATAPATH+"dbo.BillableItemType.sql")
#--
Write-Host ("loading data from "+$TABLEDATAPATH+"dbo.MedicalCodeType.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLEDATAPATH+"dbo.MedicalCodeType.sql")
#--
Write-Host ("loading data from "+$TABLEDATAPATH+"dbo.MedicalPersonnelType.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLEDATAPATH+"dbo.MedicalPersonnelType.sql")
#--
Write-Host ("loading data from "+$TABLEDATAPATH+"dbo.CardiacOutputType.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLEDATAPATH+"dbo.CardiacOutputType.sql")
#--
Write-Host ("loading data from "+$TABLEDATAPATH+"dbo.ContactInfoType.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLEDATAPATH+"dbo.ContactInfoType.sql")
#--
Write-Host ("loading data from "+$TABLEDATAPATH+"dbo.SeverityType.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLEDATAPATH+"dbo.SeverityType.sql")
#--
Write-Host ("loading data from "+$TABLEDATAPATH+"dbo.SystemComponent.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLEDATAPATH+"dbo.SystemComponent.sql")
#--
Write-Host ("loading data from "+$TABLEDATAPATH+"dbo.PathologyCategoryType.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLEDATAPATH+"dbo.PathologyCategoryType.sql")
#--
Write-Host ("loading data from "+$TABLEDATAPATH+"dbo.PathologyType.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLEDATAPATH+"dbo.PathologyType.sql")
#--
Write-Host ("loading data from "+$TABLEDATAPATH+"dbo.ProcedureType.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLEDATAPATH+"dbo.ProcedureType.sql")
#--
Write-Host ("loading data from "+$TABLEDATAPATH+"dbo.GenderMap.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLEDATAPATH+"dbo.GenderMap.sql")
#--
Write-Host ("loading data from "+$TABLEDATAPATH+"dbo.GenderType.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLEDATAPATH+"dbo.GenderType.sql")
#--
Write-Host ("loading data from "+$TABLEDATAPATH+"dbo.CaseStatusType.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLEDATAPATH+"dbo.CaseStatusType.sql")
#--
Write-Host ("loading data from "+$TABLEDATAPATH+"dbo.PropertyValueType.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLEDATAPATH+"dbo.PropertyValueType.sql")
#--
Write-Host ("loading data from "+$TABLEDATAPATH+"dbo.AngiogramType.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLEDATAPATH+"dbo.AngiogramType.sql")
#--
Write-Host ("loading data from "+$TABLEDATAPATH+"dbo.DispositionType.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLEDATAPATH+"dbo.DispositionType.sql")
#--
Write-Host ("loading data from "+$TABLEDATAPATH+"dbo.ApproachType.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLEDATAPATH+"dbo.ApproachType.sql")
#--
Write-Host ("loading data from "+$TABLEDATAPATH+"dbo.CatheterContextType.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLEDATAPATH+"dbo.CatheterContextType.sql")
#--
Write-Host ("loading data from "+$TABLEDATAPATH+"dbo.StentType.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLEDATAPATH+"dbo.StentType.sql")
#-
Write-Host ("loading data from "+$TABLEDATAPATH+"dbo.RecommendationType.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLEDATAPATH+"dbo.RecommendationType.sql")
#-
Write-Host ("loading data from "+$TABLEDATAPATH+"dbo.MeasureSiteType.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLEDATAPATH+"dbo.MeasureSiteType.sql")
#--
Write-Host ("loading data from "+$TABLEDATAPATH+"dbo.PathologyProperty.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLEDATAPATH+"dbo.PathologyProperty.sql")
#--
Write-Host ("loading data from "+$TABLEDATAPATH+"dbo.DeviceUsageProperty.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLEDATAPATH+"dbo.DeviceUsageProperty.sql")
#--
Write-Host ("loading data from "+$TABLEDATAPATH+"dbo.Strategy.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLEDATAPATH+"dbo.Strategy.sql")
#--
Write-Host ("loading data from "+$TABLEDATAPATH+"dbo.Workflow.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLEDATAPATH+"dbo.Workflow.sql")
#--
Write-Host ("loading data from "+$TABLEDATAPATH+"dbo.WorkflowStateMachine.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLEDATAPATH+"dbo.WorkflowStateMachine.sql")
#--
Write-Host ("loading data from "+$TABLEDATAPATH+"stgmerge.StageStateType.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLEDATAPATH+"stgmerge.StageStateType.sql")
#--
#TODO: StudyType bulk load

#-----------
#--load stgge schema data
#-----------
Write-Host ("loading data from "+$TABLEDATAPATH+"stgge.StageStateType.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLEDATAPATH+"stgge.StageStateType.sql")
#--

#-----------
# load inv schema data 
#-----------
Write-Host ("loading data from "+$TABLEDATAPATH+"inv.ItemType.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLEDATAPATH+"inv.ItemType.sql")
#--
Write-Host ("bulk loading csv filedata from "+$BULKIMPORTROOT+"Scripts\Data\raw-data\data-manager-minified\Min_MedicalCode.csv")
$dvMgr.ImportCSV("medicalCode", $BULKIMPORTROOT+"Scripts\Data\raw-data\data-manager-minified\Min_MedicalCode.csv", $BULKIMPORTUNCMINIFIEDPATH )
#--
Write-Host ("loading data to "+$TABLESPATH+"dbo.MedicalCode.sql")
$validations = $dvMgr.PublishEntity("medicalCode")
if($validations.MedicalCodesValid -eq $FALSE) { throw ("MedicalCode data failed validations: "  + $validations.Messages) }
#--
Write-Host ("bulk loading csv filedata from "+$BULKIMPORTROOT+"Scripts\Data\raw-data\data-manager-minified\Min_StudyType.csv")
$dvMgr.ImportCSV("studyType", $BULKIMPORTROOT+"Scripts\Data\raw-data\data-manager-minified\Min_StudyType.csv", $BULKIMPORTUNCMINIFIEDPATH )
#--
Write-Host ("loading data to "+$TABLESPATH+"dbo.StudyType.sql")
$validations = $dvMgr.PublishEntity("studyType")
if($validations.StudyTypesValid -eq $FALSE) { throw ("StudyType data failed validations: "  + $validations.Messages) }
#--
Write-Host ("bulk loading csv filedata from "+$BULKIMPORTROOT+"Scripts\Data\raw-data\data-manager-minified\Min_DeviceCategory.csv")
$dvMgr.ImportCSV("deviceCategory", $BULKIMPORTROOT+"Scripts\Data\raw-data\data-manager-minified\Min_DeviceCategory.csv", $BULKIMPORTUNCMINIFIEDPATH )
#--
Write-Host ("loading data to "+$TABLESPATH+"inv.DeviceCategory.sql")
$validations = $dvMgr.PublishEntity("deviceCategory")
if($validations.DeviceCategoriesValid -eq $FALSE) { throw ("DeviceCategory data failed validations: "  + $validations.Messages) }
#--
Write-Host ("bulk loading csv filedata from "+$BULKIMPORTROOT+"Scripts\Data\raw-data\data-manager-minified\Min_DeviceType.csv")
$dvMgr.ImportCSV("deviceType", $BULKIMPORTROOT+"Scripts\Data\raw-data\data-manager-minified\Min_DeviceType.csv", $BULKIMPORTUNCMINIFIEDPATH )
#--
Write-Host ("loading data to "+$TABLESPATH+"inv.DeviceType.sql")
$validations = $dvMgr.PublishEntity("deviceType")
if($validations.DeviceTypesValid -eq $FALSE) { throw ("DeviceType data failed validations: "  + $validations.Messages) }
#--
Write-Host ("bulk loading csv filedata from "+$BULKIMPORTROOT+"Scripts\Data\raw-data\data-manager-minified\Min_DeviceMaster.csv")
$dvMgr.ImportCSV("deviceMaster", $BULKIMPORTROOT+"Scripts\Data\raw-data\data-manager-minified\Min_DeviceMaster.csv", $BULKIMPORTUNCMINIFIEDPATH )
#--
Write-Host ("loading data to "+$TABLESPATH+"inv.DeviceMaster.sql")
$validations = $dvMgr.PublishEntity("deviceMaster")
if($validations.DeviceMasterValid -eq $FALSE) { throw ("DeviceMaster data failed validations: "  + $validations.Messages) }
#--
$BILLABLEITEMFI = New-Object IO.FileInfo($BULKIMPORTROOT+"Scripts\Data\raw-data\HCA_COCBAU_TESTONLY_BillableItem.csv")
Write-Host ("loading csv test only file data from "+$BULKIMPORTROOT+"Scripts\Data\raw-data\HCA_COCBAU_TESTONLY_BillableItem.csv")
$ccMgr.ImportAndPublishLocalCSV($BILLABLEITEMFI)
#--
Write-Host ("bulk loading csv filedata from "+$BULKIMPORTROOT+"Scripts\Data\raw-data\data-manager-minified\Min_Group.csv")
$dvMgr.ImportCSV("group", $BULKIMPORTROOT+"Scripts\Data\raw-data\data-manager-minified\Min_Group.csv", $BULKIMPORTUNCMINIFIEDPATH )
#--
Write-Host ("loading data to "+$TABLESPATH+"dbo.Group.sql")
$validations = $dvMgr.PublishEntity("group")
if($validations.GroupsValid -eq $FALSE) { throw ("Group data failed validations: "  + $validations.Messages) }
#--
Write-Host ("bulk loading csv filedata from "+$BULKIMPORTROOT+"Scripts\Data\raw-data\data-manager-minified\Min_GroupStudyType.csv")
$dvMgr.ImportCSV("groupStudyType", $BULKIMPORTROOT+"Scripts\Data\raw-data\data-manager-minified\Min_GroupStudyType.csv", $BULKIMPORTUNCMINIFIEDPATH )
#--
Write-Host ("loading data to "+$TABLESPATH+"dbo.GroupStudyType.sql")
$validations = $dvMgr.PublishEntity("groupStudyType")
if($validations.GroupStudyTypesValid -eq $FALSE) { throw ("GroupStudyType data failed validations: "  + $validations.Messages) }
#--
Write-Host ("bulk loading csv filedata from "+$BULKIMPORTROOT+"Scripts\Data\raw-data\data-manager-minified\Min_VesselHotspotMap.csv")
$dvMgr.ImportCSV("vesselHotspot", $BULKIMPORTROOT+"Scripts\Data\raw-data\data-manager-minified\Min_VesselHotspotMap.csv", $BULKIMPORTUNCMINIFIEDPATH )
#--
Write-Host ("loading data to "+$TABLESPATH+"dbo.VesselHotspotMap.sql")
$validations = $dvMgr.PublishEntity("vesselHotspot")
if($validations.VesselHotspotMapsValid -eq $FALSE) { throw ("VesselHotspotMap data failed validations: "  + $validations.Messages) }
#--
Write-Host ("bulk loading csv filedata from "+$BULKIMPORTROOT+"Scripts\Data\raw-data\HCA_TransportationModeLookup.csv")
$dvMgr.ImportCSVDirect("stghl7","HCA_TransportationModeLookup", $BULKIMPORTROOT+"Scripts\Data\raw-data\HCA_TransportationModeLookup.csv", $BULKIMPORTUNCRAWDATAPATH )
#--
#Write-Host ("drop constraint for stghl7.HCA_BedPatientLocation")
#Invoke-Sqlcmd -ServerInstance $DB_SERVER -Query "ALTER TABLE [ZHEALTH].[stghl7].[HCA_BedPatientLocation] DROP CONSTRAINT [FK_HCA_BedPatientLocation_HCA_PatientLocationLookup] "
##--
Write-Host ("bulk loading csv filedata from "+$BULKIMPORTROOT+"Scripts\Data\raw-data\HCA_PatientLocationLookup.csv")
$dvMgr.ImportCSVDirect("stghl7","HCA_PatientLocationLookup", $BULKIMPORTROOT+"Scripts\Data\raw-data\HCA_PatientLocationLookup.csv", $BULKIMPORTUNCRAWDATAPATH )
#--
Write-Host ("loading data from "+$TABLEDATAPATH+"dbo.ActionHandler.sql")
Invoke-Sqlcmd -ServerInstance $DB_SERVER -Database $DB_NAME -InputFile ($TABLEDATAPATH+"dbo.ActionHandler.sql")
#--
Write-Host ("Saving logs in memory")
$logger.SaveLogsInMemory();
#--

#----------------------------------------------------------
#-- Initiate SchemaVersions Table
#----------------------------------------------------------
Write-Host ""
Write-Host "Attempting to Initiate SchemaVersions Table"
$dbMgr.InitiateSchemaVersions()
Write-Host ""

if($DEPLOYMENT_ENVIRONMENT -eq "LOCAL")
{
	#----------------------------------------------------------
	#--Load Case Scenarios
	#----------------------------------------------------------
	
	Write-Host("loading case scenarios from "+ $TABLEDATAPATH +"CaseScenario\")
	if(!$SILENTMODE)
	{
		Invoke-Expression ($POWERSHELLPATH +"CaseScenarioDeploy.ps1")
	}
	else
	{
		Invoke-Expression ($POWERSHELLPATH +"CaseScenarioDeploy.ps1 -s")
	}
}
#-------------------------------------
Write-Host "Successfully deployed database"

#----------------------------------------------------------
#--Dispose of UnitOfWork
#----------------------------------------------------------
Write-Host("")
Write-Host("Disposing UnitOfWork")
Write-Host("")
$uow.Dispose()

if($DEPLOYMENT_ENVIRONMENT -eq "LOCAL")
{
	#----------------------------------------------------------
	#--Create temp directories 
	#----------------------------------------------------------
	$TEMPPATHMERGE = $TEMPPATH+"Merge\COCBAU\"
	$TEMPMERGEDI = New-Object IO.DirectoryInfo($TEMPPATHMERGE)
	if(!$TEMPMERGEDI.Exists)
	{
		Write-Host("MERGE temp folder is missing. Creating temp folder "+$TEMPMERGEDI.FullName)
		Write-Host("")
		$TEMPMERGEDI.Create();
	}
}

#----------------------------------------------------------
#--Conclude and Exit Script
#----------------------------------------------------------

$endTime = Get-Date
Write-Host ("$DB_NAME database deploy script finished: " + $endTime + ", but may have errors. Inspect script output for any errors.")
$totalTime = $endTime - $startTime
Write-Host ("Total time to run script: " + $totalTime)
if(!$SILENTMODE)
{
	$choice2 = read-host -prompt "Hit the Enter key to exit."
}
