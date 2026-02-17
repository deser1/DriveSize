library BuildDriveSize;

uses
  Vcl.Forms,
  Vcl.Dialogs,
  Winapi.Windows,
  Winapi.Messages,
  System.Classes,
  System.UITypes,
  System.SysUtils,
  DriveSizeForm in 'DriveSizeForm.pas' {DriveSizeFrm},
  DirectoryScanner in 'DirectoryScanner.pas',
  PieRenderer in 'PieRenderer.pas';

{$R 'DriveSize.res'}
{$R 'DriveSizeResource.res'}
{$R 'DriveSizeStrings.res'}

{$E cpl}

const
  CPL_INIT = 1;
  CPL_GETCOUNT = 2;
  CPL_INQUIRE = 3;
  CPL_DBLCLK = 5;
  CPL_STOP = 7;
  CPL_EXIT = 8;
  CPL_NEWINQUIRE = 8;

type
  TCPLInfo = record
    idIcon: Integer;
    idName: Integer;
    idInfo: Integer;
    lData: NativeInt;
  end;
  PCPLInfo = ^TCPLInfo;

  TNewCPLInfo = record
    dwSize: DWORD;
    dwFlags: DWORD;
    dwHelpContext: DWORD;
    lData: NativeInt;
    hIcon: HICON;
    szName: array[0..31] of WideChar;
    szInfo: array[0..63] of WideChar;
    szHelpFile: array[0..127] of WideChar;
  end;
  PNewCPLInfo = ^TNewCPLInfo;

function CPlApplet(hwndCPl: HWND; uMsg: UINT; lParam1, lParam2: LPARAM): LongInt; stdcall;
var
  NewCPLInfo: PNewCPLInfo;
begin
  Result := 0;
  try
    case uMsg of
      CPL_INIT: Result := 1;
      CPL_GETCOUNT: Result := 1;
      CPL_INQUIRE:
        begin
          if lParam2 <> 0 then
          begin
            PCPLInfo(lParam2)^.idIcon := 1;
            PCPLInfo(lParam2)^.idName := 1;
            PCPLInfo(lParam2)^.idInfo := 2;
            PCPLInfo(lParam2)^.lData := 0;
          end;
          Result := 0;
        end;
      CPL_NEWINQUIRE:
        begin
          if lParam2 <> 0 then
          begin
            NewCPLInfo := PNewCPLInfo(lParam2);
            NewCPLInfo^.dwSize := SizeOf(TNewCPLInfo);
            NewCPLInfo^.dwFlags := 0;
            NewCPLInfo^.dwHelpContext := 0;
            NewCPLInfo^.lData := 0;
            NewCPLInfo^.hIcon := LoadIcon(HInstance, MakeIntResource(1));
            NewCPLInfo^.szName[0] := #0;
            NewCPLInfo^.szInfo[0] := #0;
            NewCPLInfo^.szHelpFile[0] := #0;
          end;
          Result := 0;
        end;
      CPL_DBLCLK:
        begin
          Application.Initialize;
          Application.CreateForm(TDriveSizeFrm, DriveSizeFrm);
          try
            DriveSizeFrm.ShowModal;
          finally
            DriveSizeFrm.Free;
            DriveSizeFrm := nil;
          end;
        end;
    end;
  except
    on E: Exception do
      MessageBox(0, PChar('CPlApplet Crash: ' + E.Message), 'Error', MB_OK or MB_ICONERROR);
  end;
end;

exports CPlApplet;

begin
end.
