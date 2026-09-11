# Config
$check_folder  = 
$backup_folder = 
$log_folder    = 
$foxit_path = "C:\Program Files\Foxit Software\Foxit PDF Reader\FoxitPDFReader.exe"

$print_server =
$printer = 
#$printer = 
$printer_path = 

$file_unlock_timeout = 300

function Write-Log {
    param(
        [Parameter(Mandatory)]
        [string]$Message
    )

    try {
        $time = Get-Date
        $date = $time.ToString("MM-dd-yyyy")
        $timestamp = $time.ToString("MM-dd-yyyy HH:mm:ss")
        $log_file = Join-Path $log_folder "$date.txt"

        Add-Content -LiteralPath $log_file -Value "$timestamp - $Message" -ErrorAction Stop
    }
    catch {
        Write-Host "LOGGING ERROR: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "Original message: $Message" -ForegroundColor Red
    }
}


function Wait-ForFileUnlock {
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [int]$TimeoutSeconds = 300
    )

    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    while ($stopwatch.Elapsed.TotalSeconds -lt $TimeoutSeconds) {

        if (!(Test-Path -LiteralPath $Path -PathType Leaf)) {
            return $false
        }

        $stream = $null

        try {
            if($Path.Length -eq 0){
                throw exception e
            }
            
            $stream = [System.IO.File]::Open(
                $Path,
                [System.IO.FileMode]::Open,
                [System.IO.FileAccess]::ReadWrite,
                [System.IO.FileShare]::None
            )

            $stream.Close()
            $stream.Dispose()

            return $true

        }catch {
            if ($stream) {
                $stream.Dispose()
            }

            Start-Sleep -Seconds 2
        }
    }

    return $false
}


function Print-Document {
    param(
        [Parameter(Mandatory)]
        [string]$FilePath
    )

    if (!(Test-Path -LiteralPath $FilePath -PathType Leaf)) {
        throw "PDF does not exist: $FilePath"
    }

    if (!(Test-Path -LiteralPath $foxit_path -PathType Leaf)) {
        throw "Foxit PDF Reader was not found: $foxit_path"
    }

    Write-Log "Sending to printer: $FilePath"

    $arguments = @(
        "/t",
        "`"$FilePath`"",
        "`"$printer_path`""
    )

    try {
        $process = Start-Process `
            -FilePath $foxit_path `
            -ArgumentList $arguments `
            -PassThru `
            -ErrorAction SilentlyContinue

        Write-Log "Print command started. PID: $($process.Id)"

        Start-Sleep -Seconds 5

        return $true

    }catch {
        Write-Log "ERROR starting print command: $($_.Exception.Message)"
        return $false
    }
}


