# Dot Source required Function Libraries
. "C:\Scripts\Functions\Logging_Functions.ps1"

function Get-TimeStamp {
  <#
  .SYNOPSIS
    Returns the current timestamp.
  #>   
  return "[{0:MM/dd/yy} {0:HH:mm:ss}]" -f (Get-Date)
}

function Backup-SqlDatabasesToS3 {
  <#
  .SYNOPSIS
      Runs a full database backup of all databases on the server and ships them
      to a AWS S3 bucket.
      
  .PARAMETER Database Server
      [String]. <Brief description of the parameter input required. Repeat this attribute if required.>

  #>

  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $false)]
    [String] $DatabaseServer = '.',

    [Parameter(Mandatory = $true)]
    [ValidateScript( {
      if (!(Test-Path $_ -Type Container)) {
        throw "$_ is not a directory!"
      } else {
        $true
      }
    })]
    [String] $LocalBackupPath,

    [Parameter(Mandatory = $true)]
    [String] $AWSProfileName,

    [Parameter(Mandatory = $true)]
    [String] $AWSS3Bucket,

    [Parameter(Mandatory = $false)]
    [String] $AWSRegion = 'us-east-1'
  )

  Begin  {
    # Log File Info
    $sLogPath = "C:\Windows\Temp"
    $sLogName = "sqlserver_backup_to_s3.log"
    $sLogFile = Join-Path -Path $sLogPath -ChildPath $sLogName

    Log-Write -LogPath $sLogFile -LineValue "$(Get-TimeStamp) Starting database backups"
  }

  Process {
    # Get a list of all non-system databases
    $databases = Invoke-Sqlcmd -ServerInstance $server -Query "SELECT [name]
    FROM master.dbo.sysdatabases
    WHERE dbid > 4 ;"

    # Iterate through each database
    foreach ($db in $databases)
    {
      # Set local variables
      $backupTimestamp = get-date -format yyyyMMddHHmmss
      $backupFileName = "$($db.name)-$backupTimestamp.bak"
      $backupFilePath = Join-Path $LocalBackupPath $backupFileName
      
      # Backup the database locally
      Log-Write -LogPath $sLogFile -LineValue "$(Get-TimeStamp) Starting backup of $($db.name)"
      
      try {
        Backup-SqlDatabase -ServerInstance $DatabaseServer -Database $db.name -BackupFile $backupFilePat
        Log-Write -LogPath $sLogFile -LineValue "$(Get-TimeStamp) Finished backup of $($db.name)"
      }
      catch {
        Log-Error -LogPath $sLogFile -LineValue "$(Get-TimeStamp) Backup of $($db.name) failed"
      }
      
      # Ship to S3
      Log-Write -LogPath $sLogFile -LineValue "$(Get-TimeStamp) Starting S3 ship of $($db.name)"
      
      try {
        aws s3 cp $backupFilePath $AWSS3Bucket --profile $AWSProfileName --region $AWSRegion
        Log-Write -LogPath $sLogFile -LineValue "$(Get-TimeStamp) Finished S3 ship of $($db.name)"
      }
      catch {
        Log-Error -LogPath $sLogFile -LineValue "$(Get-TimeStamp) S3 ship of $($db.name) failed"
      }
      
      # Delete the local backup
      Log-Write -LogPath $sLogFile -LineValue "$(Get-TimeStamp) Deleting local backup of $($db.name)"
      Remove-Item $backupFilePath
    }
  }

  End {
    If($?) {
      Log-Write -LogPath $sLogFile -LineValue "$(Get-TimeStamp) All database backups completed successfully"
      Log-write -LogPath $sLogFile -LineValue " "
    }
  }
}