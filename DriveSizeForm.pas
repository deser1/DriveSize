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
    procedure FormDestroy(Sender: TObject);
  private
    FIsScanning: Boolean;
    FPainting: Boolean;
    FLayouts: array[0..MAX_DRIVES-1] of TPieChartLayout;
    FHoverDrive: Integer;
    FHoverSegmentIndex: Integer;
    FCurrentScanDrive: Integer;
    
    procedure StartScan;
    procedure DetectDrives;
    procedure ScanDrivesSync;
    procedure ScanProgress(const DrivePath, CurrentPath: string;
      ScannedBytes, TotalBytes: Int64);
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

type
  TScanThread = class(TThread)
  private
    FDrivePath: string;
    FResultTopFolders: TArray<DirectoryScanner.TFolderInfo>;
    FResultTotalSize: Int64;
    FResultFreeSpace: Int64;
    FCurrentPath: string;
    FScannedBytes: Int64;
    FTotalBytes: Int64;
    FDriveIndex: Integer;
    FOnProgress: TScanProgressProc;
    procedure DoProgressSync;
    procedure DoFinishSync;
    procedure ScanCallback(const DrivePath, CurrentPath: string; ScannedBytes, TotalBytes: Int64);
  protected
    procedure Execute; override;
  public
    constructor Create(const DrivePath: string; DriveIndex: Integer; OnProgress: TScanProgressProc);
  end;

constructor TScanThread.Create(const DrivePath: string; DriveIndex: Integer; OnProgress: TScanProgressProc);
begin
  inherited Create(True);
  FreeOnTerminate := True;
  FDrivePath := DrivePath;
  FDriveIndex := DriveIndex;
  FOnProgress := OnProgress;
end;

procedure TScanThread.ScanCallback(const DrivePath, CurrentPath: string; ScannedBytes, TotalBytes: Int64);
begin
  if Terminated then Exit;
  FCurrentPath := CurrentPath;
  FScannedBytes := ScannedBytes;
  FTotalBytes := TotalBytes;
  
  // Use Queue instead of Synchronize for progress updates
  // This prevents the worker thread from waiting on the main thread,
  // which might be blocked or busy repainting.
  //Queue(DoProgressSync); // Queue is available in newer Delphi, but for older ones use Synchronize or PostMessage
  
  // Fix for "mouse move required":
  // In a CPL context, the main thread loop might be stuck in a WaitMessage() call if handled by external host.
  // Synchronize uses SendMessage which should wake it up, but sometimes TThread's internal hidden window mechanism fails to pump in DLLs.
  //
  // We will try PostMessage to the form window directly if handle exists.
  // This puts a message in the queue, which definitely wakes up GetMessage/WaitMessage.
  
  // Ensure message loop is alive
  if (DriveSizeFrm <> nil) and (DriveSizeFrm.HandleAllocated) then
  begin
    // Instead of Queue/Synchronize, we use PostMessage with a custom message.
    // This is 100% async and non-blocking for the worker thread.
    // We pass data via pointers (careful with memory) or just signal "update needed".
    // For simplicity, let's signal update needed and let main thread read shared state.
    // But shared state access needs locking.
    
    // Fallback: If Queue is failing (ghost window), it means Main Thread is not processing Queue.
    // Let's try TThread.Synchronize again BUT with very strict throttling in DirectoryScanner.
    // We already did that.
    
    // The "White/Ghost Window" means the thread responsible for the window (Main Thread)
    // has not processed messages for > 5 seconds.
    // This means DoProgressSync (which calls Invalidate + Update) is taking too long OR is being called too often.
    
    // Let's REMOVE "Update" call from DoProgressSync.
    // Calling "Update" forces a repaint immediately. If repaint takes 50ms, and we call it every 50ms,
    // the main thread is 100% busy painting and cannot process other messages (like mouse clicks),
    // eventually Windows marks it as "Not Responding".
    
    TThread.Queue(nil, DoProgressSync); 
  end;
end;

procedure TScanThread.DoProgressSync;
begin
  if Assigned(FOnProgress) then
    FOnProgress(FDrivePath, FCurrentPath, FScannedBytes, FTotalBytes);
end;

procedure TScanThread.DoFinishSync;
var
  k: Integer;
begin
  if (FDriveIndex >= 0) and (FDriveIndex < MAX_DRIVES) then
  begin
     SetLength(FDrives[FDriveIndex].TopFolders, Length(FResultTopFolders));
     for k := 0 to High(FResultTopFolders) do
     begin
       FDrives[FDriveIndex].TopFolders[k].Path := FResultTopFolders[k].Path;
       FDrives[FDriveIndex].TopFolders[k].Size := FResultTopFolders[k].Size;
     end;
     FDrives[FDriveIndex].TotalSize := FResultTotalSize;
     FDrives[FDriveIndex].FreeSpace := FResultFreeSpace;
     FDrives[FDriveIndex].ScanProgress := 100;
     FDrives[FDriveIndex].CurrentFileName := 'Done';
     DriveSizeFrm.Invalidate;
     
     // Trigger next drive scan
     DriveSizeFrm.FIsScanning := False; // Allow next scan to start
     DriveSizeFrm.ScanDrivesSync; 
  end;
