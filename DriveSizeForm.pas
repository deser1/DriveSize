unit DriveSizeForm;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants, System.Classes, Vcl.Graphics,
  Vcl.GraphUtil, Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.ExtCtrls, System.Generics.Collections,
  System.Generics.Defaults, System.Math, System.Types, System.IOUtils, PieRenderer, DirectoryScanner;

const
  MAX_DRIVES = 10;

type
  TFolderInfo = record
    Path: string;
    Size: Int64;
  end;
  TDriveData = record
    DriveLetter: string;
    TotalSize, FreeSpace: Int64;
    Folders: array[0..2] of TFolderInfo;
    TopFolders: array of TFolderInfo;
    ScanProgress: Double;
    CurrentFileName: string;
  end;
  TDriveSizeFrm = class(TForm)
    PaintBox1: TPaintBox;
    Timer1: TTimer;
    procedure FormPaint(Sender: TObject);
    procedure Timer1Timer(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure FormActivate(Sender: TObject);
    procedure FormMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
  private
    FIsScanning: Boolean;
    FPainting: Boolean;
    FLayouts: array[0..MAX_DRIVES-1] of TPieChartLayout;
    FHoverDrive: Integer;
    FHoverSegmentIndex: Integer;
    
    procedure StartScan;
    procedure DetectDrives;
    procedure ScanDrivesSync;
  public
    procedure AppExceptionHandler(Sender: TObject; E: Exception);
  end;

var
  DriveSizeFrm: TDriveSizeFrm;
  FDrives: array[0..MAX_DRIVES-1] of TDriveData;
  FActualDriveCount: Integer = 0;
  DiagLogPath: string;

procedure DebugLog(const Msg: string);
procedure GlobalAppExceptionHandler(Sender: TObject; E: Exception);
function EllipsizeMiddle(const S: string; MaxLen: Integer): string;

implementation

{$R *.dfm}

function GetDiskFreeSpaceExW(lpDirectoryName: PWideChar;
  var lpFreeBytesAvailableToCaller: Int64;
  var lpTotalNumberOfBytes: Int64;
  var lpTotalNumberOfFreeBytes: Int64): BOOL; stdcall; external kernel32 name 'GetDiskFreeSpaceExW';

procedure TDriveSizeFrm.FormActivate(Sender: TObject);
begin
  if not FIsScanning then
  begin
    OnActivate := nil;
    StartScan;
  end;
end;

procedure TDriveSizeFrm.FormCreate(Sender: TObject);
begin
  DebugLog('FormCreate: start');
  DoubleBuffered := True;
  OnMouseMove := FormMouseMove;
  FHoverDrive := -1;
  FHoverSegmentIndex := -1;

  Finalize(FDrives);
  DetectDrives;
  DebugLog(Format('FormCreate: DetectDrives done, FActualDriveCount=%d', [FActualDriveCount]));

  if Length(FDrives) = 0 then
    Caption := 'Error: No drives found'
  else
    Caption := 'Drive Size';

  // Load Icon from Resource ID 1
  if HInstance <> 0 then
    Icon.LoadFromResourceID(HInstance, 1);

  // Globalne przechwytywanie EListError, aby aplet nie pokazywał błędów przy starcie
  Application.OnException := AppExceptionHandler;
end;

{$R-} 
procedure TDriveSizeFrm.FormPaint(Sender: TObject);
const
  cColors: array[0..2] of TColor = ($004B4BFF, $0000A5FF, $00FF9933);
var
  d, i, LegendY, StatusY: Integer;
  CenterX, CenterY, Radius, ChartSpacing: Integer;
  LabelTxt: string;
  LX, LY: Integer;
  DriveCount: Integer;
  Layout: TPieChartLayout;
  TopSizes: TArray<Int64>;
  TotalFree: Int64;
  TotalUsedInChart: Int64;
  Highlight: Integer;
  S: TPieSegment;
  MidAngle, Percent: Double;
  SizeGB, OtherGB, FreeGB, TFPercent: Double;
  UsedBytes, OtherUsedBytes: Int64;
  OtherPercent, FreePercent: Double;
  maxTop: Integer;
  FolderName: string;
  LegendX: Integer;
  LFreeAvailable, LTotalSpace, LTotalFree: Int64;
  PlacedLeft, PlacedRight: TList<TRect>;
  R: TRect;
  BoxHalfW, BoxHalfH: Integer;
  CombinedHalfW: Integer;
  IsLeft: Boolean;
  AnchorX, AnchorY, BendX, BendY, EdgeX: Integer;
  FolderY: Integer;
  j: Integer;
  ERect: TRect;
  Overlap: Boolean;
  LeftColumnRight, RightColumnLeft, TopBound, BottomBound, LabelGapX: Integer;
  ScanTxt: string;
  ScanRect: TRect;
  StatusTextX, StatusTextY: Integer;
  TwoLine: Boolean;
  NameHalfW: Integer;
  ExtraH: Integer;
begin
  if FPainting then Exit;
  FPainting := True;
  try
    try
      DriveCount := FActualDriveCount;

      if DriveCount <= 0 then
        Exit;
      if FActualDriveCount <= 0 then
      begin
        Canvas.TextOut(20, 20, 'Searching drives...');
        DebugLog('FormPaint: FActualDriveCount=0, exit painting');
        Exit;
      end;

      Canvas.Brush.Color := $F7F7F7;
      Canvas.FillRect(ClientRect);

      ChartSpacing := ClientHeight div FActualDriveCount;
      Radius := Round(ChartSpacing * 0.22);
      if Radius > 75 then Radius := 75;
      CenterX := Width div 3;
      CenterY := ChartSpacing div 2;

      DebugLog(Format('FormPaint: start, DriveCount=%d', [DriveCount]));
      
      for d := 0 to DriveCount - 1 do
      begin
        TotalFree := 0;
        if GetDiskFreeSpaceExW(PChar(FDrives[d].DriveLetter), LFreeAvailable, LTotalSpace, LTotalFree) then
        begin
           FDrives[d].FreeSpace := LFreeAvailable;
           FDrives[d].TotalSize := LTotalSpace;
           TotalFree := LTotalFree;
        end
        else
          Continue;

        SetLength(TopSizes, Length(FDrives[d].TopFolders));
        TotalUsedInChart := 0;
        for i := 0 to High(TopSizes) do
        begin
          TopSizes[i] := FDrives[d].TopFolders[i].Size;
          TotalUsedInChart := TotalUsedInChart + TopSizes[i];
        end;

        Highlight := -1;
        if d = FHoverDrive then Highlight := FHoverSegmentIndex;
        RenderDrivePie(Canvas, CenterX, CenterY, Radius,
          FDrives[d].TotalSize, FDrives[d].FreeSpace, TopSizes, cColors,
          Layout, Highlight);
        FLayouts[d] := Layout;

        PlacedLeft := TList<TRect>.Create;
        PlacedRight := TList<TRect>.Create;
        try
          LegendY := CenterY - Radius;
          LegendX := CenterX + Radius + 80;
          StatusY := (d + 1) * ChartSpacing - 30;

          // parametry kolumn i ograniczenia
          BoxHalfH := 10; // default; aktualny dla każdego dymka poniżej
          // Lewa kolumna kończy się przed obszarem Scan i przed kołem
          LeftColumnRight := CenterX - Radius - 60;
          // Prawa kolumna zaczyna się przed legendą (margines)
          RightColumnLeft := LegendX - 12;
          // Granice pionowe dostępnego pasa
          TopBound := CenterY - Radius - 8;
          BottomBound := CenterY + Radius + 8;
          if BottomBound > (StatusY - 6) then BottomBound := StatusY - 6;
          // Odległość od koła
          LabelGapX := 40;

          for i := 0 to High(Layout.Segments) do
          begin
            S := Layout.Segments[i];
            MidAngle := (S.StartAngle + S.EndAngle) / 2.0;
            Percent := (S.EndAngle - S.StartAngle) / 360.0;

            case S.Kind of
              psTop:
                begin
                  SizeGB := FDrives[d].TopFolders[S.TopIndex].Size / 1073741824;
                  LabelTxt := Format('%.1f%% . %.1f GB', [Percent * 100, SizeGB]);
                  FolderName := EllipsizeMiddle(FDrives[d].TopFolders[S.TopIndex].Path, 40);
                  NameHalfW := Canvas.TextWidth(FolderName) div 2;
                  TwoLine := True;
                end;
              psOther:
                begin
                  OtherGB := (Percent * FDrives[d].TotalSize) / 1073741824;
                  LabelTxt := Format('%.1f%% . %.1f GB', [Percent * 100, OtherGB]);
                  NameHalfW := 0;
                  TwoLine := False;
                end;
              psFree:
                begin
                  FreeGB := (Percent * FDrives[d].TotalSize) / 1073741824;
                  LabelTxt := Format('%.1f%% . %.1f GB', [Percent * 100, FreeGB]);
                  NameHalfW := 0;
                  TwoLine := False;
                end;
            end;

            IsLeft := Cos(MidAngle * Pi / 180) < 0;
            BoxHalfH := 10;
            BoxHalfW := (Canvas.TextWidth(LabelTxt) div 2) + 6;
            CombinedHalfW := BoxHalfW;
            if NameHalfW > CombinedHalfW then CombinedHalfW := NameHalfW;
            if IsLeft then
              LX := CenterX - (Radius + LabelGapX)
            else
              LX := CenterX + (Radius + LabelGapX);
            LY := CenterY - Round((Radius + 0) * Sin(MidAngle * Pi / 180));

            // klamry poziome względem kolumn
            if IsLeft then
            begin
              if LX + CombinedHalfW > LeftColumnRight then
                LX := LeftColumnRight - CombinedHalfW;
            end
            else
            begin
              if LX + CombinedHalfW > RightColumnLeft then
                LX := RightColumnLeft - CombinedHalfW;
            end;
            if TwoLine then ExtraH := Canvas.TextHeight('Ag') + 2 else ExtraH := 0;
            R.Left := LX - CombinedHalfW;
            R.Top := LY - BoxHalfH;
            R.Right := LX + CombinedHalfW;
            R.Bottom := LY + BoxHalfH + ExtraH;

            if IsLeft then
                begin
                  Overlap := True;
                  while Overlap do
                  begin
                    Overlap := False;
                    // ograniczenia pionowe
                    if R.Top < TopBound then
                    begin
                      LY := TopBound + BoxHalfH;
                      R.Top := LY - BoxHalfH;
                      R.Bottom := LY + BoxHalfH + ExtraH;
                    end
                    else if R.Bottom > BottomBound then
                    begin
                      LY := BottomBound - BoxHalfH;
                      R.Top := LY - BoxHalfH;
                      R.Bottom := LY + BoxHalfH + ExtraH;
                    end;
                    for j := 0 to PlacedLeft.Count - 1 do
                    begin
                      ERect := PlacedLeft[j];
                      if not ((R.Right <= ERect.Left) or (R.Left >= ERect.Right) or (R.Bottom <= ERect.Top) or (R.Top >= ERect.Bottom)) then
                      begin
                        Overlap := True;
                        Inc(LY, 20);
                        if LY + BoxHalfH > BottomBound then
                          LY := TopBound + BoxHalfH;
                        R.Top := LY - BoxHalfH;
                        R.Bottom := LY + BoxHalfH + ExtraH;
                      end;
                    end;
                  end;
                  PlacedLeft.Add(R);
                end
                else
                begin
                  Overlap := True;
                  while Overlap do
                  begin
                    Overlap := False;
                    if R.Top < TopBound then
                    begin
                      LY := TopBound + BoxHalfH;
                      R.Top := LY - BoxHalfH;
                      R.Bottom := LY + BoxHalfH + ExtraH;
                    end
                    else if R.Bottom > BottomBound then
                    begin
                      LY := BottomBound - BoxHalfH;
                      R.Top := LY - BoxHalfH;
                      R.Bottom := LY + BoxHalfH + ExtraH;
                    end;
                    for j := 0 to PlacedRight.Count - 1 do
                    begin
                      ERect := PlacedRight[j];
                      if not ((R.Right <= ERect.Left) or (R.Left >= ERect.Right) or (R.Bottom <= ERect.Top) or (R.Top >= ERect.Bottom)) then
                      begin
                        Overlap := True;
                        Inc(LY, 20);
                        if LY + BoxHalfH > BottomBound then
                          LY := TopBound + BoxHalfH;
                        R.Top := LY - BoxHalfH;
                        R.Bottom := LY + BoxHalfH + ExtraH;
                      end;
                    end;
                  end;
                  PlacedRight.Add(R);
                end;

            AnchorX := CenterX + Round(Radius * Cos(MidAngle * Pi / 180));
            AnchorY := CenterY - Round(Radius * Sin(MidAngle * Pi / 180));
            BendX := CenterX + Round((Radius + 8) * Cos(MidAngle * Pi / 180));
            BendY := CenterY - Round((Radius + 8) * Sin(MidAngle * Pi / 180));
            if IsLeft then
              EdgeX := R.Right
            else
              EdgeX := R.Left;

            Canvas.Pen.Color := clGray;
            Canvas.Pen.Width := 1;
            Canvas.MoveTo(AnchorX, AnchorY);
            Canvas.LineTo(BendX, BendY);
            Canvas.LineTo(EdgeX, LY);

            Canvas.Brush.Color := clWhite;
            Canvas.RoundRect(LX - BoxHalfW, LY - BoxHalfH, LX + BoxHalfW, LY + BoxHalfH, 5, 5);
            Canvas.Brush.Style := bsClear;
            Canvas.TextOut(LX - (Canvas.TextWidth(LabelTxt) div 2), LY - 7, LabelTxt);

            if S.Kind = psTop then
            begin
              FolderY := LY + BoxHalfH + 2;
              Canvas.TextOut(LX - (Canvas.TextWidth(FolderName) div 2), FolderY, FolderName);
            end;
          end;
          // rozmieść i narysuj napis Scan tak, by nie kolidował z dymkami
          Canvas.Font.Size := 7;
          Canvas.Font.Style := [];
          ScanTxt := Format('Scan: %s (%.0f%%)', [FDrives[d].CurrentFileName, FDrives[d].ScanProgress]);
          StatusTextX := 40;
          StatusTextY := StatusY - 14;
          ScanRect.Left := StatusTextX;
          ScanRect.Top := StatusTextY;
          ScanRect.Right := StatusTextX + Canvas.TextWidth(ScanTxt);
          ScanRect.Bottom := StatusTextY + Canvas.TextHeight(ScanTxt);
          Overlap := True;
          while Overlap do
          begin
            Overlap := False;
            if ScanRect.Top < TopBound then
            begin
              StatusTextY := TopBound;
              ScanRect.Top := StatusTextY;
              ScanRect.Bottom := StatusTextY + Canvas.TextHeight(ScanTxt);
            end
            else if ScanRect.Bottom > BottomBound then
            begin
              StatusTextY := BottomBound - Canvas.TextHeight(ScanTxt);
              ScanRect.Top := StatusTextY;
              ScanRect.Bottom := StatusTextY + Canvas.TextHeight(ScanTxt);
            end;
            for j := 0 to PlacedLeft.Count - 1 do
            begin
              ERect := PlacedLeft[j];
              if not ((ScanRect.Right <= ERect.Left) or (ScanRect.Left >= ERect.Right) or (ScanRect.Bottom <= ERect.Top) or (ScanRect.Top >= ERect.Bottom)) then
              begin
                Overlap := True;
                Inc(StatusTextY, 14);
                if StatusTextY + Canvas.TextHeight(ScanTxt) > BottomBound then
                  StatusTextY := TopBound;
                ScanRect.Top := StatusTextY;
                ScanRect.Bottom := StatusTextY + Canvas.TextHeight(ScanTxt);
              end;
            end;
          end;
          Canvas.TextOut(StatusTextX, StatusTextY, ScanTxt);
        finally
          PlacedLeft.Free;
          PlacedRight.Free;
        end;

        LegendY := CenterY - Radius;
        Canvas.Brush.Style := bsClear;
        Canvas.Font.Style := [fsBold];
        Canvas.TextOut(CenterX + Radius + 80, LegendY - 20, 'Drive ' + FDrives[d].DriveLetter);

        LegendX := CenterX + Radius + 80;
        Canvas.Pen.Color := clGray;
        Canvas.Brush.Style := bsSolid;
        Canvas.Brush.Color := $00808080; // Other used
        Canvas.Rectangle(LegendX, LegendY, LegendX + 12, LegendY + 12);
        Canvas.Brush.Color := clBtnFace;
        Canvas.Brush.Style := bsClear;
        UsedBytes := FDrives[d].TotalSize - FDrives[d].FreeSpace;
        OtherUsedBytes := UsedBytes - TotalUsedInChart;
        if OtherUsedBytes < 0 then OtherUsedBytes := 0;
        OtherPercent := 0.0;
        if FDrives[d].TotalSize > 0 then OtherPercent := OtherUsedBytes / FDrives[d].TotalSize;
        Canvas.TextOut(LegendX + 18, LegendY,
          Format('Other used (%.1f GB, %.1f%%)', [OtherUsedBytes / 1073741824, OtherPercent * 100]));

        Canvas.Brush.Style := bsSolid;
        Canvas.Brush.Color := $00E0E0E0; // Free
        Canvas.Rectangle(LegendX, LegendY + 18, LegendX + 12, LegendY + 30);
        Canvas.Brush.Style := bsClear;
        FreePercent := 0.0;
        if FDrives[d].TotalSize > 0 then FreePercent := FDrives[d].FreeSpace / FDrives[d].TotalSize;
        Canvas.TextOut(LegendX + 18, LegendY + 18,
          Format('Free (%.1f GB, %.1f%%)', [FDrives[d].FreeSpace / 1073741824, FreePercent * 100]));

        maxTop := System.Math.Min(3, Length(FDrives[d].TopFolders));
        for i := 0 to maxTop - 1 do
        begin
          Canvas.Brush.Style := bsSolid;
          Canvas.Brush.Color := TColor(cColors[i mod 3]);
          Canvas.Rectangle(LegendX, LegendY + 36 + (i * 18), LegendX + 12, LegendY + 48 + (i * 18));
          Canvas.Brush.Style := bsClear;
          TFPercent := 0.0;
          if FDrives[d].TotalSize > 0 then TFPercent := FDrives[d].TopFolders[i].Size / FDrives[d].TotalSize;
          Canvas.TextOut(LegendX + 18, LegendY + 36 + (i * 18),
            Format('Top %d: %s (%.1f GB, %.1f%%)', [i + 1, EllipsizeMiddle(FDrives[d].TopFolders[i].Path, 50),
            FDrives[d].TopFolders[i].Size / 1073741824, TFPercent * 100]));
        end;

        // napis Scan został narysowany wcześniej po ułożeniu dymków

        Inc(CenterY, ChartSpacing);
      end;
    except
      on E: EListError do
      begin
        Canvas.Brush.Style := bsClear;
        Canvas.Font.Color := clRed;
        Canvas.TextOut(20, 20, 'Loading data...');
        DebugLog('FormPaint: EListError caught');
      end;
      on E: Exception do
      begin
        DebugLog('FormPaint: Exception: ' + E.ClassName + ' ' + E.Message);
      end;
    end;
  finally
    FPainting := False;
  end;
end;

procedure TDriveSizeFrm.DetectDrives;
var
  DriveMask: DWORD;
  i: Integer;
  DrivePath: string;
begin
  DebugLog('DetectDrives: start');
  DriveMask := GetLogicalDrives;
  FActualDriveCount := 0;

  FillChar(FDrives, SizeOf(FDrives), 0);

  for i := 0 to 25 do
    if (DriveMask and (1 shl i)) <> 0 then
    begin
      DrivePath := Char(Ord('A') + i) + ':\';
      if (GetDriveType(PChar(DrivePath)) = DRIVE_FIXED) and (FActualDriveCount < MAX_DRIVES) then
      begin
        FDrives[FActualDriveCount].DriveLetter := DrivePath;
        FDrives[FActualDriveCount].CurrentFileName := 'Waiting...';
        Inc(FActualDriveCount);
      end;
    end;
  DebugLog(Format('DetectDrives: found=%d', [FActualDriveCount]));
end;

procedure TDriveSizeFrm.ScanDrivesSync;
var
  d: Integer;
  DriveCount: Integer;
  TopFolders: TArray<DirectoryScanner.TFolderInfo>;
  TotalSize, FreeSpace: Int64;
  k: Integer;
begin
  FIsScanning := True;
  try
    DriveCount := FActualDriveCount;
    for d := 0 to DriveCount - 1 do
    begin
      FDrives[d].CurrentFileName := 'Scanning...';
      Invalidate;
      Application.ProcessMessages;

      try
         TopFolders := DirectoryScanner.GetTopFolders(FDrives[d].DriveLetter, 3, TotalSize, FreeSpace);
         
         SetLength(FDrives[d].TopFolders, Length(TopFolders));
         for k := 0 to High(TopFolders) do
         begin
           FDrives[d].TopFolders[k].Path := TopFolders[k].Path;
           FDrives[d].TopFolders[k].Size := TopFolders[k].Size;
         end;
         FDrives[d].TotalSize := TotalSize;
         FDrives[d].FreeSpace := FreeSpace;
         FDrives[d].ScanProgress := 100;
         FDrives[d].CurrentFileName := 'Done';
         
      except
        on E: Exception do
        begin
           DebugLog('Scan Error on drive ' + IntToStr(d) + ': ' + E.Message);
           FDrives[d].CurrentFileName := 'Error';
        end;
      end;
      
      Invalidate;
      try
        Application.ProcessMessages;
      except
        on E: Exception do DebugLog('ProcessMessages Error: ' + E.Message);
      end;
    end;
  finally
    FIsScanning := False;
  end;
end;

procedure TDriveSizeFrm.StartScan;
begin
  Timer1.Interval := 100;
  Timer1.OnTimer := Timer1Timer;
  Timer1.Enabled := True;
end;

procedure TDriveSizeFrm.Timer1Timer(Sender: TObject);
begin
  Timer1.Enabled := False;
  ScanDrivesSync;
end;

procedure TDriveSizeFrm.AppExceptionHandler(Sender: TObject; E: Exception);
begin
  if (E is EListError) or (E is EArgumentOutOfRangeException) then
    Exit
  else
    Application.ShowException(E);
end;

procedure DebugLog(const Msg: string);
begin
  try
    if DiagLogPath = '' then
      DiagLogPath := IncludeTrailingPathDelimiter(TPath.GetTempPath) + 'DriveSizeDiag.log';
    TFile.AppendAllText(DiagLogPath,
      FormatDateTime('yyyy-mm-dd hh:nn:ss.zzz', Now) + ' ' + Msg + sLineBreak);
  except
  end;
end;

procedure GlobalAppExceptionHandler(Sender: TObject; E: Exception);
begin
  if E is EListError then
  begin
    DebugLog('GlobalAppExceptionHandler: EListError: ' + E.Message);
    Exit;
  end;
  Application.ShowException(E);
end;

function EllipsizeMiddle(const S: string; MaxLen: Integer): string;
var
  Part: Integer;
begin
  if Length(S) <= MaxLen then
    Exit(S);
  if MaxLen < 5 then
    Exit(Copy(S, 1, MaxLen));
  Part := (MaxLen - 3) div 2;
  Result := Copy(S, 1, Part) + '...' + Copy(S, Length(S) - Part + 1, Part);
end;

procedure TDriveSizeFrm.FormMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
var
  d, idx: Integer;
begin
  FHoverDrive := -1;
  FHoverSegmentIndex := -1;
  for d := 0 to FActualDriveCount - 1 do
  begin
    if HitTestPie(FLayouts[d], X, Y, idx) then
    begin
      FHoverDrive := d;
      FHoverSegmentIndex := idx;
      Break;
    end;
  end;
  Invalidate;
end;

end.