function Process-CheckFile {
    param(
        [Parameter(Mandatory)]
        [string]$FilePath
    )

    $name = Split-Path -Path $FilePath -Leaf
    $backup_path = Join-Path $backup_folder $name

    Write-Log "Detected PDF: $FilePath"
    #Write-Log "Waiting for file to become available: $name"

    if (!(Wait-ForFileUnlock -Path $FilePath -TimeoutSeconds $file_unlock_timeout)) {
        Write-Log "ERROR: File remained locked or disappeared: $name"
        return $false
    }

    #Write-Log "File is available: $name"
    #Write-Log "Printing: $name"

    if (!(Print-Document -FilePath $FilePath)) {
        Write-Log "ERROR: Print command failed: $name"
        return $false
    }

    #Write-Log "Print command submitted successfully: $name"

    try {
        #Write-Log "Creating backup: $backup_path"

        Copy-Item `
            -LiteralPath $FilePath `
            -Destination $backup_path `
            -Force `
            -ErrorAction Stop

        Write-Log "Backup successful: $name"

    }catch {
        #Write-Log "ERROR: Backup copy failed for $name"
        Write-Log "ERROR: $($_.Exception.Message)"
        return $false
    }


    $delete_stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $deleted = $false

    #Write-Log "Waiting for print process to release file: $name"

    while ($delete_stopwatch.Elapsed.TotalSeconds -lt $file_unlock_timeout) {

        if (!(Test-Path -LiteralPath $FilePath -PathType Leaf)) {
            Write-Log "Original file no longer exists: $name"
            $deleted = $true
            break
        }

        try {
            Remove-Item `
                -LiteralPath $FilePath `
                -Force `
                -ErrorAction Stop

            #Write-Log "Original deleted successfully: $name"
            $deleted = $true
            break

        }catch {
            Start-Sleep -Seconds 2
        }
    }

    if (!$deleted) {
        Write-Log "ERROR: Could not delete original after $file_unlock_timeout seconds: $name"
        return $false
    }

    #Write-Log "Completed successfully: $name"

    return $true
}


Write-Log "=============================================="
Write-Log "Finance Check Printer started"
Write-Log "Check folder: $check_folder"
Write-Log "Backup folder: $backup_folder"
Write-Log "=============================================="


if (!(Test-Path -LiteralPath $check_folder -PathType Container)) {
    Write-Log "ERROR: Check folder does not exist: $check_folder"
    exit 1
}


if (!(Test-Path -LiteralPath $backup_folder -PathType Container)) {
    try {
        New-Item `
            -ItemType Directory `
            -Path $backup_folder `
            -Force `
            -ErrorAction Stop | Out-Null

        Write-Log "Created backup folder: $backup_folder"
    }
    catch {
        Write-Log "ERROR: Could not create backup folder"
        Write-Log "ERROR: $($_.Exception.Message)"
        exit 1
    }
}


#$processing_files = @{}
#$completed_files = @{}


# Check for any existing PDFs
try {
    $existing_files = Get-ChildItem -LiteralPath $check_folder -Filter "*.pdf" -File -ErrorAction Stop

    if ($existing_files.Count -eq 0) {
        Write-Log "No existing PDFs found."
		
    }else{
        foreach ($file in $existing_files) {
            try {
                $result = Process-CheckFile -FilePath $file.FullName

                if ($result) {
                    Write-Log "Successfully processed $file"
					
                }else{
					# If file is bad or corrupted we must delete it so program does not loop over it
					try {
						Remove-Item -LiteralPath $file -Force -ErrorAction Stop
						Write-Log "Sucessfully deleted unprocessable file"
						
					}catch{
						Write-Log "ERROR deleting bad file"
						exit 1
					}
				}
				
            }catch{
                Write-Log "ERROR processing $($file.FullName)"
                Write-Log "ERROR: $($_.Exception.Message)"
            }
        }
		
    }
	
}catch{
    Write-Log "ERROR scanning check folder during startup"
    Write-Log "ERROR: $($_.Exception.Message)"
}


try {
    $watcher = New-Object System.IO.FileSystemWatcher

    $watcher.Path = $check_folder
    $watcher.Filter = "*.pdf"
    $watcher.IncludeSubdirectories = $false
    $watcher.NotifyFilter = [System.IO.NotifyFilters]::FileName
    $watcher.InternalBufferSize = 65536


    Register-ObjectEvent `
        -InputObject $watcher `
        -EventName Created `
        -SourceIdentifier "FinanceCheckPrinter.Created" `
        -ErrorAction Stop | Out-Null


    Register-ObjectEvent `
        -InputObject $watcher `
        -EventName Error `
        -SourceIdentifier "FinanceCheckPrinter.Error" `
        -ErrorAction Stop | Out-Null


    $watcher.EnableRaisingEvents = $true

    Write-Log "File watcher started successfully."
    Write-Log "Waiting for new PDF files..."
}
catch {
    Write-Log "FATAL ERROR: Could not start file watcher."
    Write-Log "ERROR: $($_.Exception.Message)"

    if ($watcher) {
        $watcher.Dispose()
    }

    exit 1
}


try {
    while ($true) {

        $event = Wait-Event -Timeout 60

        if ($null -eq $event) {
            continue
        }


        try {

            switch ($event.SourceIdentifier) {

                "FinanceCheckPrinter.Created" {

                    $file_path = $event.SourceEventArgs.FullPath
                    #$file_key = $file_path.ToLowerInvariant()

                    Write-Log "File watcher detected: $file_path"


                    if ([System.IO.Path]::GetExtension($file_path) -ne ".pdf") {
                        Write-Log "Ignoring non-PDF file: $file_path"
                        break
                    }

                    <#
                    if ($processing_files.ContainsKey($file_key)) {
                        Write-Log "Duplicate event ignored - file is already processing: $file_path"
                        break
                    }


                    if ($completed_files.ContainsKey($file_key)) {
                        Write-Log "Duplicate event ignored - file already completed: $file_path"
                        break
                    }
                    #>


                    if (!(Test-Path -LiteralPath $file_path -PathType Leaf)) {
                        Write-Log "File no longer exists. Ignoring event: $file_path"
                        break
                    }


                    #$processing_files[$file_key] = Get-Date

                    try {

                        $result = Process-CheckFile -FilePath $file_path

                        #if ($result) {
                            #$completed_files[$file_key] = Get-Date
                            #Write-Log "File marked as completed: $file_path"
                        #}

                    }
                    catch {

                        Write-Log "UNHANDLED ERROR processing: $file_path"
                        Write-Log "ERROR: $($_.Exception.Message)"
                    }
                }


                "FinanceCheckPrinter.Error" {

                    $watcher_exception = $event.SourceEventArgs.GetException()

                    Write-Log "FILE WATCHER ERROR:"
                    Write-Log "ERROR: $($watcher_exception.Message)"

                    try {

                        $watcher.EnableRaisingEvents = $false

                        Start-Sleep -Seconds 1

                        $watcher.EnableRaisingEvents = $true

                        Write-Log "File watcher restarted successfully."
                    }
                    catch {

                        Write-Log "ERROR: Could not restart file watcher."
                        Write-Log "ERROR: $($_.Exception.Message)"
                    }
                }
            }
        }
        catch {

            Write-Log "ERROR handling filesystem event"
            Write-Log "ERROR: $($_.Exception.Message)"
        }


        Remove-Event `
            -EventIdentifier $event.EventIdentifier `
            -ErrorAction SilentlyContinue
    }
}
catch {

    Write-Log "FATAL ERROR: Main watcher loop stopped."
    Write-Log "ERROR: $($_.Exception.Message)"
}
finally {

    Write-Log "Shutting down Finance Check Printer..."


    if ($watcher) {
        $watcher.EnableRaisingEvents = $false
    }


    Unregister-Event `
        -SourceIdentifier "FinanceCheckPrinter.Created" `
        -ErrorAction SilentlyContinue


    Unregister-Event `
        -SourceIdentifier "FinanceCheckPrinter.Error" `
        -ErrorAction SilentlyContinue


    Get-Event `
        -ErrorAction SilentlyContinue |
        Where-Object {
            $_.SourceIdentifier -eq "FinanceCheckPrinter.Created" -or
            $_.SourceIdentifier -eq "FinanceCheckPrinter.Error"
        } |
        Remove-Event -ErrorAction SilentlyContinue


    if ($watcher) {
        $watcher.Dispose()
    }


    Write-Log "Finance Check Printer stopped."
}
