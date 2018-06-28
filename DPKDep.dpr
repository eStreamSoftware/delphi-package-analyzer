program DPKDep;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.IOUtils,
  DPKAnalyzer in 'DPKAnalyzer.pas';

procedure CheckParameters;
begin
  if ParamCount <> 2 then begin
    WriteLn('RAD Studio package depdendencies analyzer');
    WriteLn('Syntax: ', ExtractFileName(ParamStr(0)), ' LibraryNames PackageFiles');
    WriteLn('        ', 'Both LibraryNames and PackageFiles are separated by semicolon');
    Halt(1);
  end;
end;

var s, t: string;

begin
  ReportMemoryLeaksOnShutdown := True;
  CheckParameters;

  // Declare two variables to hold ParamStr(n) to avoid unexpected memory leak
  s := ParamStr(1);
  t := ParamStr(2);
  if not TFile.Exists(t) or not TPath.GetExtension(t).ToLower.Equals('.dpk') then
    t := TFile.ReadAllText(t, TEncoding.UTF8);

  WriteLn(TDelphiDPKAnalyzer.ConstructBuildSequence(s.Split([';']), t.Split([';'])));
end.
