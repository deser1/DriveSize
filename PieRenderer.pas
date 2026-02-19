unit PieRenderer;

interface

uses
  System.Types, System.SysUtils, System.Classes, System.Math, Vcl.Graphics;

type
  TPieSegmentKind = (psTop, psOther, psFree);
  TPieSegment = record
    Kind: TPieSegmentKind;
    TopIndex: Integer; // dla psTop: indeks top folderu, w przeciwnym razie -1
    StartAngle: Double; // w stopniach [0..360)
    EndAngle: Double;   // w stopniach [0..360)
  end;

  TPieChartLayout = record
    CenterX, CenterY: Integer;
    Radius: Integer;
    Segments: TArray<TPieSegment>;
  end;

// Renderuje wykres kołowy dla danego dysku i zwraca układ segmentów do hit-testu.
procedure RenderDrivePie(Canvas: TCanvas; const CenterX, CenterY, Radius: Integer;
  const TotalSize, FreeSpace: Int64; const TopSizes: TArray<Int64>; const Colors: array of TColor;
  out Layout: TPieChartLayout; const HighlightIndex: Integer = -1);

// Sprawdza, czy punkt (X,Y) trafia w któryś z segmentów. Zwraca indeks segmentu.
function HitTestPie(const Layout: TPieChartLayout; const X, Y: Integer; out SegmentIndex: Integer): Boolean;

implementation

procedure AddSegment(var Segs: TArray<TPieSegment>; const Kind: TPieSegmentKind; TopIndex: Integer; StartA, EndA: Double);
var
  S: TPieSegment;
begin
  S.Kind := Kind;
  S.TopIndex := TopIndex;
  S.StartAngle := StartA;
  S.EndAngle := EndA;
  Segs := Segs + [S];
end;

procedure RenderDrivePie(Canvas: TCanvas; const CenterX, CenterY, Radius: Integer;
  const TotalSize, FreeSpace: Int64; const TopSizes: TArray<Int64>; const Colors: array of TColor;
  out Layout: TPieChartLayout; const HighlightIndex: Integer);
var
  StartAngle, EndAngle: Double;
  UsedBytes, TotalUsedInChart: Int64;
  i: Integer;
  UsagePercent, OtherPercent, FreePercent: Double;
  OtherUsedBytes: Int64;
  S: TPieSegment;
