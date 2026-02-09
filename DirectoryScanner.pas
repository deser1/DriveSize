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

// Zwraca TopN największych katalogów z poziomu głównego danej partycji.
// Uzupełnia także TotalSize i FreeSpace z GetDiskFreeSpaceEx.
function GetTopFolders(const DrivePath: string; TopN: Integer;
  out TotalSize: Int64; out FreeSpace: Int64): TArray<TFolderInfo>;

implementation

const
  FILE_ATTRIBUTE_REPARSE_POINT = $00000400;

// Explicit wide-character import to avoid overload resolution issues with dcc32
function GetDiskFreeSpaceExW(lpDirectoryName: PWideChar;
  var lpFreeBytesAvailableToCaller: Int64;
  var lpTotalNumberOfBytes: Int64;
  var lpTotalNumberOfFreeBytes: Int64): BOOL; stdcall; external kernel32 name 'GetDiskFreeSpaceExW';

function GetFolderSizeRecursive(const Path: string): Int64;
var
  SearchRec: TSearchRec;
  Base: string;
  IsDir, IsReparse: Boolean;
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
        // Omijaj punkty dowiązań (reparse point), aby nie zapętlać
        IsReparse := ((Cardinal(SearchRec.Attr) and Cardinal(FILE_ATTRIBUTE_REPARSE_POINT)) <> 0);
        if IsReparse then
          Continue;
        IsDir := ((Cardinal(SearchRec.Attr) and Cardinal(faDirectory)) <> 0);
        if IsDir then
        begin
          try
            Inc(Result, GetFolderSizeRecursive(Base + SearchRec.Name));
          except
            on E: Exception do ;
          end;
        end
        else
          Inc(Result, SearchRec.Size);
      until FindNext(SearchRec) <> 0;
    finally
      System.SysUtils.FindClose(SearchRec);
    end;
  end;
end;

function GetTopFolders(const DrivePath: string; TopN: Integer;
  out TotalSize: Int64; out FreeSpace: Int64): TArray<TFolderInfo>;
var
  SearchRec: TSearchRec;
  Info: TFolderInfo;
  TotalFree: Int64;
  Count, i: Integer;
  IsDir: Boolean;
  TempList: array of TFolderInfo;
  j: Integer;
  TempInfo: TFolderInfo;
begin
  TotalSize := 0;
  FreeSpace := 0;
  SetLength(Result, 0);

  // Dane przestrzeni dysku
  TotalFree := 0;
  GetDiskFreeSpaceExW(PWideChar(DrivePath), FreeSpace, TotalSize, TotalFree);

  SetLength(TempList, 0);
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
              Info.Size := GetFolderSizeRecursive(IncludeTrailingPathDelimiter(DrivePath) + SearchRec.Name);
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
