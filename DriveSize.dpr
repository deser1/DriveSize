library DriveSize;

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

{$R *.RES}
{$R 'DriveSizeResource.res' 'DriveSizeResource.rc'}

{$E cpl}
// Definicja stałych i struktur Panelu Sterowania
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
    lData: LongInt;
  end;
  PCPLInfo = ^TCPLInfo;

  TNewCPLInfo = record
    dwSize: DWORD;
    dwFlags: DWORD;
    dwHelpContext: DWORD;
    lData: LongInt;
    hIcon: HICON;
    szName: array[0..31] of Char;
    szInfo: array[0..63] of Char;
    szHelpFile: array[0..127] of Char;
  end;
  PNewCPLInfo = ^TNewCPLInfo;

// Główna funkcja eksportowana
function CPlApplet(hwndCPl: HWND; uMsg: UINT; lParam1, lParam2: LPARAM): LongInt; stdcall;
var
  NewCPLInfo: PNewCPLInfo;
begin
  Result := 0;
  OutputDebugString(PChar('CPlApplet Msg: ' + IntToStr(uMsg)));
  try
    case uMsg of
      1: Result := 1; // CPL_INIT
      2: Result := 1; // CPL_GETCOUNT
      3: // CPL_INQUIRE
        begin
          // Fallback if NEWINQUIRE not sent
          if lParam2 <> 0 then
          begin
            PCPLInfo(lParam2)^.idIcon := 1;
            PCPLInfo(lParam2)^.idName := 1;
            PCPLInfo(lParam2)^.idInfo := 1;
            PCPLInfo(lParam2)^.lData := 0;
          end;
          Result := 0; // Handled
        end;
      8: // CPL_NEWINQUIRE
        begin
          if lParam2 <> 0 then
          begin
             NewCPLInfo := PNewCPLInfo(lParam2);
             NewCPLInfo^.dwSize := SizeOf(TNewCPLInfo);
             NewCPLInfo^.dwFlags := 0;
             NewCPLInfo^.dwHelpContext := 0;
             NewCPLInfo^.lData := 0;
             NewCPLInfo^.hIcon := LoadIcon(HInstance, MakeIntResource(1)); // Try loading icon 1
             
             // Direct string assignment
              StrPLCopy(@NewCPLInfo^.szName, 'Drive Size', 31);
              StrPLCopy(@NewCPLInfo^.szInfo, 'Disk Space Analyzer', 63);
             NewCPLInfo^.szHelpFile[0] := #0;
          end;
          Result := 0; // Handled
        end;
      5: // CPL_DBLCLK
        begin
          // Inicjalizacja środowiska VCL dla wątków wewnątrz DLL
          Application.Initialize;
          Application.CreateForm(TDriveSizeFrm, DriveSizeFrm);
          try
            DriveSizeFrm.ShowModal;
          finally
            // Zamykanie wątków przed zwolnieniem formy
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
  // Blok begin-end w DLL powinien być pusty!
end.
