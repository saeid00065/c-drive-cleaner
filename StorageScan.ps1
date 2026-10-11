param([string]$Root)
$ErrorActionPreference='Stop'
if(-not ('StorageScan' -as [type])) { Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Collections.Generic;
public class StorageFile { public string Path; public long Bytes; }
public class StorageRow {
 public string Name; public string Path; public bool Directory; public long Bytes; public long Files; public int Skipped;
 public List<StorageFile> Largest = new List<StorageFile>();
}
public static class StorageScan {
 public static volatile bool Cancelled;
 public static long FilesSeen;
 public static string CurrentPath = "";
 static void File(StorageRow row, FileInfo file) {
  try { if((file.Attributes & FileAttributes.ReparsePoint)!=0) {row.Skipped++;return;}
   long size=file.Length; row.Bytes+=size; row.Files++;FilesSeen++;
   if(size>1048576) {row.Largest.Add(new StorageFile {Path=file.FullName,Bytes=size});
    if(row.Largest.Count>100) {row.Largest.Sort((a,b)=>b.Bytes.CompareTo(a.Bytes));row.Largest.RemoveRange(50,row.Largest.Count-50);}}
  } catch {row.Skipped++;}
 }
 public static StorageRow Measure(string path) {
  StorageRow row=new StorageRow {Path=path,Name=System.IO.Path.GetFileName(path)};
  try {
   var attr=System.IO.File.GetAttributes(path);
   if((attr & FileAttributes.ReparsePoint)!=0){row.Skipped++;return row;}
   row.Directory=(attr & FileAttributes.Directory)!=0;
   if(!row.Directory){File(row,new FileInfo(path));return row;}
   var pending=new Stack<string>();pending.Push(path);
   while(pending.Count>0 && !Cancelled){var current=pending.Pop();CurrentPath=current;
    try {foreach(var file in new DirectoryInfo(current).EnumerateFiles()) {if(Cancelled)break;File(row,file);}}catch{row.Skipped++;}
    try {foreach(var dir in new DirectoryInfo(current).EnumerateDirectories()){
     try {if((dir.Attributes & FileAttributes.ReparsePoint)==0)pending.Push(dir.FullName);else row.Skipped++;}catch{row.Skipped++;}
    }}catch{row.Skipped++;}
   }
  }catch{row.Skipped++;}
  row.Largest.Sort((a,b)=>b.Bytes.CompareTo(a.Bytes));
  if(row.Largest.Count>50)row.Largest.RemoveRange(50,row.Largest.Count-50);
  return row;
 }
}
'@
}
$full=[IO.Path]::GetFullPath($Root)
if(-not $full.StartsWith('C:\',[StringComparison]::OrdinalIgnoreCase)){throw 'Choose a folder on C:.'}
$check=Get-Item -LiteralPath $full -Force
while($check){
 if($check.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Linked folders are excluded.'}
 $check=$check.Parent
}
Get-ChildItem -LiteralPath $full -Force -ErrorAction Stop | ForEach-Object {
 if([StorageScan]::Cancelled){return}
 $result=[StorageScan]::Measure($_.FullName)
 [pscustomobject]@{Name=$result.Name;Path=$result.Path;Directory=$result.Directory;Bytes=$result.Bytes;Files=$result.Files;Skipped=$result.Skipped;Largest=@($result.Largest|ForEach-Object {[pscustomobject]@{Path=$_.Path;Bytes=$_.Bytes}})}
}
