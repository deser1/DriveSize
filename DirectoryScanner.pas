unit DirectoryScanner;

interface

uses
  System.SysUtils, System.Classes, System.IOUtils, Winapi.Windows,
  System.Generics.Defaults;

type
  TFolderInfo = record
    Path: string;
    Size: Int64;
  end;

  TScanProgressProc = procedure(const DrivePath, CurrentPath: string;
    ScannedBytes, TotalBytes: Int64) of object;

// Zwraca TopN największych katalogów z poziomu głównego danej partycji.
// Uzupełnia także TotalSize i FreeSpace z GetDiskFreeSpaceEx.
function GetTopFolders(const DrivePath: string; TopN: Integer;
  out TotalSize: Int64; out FreeSpace: Int64; OnProgress: TScanProgressProc = nil): TArray<TFolderInfo>;

implementation

const
  FILE_ATTRIBUTE_REPARSE_POINT = $00000400;

function GetDiskFreeSpaceExW(lpDirectoryName: PWideChar;
  var lpFreeBytesAvailableToCaller: Int64;
  var lpTotalNumberOfBytes: Int64;
  var lpTotalNumberOfFreeBytes: Int64): BOOL; stdcall; external kernel32 name 'GetDiskFreeSpaceExW';

function GetFolderSizeRecursive(const DrivePath, Path: string;
    var ScannedBytes: Int64; const TotalBytes: Int64; var NextUpdate: Int64; var LastUpdateTick: DWORD; OnProgress: TScanProgressProc): Int64;
var
  SearchRec: TSearchRec;
  Base: string;
  IsDir, IsReparse: Boolean;
  ItemPath: string;
begin
  Result := 0;
  if not DirectoryExists(Path) then Exit;
  Base := IncludeTrailingPathDelimiter(Path);
  if FindFirst(Base + '*', faAnyFile, SearchRec) = 0 then
  begin
    try
      repeat
        if (SearchRec.Name = '.') or (SearchRec.Name = '..') then
          Continue;

        // Check time-based update (every 100ms) to keep UI responsive
        if (GetTickCount - LastUpdateTick) > 100 then
        begin
           if Assigned(OnProgress) and (TotalBytes > 0) then
             OnProgress(DrivePath, Base + SearchRec.Name, ScannedBytes, TotalBytes);
           LastUpdateTick := GetTickCount;
        end;

        // Omijaj punkty dowiązań (reparse point), aby nie zapętlać
        IsReparse := ((Cardinal(SearchRec.Attr) and Cardinal(FILE_ATTRIBUTE_REPARSE_POINT)) <> 0);
        if IsReparse then
          Continue;
        IsDir := ((Cardinal(SearchRec.Attr) and Cardinal(faDirectory)) <> 0);
        if IsDir then
        begin
          try
            Inc(Result, GetFolderSizeRecursive(DrivePath, Base + SearchRec.Name,
              ScannedBytes, TotalBytes, NextUpdate, LastUpdateTick, OnProgress));
          except
            on E: Exception do ;
          end;
        end
        else
        begin
          Inc(Result, SearchRec.Size);
          Inc(ScannedBytes, SearchRec.Size);
          ItemPath := Base + SearchRec.Name;
          if (ScannedBytes >= NextUpdate) then
          begin
            if Assigned(OnProgress) and (TotalBytes > 0) then
              OnProgress(DrivePath, ItemPath, ScannedBytes, TotalBytes);
            // Update every 5 MB
            NextUpdate := ScannedBytes + (5 * 1024 * 1024);
            LastUpdateTick := GetTickCount;
          end;
        end;
      until FindNext(SearchRec) <> 0;
    finally
      System.SysUtils.FindClose(SearchRec);
    end;
  end;
end;

function GetTopFolders(const DrivePath: string; TopN: Integer;
  out TotalSize: Int64; out FreeSpace: Int64; OnProgress: TScanProgressProc = nil): TArray<TFolderInfo>;
var
  SearchRec: TSearchRec;
  Info: TFolderInfo;
  TotalFree: Int64;
  Count, i: Integer;
  IsDir: Boolean;
  TempList: array of TFolderInfo;
  j: Integer;
  TempInfo: TFolderInfo;
  ScannedBytes: Int64;
  NextUpdate: Int64;
  LastUpdateTick: DWORD;
begin
  TotalSize := 0;
  FreeSpace := 0;
  SetLength(Result, 0);

  // Dane przestrzeni dysku
  TotalFree := 0;
  GetDiskFreeSpaceExW(PWideChar(DrivePath), FreeSpace, TotalSize, TotalFree);

  SetLength(TempList, 0);
  ScannedBytes := 0;
  NextUpdate := 5 * 1024 * 1024;
  LastUpdateTick := GetTickCount;
  try
    try
      if FindFirst(IncludeTrailingPathDelimiter(DrivePath) + '*', faDirectory, SearchRec) = 0 then
      begin
        try
          repeat
            IsDir := ((Cardinal(SearchRec.Attr) and Cardinal(faDirectory)) <> 0);
            if (IsDir and (SearchRec.Name <> '.') and (SearchRec.Name <> '..')) then
            begin
              Info.Path := SearchRec.Name;
              Info.Size := GetFolderSizeRecursive(DrivePath,
                IncludeTrailingPathDelimiter(DrivePath) + SearchRec.Name,
                ScannedBytes, TotalSize, NextUpdate, LastUpdateTick, OnProgress);
              if Info.Size > 0 then
              begin
                SetLength(TempList, Length(TempList) + 1);
                TempList[High(TempList)] := Info;
              end;
            end;
          until FindNext(SearchRec) <> 0;
        finally
          System.SysUtils.FindClose(SearchRec);
        end;
      end;

      if Length(TempList) > 0 then
      begin
        // Simple Bubble Sort (Descending)
        for i := Low(TempList) to High(TempList) - 1 do
          for j := i + 1 to High(TempList) do
          begin
            if TempList[j].Size > TempList[i].Size then
            begin
              TempInfo := TempList[i];
              TempList[i] := TempList[j];
              TempList[j] := TempInfo;
            end;
          end;

        if TopN < Length(TempList) then Count := TopN else Count := Length(TempList);
        SetLength(Result, Count);
        for i := 0 to Count - 1 do
          Result[i] := TempList[i];
      end;
    except
      on E: Exception do
      begin
        OutputDebugString(PChar('DirectoryScanner Error: ' + E.Message));
        SetLength(Result, 0);
      end;
    end;
  finally
    // No explicit free needed for dynamic array
  end;
end;

end.
