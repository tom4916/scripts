:: Simple repair script.

@echo off
write-host "Running System File Checker (SFC)" -foregroundcolor green
sfc /scannow

write-host "Running DISM RestoreHealth" -foregroundcolor green
DISM /Online /Cleanup-Image /RestoreHealth

write-host "Running System File Checker (SFC)" -foregroundcolor green
defrag C: /o

write-host "Updating Group Policy" -foregroundcolor green
gpudate /force

write-host "Repairs complete." -foregroundcolor green
pause