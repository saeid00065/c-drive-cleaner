# C Drive Cleaner

A small Windows desktop app for exploring disk usage and removing old temporary files.

## Run

Download or clone the repository, then double-click **Start Cleaner.cmd**.
**Start Cleaner.vbs** starts the same app without a console window.

Requires Windows with Windows PowerShell 5.1 and .NET Framework Windows Forms.
No additional packages are required. The launchers set execution policy for
that process only; organization policies may still restrict script execution.

## Features

- Storage chart, sorted folder sizes, and the 50 largest files.
- Drill into folders or analyze any folder on C:.
- Background scanning, cancellation, and saved scan results.
- **Safe cleanup** for supported application caches and old temporary files.
- **Clean Windows Temp** requests administrator permission and reports reclaimed space.

## Cleanup behavior

Windows and user temporary files must be older than seven days. Supported
browser and application cache files must be older than one day. Both creation
and modification dates are checked. Locked and inaccessible files are skipped.
Deletion is permanent. Close affected applications before cleaning their caches.

Personal documents, browser passwords, installed programs, recovery data, and
Windows servicing files are not cleanup targets. Directory links are not followed.
The Windows Temp button uses the same restricted cleanup worker as the main app.

The disk capacity meter uses Windows-reported space. Folder charts use logical
file sizes: hard links can count more than once, protected locations may be
unreadable, and linked/cloud folders may be skipped. Cached scans show their date;
click **Analyze** for fresh results after changing files.

## Local data

Scan caches, cleanup reports, and diagnostic logs are saved beside the scripts.
They can contain personal file paths and are excluded from Git by `.gitignore`.

## Verification

Run in Windows PowerShell from the repository folder:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File .\Cleaner.ps1 -SmokeTest
powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File '.\Storage Map.ps1' -SmokeTest
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Verify-Cleanup.ps1
```

Smoke checks scan AppData and open/close the interface without deleting user data.
The cleanup verification creates isolated disposable files and checks selection,
age filtering, locked-file handling, deletion, and result counts.