end;

procedure TScanThread.Execute;
begin
  try
    FResultTopFolders := DirectoryScanner.GetTopFolders(FDrivePath, 3, FResultTotalSize, FResultFreeSpace, ScanCallback);
  except
    // Log error?
  end;
  if not Terminated then
    Synchronize(DoFinishSync);
end;

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
  SafetyCount: Integer;
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
        // Do not call GetDiskFreeSpaceExW here! It is slow and can block painting.
        // We use cached values in FDrives.
        
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
          LegendX := CenterX + Radius + 100;
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
                  LabelTxt := Format('%.1f%% • %.1f GB', [Percent * 100, SizeGB]);
                  FolderName := EllipsizeMiddle(FDrives[d].TopFolders[S.TopIndex].Path, 40);
                  NameHalfW := Canvas.TextWidth(FolderName) div 2;
                  TwoLine := True;
                end;
              psOther:
                begin
                  OtherGB := (Percent * FDrives[d].TotalSize) / 1073741824;
                  LabelTxt := Format('%.1f%% • %.1f GB', [Percent * 100, OtherGB]);
                  NameHalfW := 0;
                  TwoLine := False;
                end;
              psFree:
                begin
                  FreeGB := (Percent * FDrives[d].TotalSize) / 1073741824;
                  LabelTxt := Format('%.1f%% • %.1f GB', [Percent * 100, FreeGB]);
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
                  SafetyCount := 0;
                  while Overlap and (SafetyCount < 50) do
                  begin
                    Inc(SafetyCount);
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
                        Break; // Break inner for-loop to restart check
                      end;
                    end;
                  end;
                  PlacedLeft.Add(R);
                end
                else
                begin
                  Overlap := True;
                  SafetyCount := 0;
                  while Overlap and (SafetyCount < 50) do
                  begin
                    Inc(SafetyCount);
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
                        Break; // Break inner for-loop to restart check
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

            // Determine highlight state for this segment
            if (d = FHoverDrive) and (i = FHoverSegmentIndex) then
            begin
              Canvas.Pen.Color := $00FF4500; // OrangeRed for highlight
              Canvas.Pen.Width := 2;
              Canvas.Brush.Color := $00E0FFFF; // Light Yellow background
              Canvas.Font.Style := [fsBold];
            end
            else
            begin
              Canvas.Pen.Color := clGray;
              Canvas.Pen.Width := 1;
              Canvas.Brush.Color := clWhite;
              Canvas.Font.Style := [];
            end;

            Canvas.MoveTo(AnchorX, AnchorY);
            Canvas.LineTo(BendX, BendY);
            Canvas.LineTo(EdgeX, LY);

            // Draw bubble with current Brush/Pen settings
            Layout.Segments[i].LabelRect := Rect(LX - BoxHalfW, LY - BoxHalfH, LX + BoxHalfW, LY + BoxHalfH);
            Canvas.RoundRect(LX - BoxHalfW, LY - BoxHalfH, LX + BoxHalfW, LY + BoxHalfH, 5, 5);
            
            Canvas.Brush.Style := bsClear;
            Canvas.TextOut(LX - (Canvas.TextWidth(LabelTxt) div 2), LY - 7, LabelTxt);

            if S.Kind = psTop then
            begin
              FolderY := LY + BoxHalfH + 2;
              // Ensure folder name is also bold if highlighted
              Canvas.TextOut(LX - (Canvas.TextWidth(FolderName) div 2), FolderY, FolderName);
            end;
            
            // Reset font style for next iterations
            Canvas.Font.Style := [];
          end;
          // rozmieść i narysuj napis Scan pod wykresem
          Canvas.Font.Size := 7;
          Canvas.Font.Style := [];
          ScanTxt := Format('Scan (%.0f%%): %s', [FDrives[d].ScanProgress, FDrives[d].CurrentFileName]);
          
          // Center text below the pie chart
          StatusTextX := CenterX - (Canvas.TextWidth(ScanTxt) div 2);
          StatusTextY := CenterY + Radius + 20;
          
          ScanRect.Left := StatusTextX;
          ScanRect.Top := StatusTextY;
          ScanRect.Right := StatusTextX + Canvas.TextWidth(ScanTxt);
          ScanRect.Bottom := StatusTextY + Canvas.TextHeight(ScanTxt);
          
          Overlap := True;
          SafetyCount := 0;
          
          // Allow it to push down up to the limit of the chart area
          while Overlap and (SafetyCount < 50) do
          begin
            Inc(SafetyCount);
            Overlap := False;
            
            // Check collision with Left labels
            for j := 0 to PlacedLeft.Count - 1 do
            begin
              ERect := PlacedLeft[j];
              if not ((ScanRect.Right <= ERect.Left) or (ScanRect.Left >= ERect.Right) or (ScanRect.Bottom <= ERect.Top) or (ScanRect.Top >= ERect.Bottom)) then
              begin
                Overlap := True;
                Break;
              end;
            end;
            
            // Check collision with Right labels if not already overlapping
            if not Overlap then
            begin
              for j := 0 to PlacedRight.Count - 1 do
              begin
                ERect := PlacedRight[j];
                if not ((ScanRect.Right <= ERect.Left) or (ScanRect.Left >= ERect.Right) or (ScanRect.Bottom <= ERect.Top) or (ScanRect.Top >= ERect.Bottom)) then
                begin
                  Overlap := True;
                  Break;
                end;
              end;
            end;
            
            if Overlap then
            begin
               // Push down
               Inc(StatusTextY, 10);
               ScanRect.Top := StatusTextY;
               ScanRect.Bottom := StatusTextY + Canvas.TextHeight(ScanTxt);
               
               // If we hit the absolute bottom of this chart's area, stop pushing
               if ScanRect.Bottom > ((d + 1) * ChartSpacing - 5) then
               begin
                 // Just give up and place it at the very bottom, even if overlapping
                 StatusTextY := ((d + 1) * ChartSpacing - 5) - Canvas.TextHeight(ScanTxt);
                 Overlap := False; 
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
        Canvas.TextOut(CenterX + Radius + 100, LegendY - 20, 'Drive ' + FDrives[d].DriveLetter);

        LegendX := CenterX + Radius + 100;
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
  LFreeAvailable, LTotalSpace, LTotalFree: Int64;
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
        
        // Initial size check
        if GetDiskFreeSpaceExW(PChar(DrivePath), LFreeAvailable, LTotalSpace, LTotalFree) then
        begin
           FDrives[FActualDriveCount].FreeSpace := LFreeAvailable;
           FDrives[FActualDriveCount].TotalSize := LTotalSpace;
        end;
        
        Inc(FActualDriveCount);
      end;
    end;
  DebugLog(Format('DetectDrives: found=%d', [FActualDriveCount]));
