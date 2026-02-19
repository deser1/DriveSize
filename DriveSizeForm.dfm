object DriveSizeFrm: TDriveSizeFrm
  Left = 0
  Top = 0
  Caption = 'Hard Drive Size Statistic'
  ClientHeight = 479
  ClientWidth = 624
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -12
  Font.Name = 'Segoe UI'
  Font.Style = []
  OnActivate = FormActivate
  OnCreate = FormCreate
  OnPaint = FormPaint
  TextHeight = 15
  object PaintBox1: TPaintBox
    Left = 0
    Top = 8
    Width = 616
    Height = 113
  end
  object Timer1: TTimer
    OnTimer = Timer1Timer
    Left = 536
    Top = 192
  end
end