begin
  Layout.CenterX := CenterX;
  Layout.CenterY := CenterY;
  Layout.Radius := Radius;
  SetLength(Layout.Segments, 0);

  // Cień
  Canvas.Pen.Style := psClear;
  Canvas.Brush.Color := $DCDCDC;
  Canvas.Ellipse(CenterX - Radius + 5, CenterY - Radius + 5, CenterX + Radius + 5, CenterY + Radius + 5);

  Canvas.Pen.Style := psSolid;
  Canvas.Pen.Color := clWhite;
  Canvas.Pen.Width := 2;

  StartAngle := 0;
  TotalUsedInChart := 0;

  // Top folders
  if (TotalSize > 0) and (Length(TopSizes) > 0) then
  begin
    for i := 0 to High(TopSizes) do
    begin
      UsagePercent := TopSizes[i] / TotalSize;
      if UsagePercent > 0.001 then
      begin
        EndAngle := StartAngle + (UsagePercent * 360);
        Canvas.Brush.Color := Colors[i mod Length(Colors)];
        Canvas.Pie(CenterX - Radius, CenterY - Radius, CenterX + Radius, CenterY + Radius,
                   CenterX + Round(Radius * Cos(StartAngle * Pi / 180)), CenterY - Round(Radius * Sin(StartAngle * Pi / 180)),
                   CenterX + Round(Radius * Cos(EndAngle * Pi / 180)), CenterY - Round(Radius * Sin(EndAngle * Pi / 180)));

        AddSegment(Layout.Segments, psTop, i, StartAngle, EndAngle);
        TotalUsedInChart := TotalUsedInChart + TopSizes[i];
        StartAngle := EndAngle;
      end;
    end;
  end;

  // Other used
  if TotalSize > 0 then
  begin
    UsedBytes := TotalSize - FreeSpace;
    OtherUsedBytes := UsedBytes - TotalUsedInChart;
    if OtherUsedBytes < 0 then OtherUsedBytes := 0;
    
    // Always show 'Other' if it's significant, even if it's small percentage
    // For very small drives or near empty, precision might be an issue.
    // Let's lower the threshold or ensure angle > 0
    
    OtherPercent := OtherUsedBytes / TotalSize;
    if (OtherPercent > 0.001) or (OtherUsedBytes > 1048576) then // Show if > 0.1% or > 1MB
    begin
      EndAngle := StartAngle + (OtherPercent * 360);
      
      // Ensure we don't exceed 360 due to float errors before Free space
      if EndAngle > 360 then EndAngle := 360; 
      
      if EndAngle > StartAngle then
      begin
        Canvas.Brush.Color := $00808080;
        Canvas.Pie(CenterX - Radius, CenterY - Radius, CenterX + Radius, CenterY + Radius,
                   CenterX + Round(Radius * Cos(StartAngle * Pi / 180)), CenterY - Round(Radius * Sin(StartAngle * Pi / 180)),
                   CenterX + Round(Radius * Cos(EndAngle * Pi / 180)), CenterY - Round(Radius * Sin(EndAngle * Pi / 180)));
        AddSegment(Layout.Segments, psOther, -1, StartAngle, EndAngle);
        StartAngle := EndAngle;
      end;
    end;
  end;

  // Free
  if (TotalSize > 0) and (FreeSpace > 0) then
  begin
    FreePercent := FreeSpace / TotalSize;
    if FreePercent > 0.001 then
    begin
      EndAngle := StartAngle + (FreePercent * 360);
      Canvas.Brush.Color := $00E0E0E0;
      Canvas.Pie(CenterX - Radius, CenterY - Radius, CenterX + Radius, CenterY + Radius,
                 CenterX + Round(Radius * Cos(StartAngle * Pi / 180)), CenterY - Round(Radius * Sin(StartAngle * Pi / 180)),
                 CenterX + Round(Radius * Cos(EndAngle * Pi / 180)), CenterY - Round(Radius * Sin(EndAngle * Pi / 180)));
      AddSegment(Layout.Segments, psFree, -1, StartAngle, EndAngle);
    end;
  end;

  // Podświetlenie (obrys) aktualnego segmentu
  if (HighlightIndex >= 0) and (HighlightIndex < Length(Layout.Segments)) then
  begin
    S := Layout.Segments[HighlightIndex];
    Canvas.Pen.Color := clBlack;
    Canvas.Pen.Width := 3;
    Canvas.Brush.Style := bsClear;
    // prosty łuk przez wycinek — obrys po zewnętrznym okręgu
    Canvas.Arc(CenterX - Radius, CenterY - Radius, CenterX + Radius, CenterY + Radius,
               CenterX + Round(Radius * Cos(S.StartAngle * Pi / 180)), CenterY - Round(Radius * Sin(S.StartAngle * Pi / 180)),
               CenterX + Round(Radius * Cos(S.EndAngle * Pi / 180)), CenterY - Round(Radius * Sin(S.EndAngle * Pi / 180)));
  end;
end;

function NormalizeAngle(const A: Double): Double;
begin
  Result := A;
  while Result < 0 do Result := Result + 360;
  while Result >= 360 do Result := Result - 360;
end;

function HitTestPie(const Layout: TPieChartLayout; const X, Y: Integer; out SegmentIndex: Integer): Boolean;
var
  dx, dy: Double;
  dist: Double;
  angle: Double;
  i: Integer;
  S: TPieSegment;
begin
  SegmentIndex := -1;
  Result := False;
  dx := X - Layout.CenterX;
  dy := Layout.CenterY - Y; // odwrócone Y, jak w rysunku
  dist := Sqrt(dx * dx + dy * dy);
  if dist > Layout.Radius then
    Exit(False);
  angle := NormalizeAngle(ArcTan2(dy, dx) * 180 / Pi);
  for i := 0 to High(Layout.Segments) do
  begin
    S := Layout.Segments[i];
    // Segmenty są ułożone bez zawijania przez 0
    if (angle >= S.StartAngle) and (angle <= S.EndAngle) then
    begin
      SegmentIndex := i;
      Exit(True);
    end;
  end;
end;

end.