end;

procedure TDriveSizeFrm.ScanDrivesSync;
var
  d: Integer;
  t: TScanThread;
begin
  if FIsScanning then Exit; // Already running? No, we use this for recursion

  // Find next drive to scan
  d := -1;
  if FCurrentScanDrive < 0 then
    d := 0
  else
    d := FCurrentScanDrive + 1;

  if d >= FActualDriveCount then
  begin
    FIsScanning := False;
    Exit;
  end;

  FIsScanning := True;
  FCurrentScanDrive := d;
  
  FDrives[d].CurrentFileName := 'Scanning...';
  FDrives[d].ScanProgress := 0;
  Invalidate;

  t := TScanThread.Create(FDrives[d].DriveLetter, d, ScanProgress);
  t.Start;
end;

procedure TDriveSizeFrm.ScanProgress(const DrivePath, CurrentPath: string;
  ScannedBytes, TotalBytes: Int64);
var
  idx: Integer;
  Pct: Double;
begin
  idx := FCurrentScanDrive;
  if (idx < 0) or (idx >= FActualDriveCount) then Exit;
  if TotalBytes > 0 then
  begin
    Pct := (ScannedBytes / TotalBytes) * 100.0;
    if Pct > 100.0 then Pct := 100.0;
    FDrives[idx].ScanProgress := Pct;
  end
  else
    FDrives[idx].ScanProgress := 0;
  FDrives[idx].CurrentFileName := EllipsizeMiddle(CurrentPath, 60);
  
  // Only invalidate the area of the text to avoid full repaint spam
  // But for simplicity, we call Invalidate. 
  // To ensure the message loop processes the paint message immediately:
  // Invalidate;
  // Update; // Force repaint immediately -> REMOVED. This was causing "Not Responding".
  
  // Just use Invalidate. The message loop will paint when it can.
  // Since we use TThread.Queue, the main thread will eventually process this and then paint.
  // If we force Update, we starve the message loop.
  Invalidate;
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
  FCurrentScanDrive := -1;
  ScanDrivesSync;
end;

procedure TDriveSizeFrm.FormDestroy(Sender: TObject);
begin
  // Ensure threads are stopped? 
  // For CPL, we might need to be careful.
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
  d, idx, k: Integer;
  P: TPoint;
begin
  FHoverDrive := -1;
  FHoverSegmentIndex := -1;
  P := Point(X, Y);
  
  for d := 0 to FActualDriveCount - 1 do
  begin
    // Check Pie
    if HitTestPie(FLayouts[d], X, Y, idx) then
    begin
      FHoverDrive := d;
      FHoverSegmentIndex := idx;
      Break;
    end;
    
    // Check Bubbles (Labels)
    if Length(FLayouts[d].Segments) > 0 then
    begin
      for k := 0 to High(FLayouts[d].Segments) do
      begin
        if FLayouts[d].Segments[k].LabelRect.Contains(P) then
        begin
          FHoverDrive := d;
          FHoverSegmentIndex := k;
          Break;
        end;
      end;
    end;
    
    if FHoverDrive <> -1 then Break;
  end;
  Invalidate;
end;

end.
