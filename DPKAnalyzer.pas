unit DPKAnalyzer;

interface

uses
  System.Classes, System.Generics.Collections, System.SysUtils;

type
  TPackage = class
  private
    FID: string;
    FIsDesign: Boolean;
    FFileName: string;
    FRequires: TDictionary<string,string>;
    FRequiredBy: TStringList;
    function ExtractRequires(aSource: string; aDefines: TArray<string> = nil):
        TArray<string>;
    function GetFileName: string;
    function GetHasRequires: Boolean;
    function GetIsPriority: Boolean;
    function GetRequiredBy: TArray<string>;
    function GetIsSourceFile: Boolean;
    function ParseDefines_ifdef(var aClause: string; aDefines: TArray<string> =
        nil): Boolean;
    function ParseDefines_else(aClause: string; aCondition: Boolean): string;
    function ParseDefines_IsElse(aClause: string): Boolean;
    function ParseDefines_IsNested(aClause: string): Boolean;
  public
    constructor Create(aFileName: string; aDefines: TArray<string> = nil);
    procedure BeforeDestruction; override;
    procedure AddRequiredBy(aRequiredBy: string);
    procedure RemoveRequire(aRequired: string);
    procedure ForEachRequire(Predicate: TFunc<string,Boolean>; DoAction:
        TProc<TPackage,string>);
    property FileName: string read GetFileName;
    property ID: string read FID;
    property IsDesign: Boolean read FIsDesign;
    property IsPriority: Boolean read GetIsPriority;
    property IsSourceFile: Boolean read GetIsSourceFile;
    property HasRequires: Boolean read GetHasRequires;
    property RequiredBy: TArray<string> read GetRequiredBy;
  end;

  TDelphiDPKAnalyzer = class abstract
  public
    class function ConstructBuildSequence(LibNames, Packages: TArray<string>;
        aDefines: TArray<string> = nil): string;
  end;

implementation

uses
  System.IOUtils, System.RegularExpressions, System.StrUtils;

procedure TPackage.AddRequiredBy(aRequiredBy: string);
begin
  FRequiredBy.Add(aRequiredBy);
end;

procedure TPackage.BeforeDestruction;
begin
  inherited;
  FRequires.Free;
  FRequiredBy.Free;
end;

constructor TPackage.Create(aFileName: string; aDefines: TArray<string> = nil);
var s, Source: string;
    A: TArray<string>;
begin
  FFileName := aFileName;
  FID := TPath.GetFileNameWithoutExtension(FFileName).ToLower;

  FRequires := TDictionary<string,string>.Create;
  if TPath.GetExtension(FFileName).ToLower = '.dpk' then begin
    Source := TFile.ReadAllText(FFileName);
    A := ExtractRequires(Source, aDefines);
    for s in A do begin
      if not FRequires.ContainsKey(s) then
        FRequires.Add(s, '');
    end;
  end;

  FIsDesign := FRequires.ContainsKey('designide') or Source.Contains('{$DESIGNONLY}');

  FRequiredBy := TStringList.Create;
end;

function TPackage.ParseDefines_IsNested(aClause: string): Boolean;
begin
  const re_defs = '(?isU){\$.+}';
  var M := TRegEx.Match(aClause, re_defs);
  var LastDefine := '';
  while M.Success do begin
    if SameText(LastDefine, M.Value) then
      Exit(True);
    LastDefine := M.Value;
  end;

  Result := False;
end;

function TPackage.ParseDefines_IsElse(aClause: string): Boolean;
begin
  const re_defs = '(?isU){\$.+}';
  var M := TRegEx.Match(aClause, re_defs);
  var A: TArray<string> := nil;
  while M.Success do begin
    A := A + [M.Value];
    M := M.NextMatch;
  end;
  Result := (Length(A) = 1) and SameText(A[0], '{$else}');
end;

function TPackage.ParseDefines_else(aClause: string; aCondition: Boolean):
    string;
begin
  const re_else = '(?is)([^{}]*)\{\$else\}([^{}]*)$';

  var M := TRegEx.Match(aClause, re_else);
  if M.Success then begin
    if aCondition then
      Result := M.Groups[1].Value
    else
      Result := M.Groups[2].Value;
  end else
    Result := aClause;
end;

function TPackage.ParseDefines_ifdef(var aClause: string; aDefines:
    TArray<string> = nil): Boolean;
begin
  var Ungreedy := '';
  if ParseDefines_IsNested(aClause) then Ungreedy := 'U';
  const re_ifdef = Format('(?is%s)\{\$ifdef\s+([^{}]*)\}(.*)\{\$endif\}', [Ungreedy]);
  var M := TRegEx.Match(aClause, re_ifdef);
  var s: string;

  Result := M.Success;
  if M.Success then begin
    aClause := aClause.Remove(M.Index - 1, M.Length);
    if ParseDefines_IsElse(M.Groups[2].Value) then
      s := ParseDefines_else(M.Groups[2].Value, MatchText(M.Groups[1].Value, aDefines))
    else if MatchText(M.Groups[1].Value, aDefines) then
      s := M.Groups[2].Value;
    aClause.Insert(M.Index - 1, s);
  end;
end;

function TPackage.ExtractRequires(aSource: string; aDefines: TArray<string> =
    nil): TArray<string>;
var s: string;
    M: TMatch;
begin
  Result := TArray<string>.Create();
  M := TRegEx.Match(aSource, '(?is)requires\s+(.*)\s+contains.*end.');
  if M.Success then begin
    s := M.Groups[1].Value;
    while ParseDefines_ifdef(s, aDefines) do;
    s := TRegEx.Replace(s, '(?isU)\(\*.*\*\)', '');
    s := TRegEx.Replace(s, '(?isU)\{.*\}', '');
    s := s.Replace(#13, '', [rfReplaceAll]);
    s := s.Replace(#10, '', [rfReplaceAll]);
    s := s.Replace(' ', '', [rfReplaceAll]);
    if s.EndsWith(';') then s := s.Remove(s.Length - 1);
    Result := s.ToLower.Split([','], TStringSplitOptions.ExcludeEmpty);
  end;
end;

function TPackage.GetHasRequires: Boolean;
begin
  Result := FRequires.Count > 0;
end;

function TPackage.GetIsSourceFile: Boolean;
begin
  Result := TPath.GetExtension(FileName).ToLower.Equals('.pas');
end;

function TPackage.GetRequiredBy: TArray<string>;
begin
  Result := FRequiredBy.ToStringArray;
end;

procedure TPackage.RemoveRequire(aRequired: string);
begin
  FRequires.Remove(aRequired);
end;

procedure TPackage.ForEachRequire(Predicate: TFunc<string,Boolean>; DoAction:
    TProc<TPackage,string>);
var L, M: TStringList;
    s: string;
begin
  L := TStringList.Create;
  M := TStringList.Create;
  try
    for s in FRequires.Keys do
      if Predicate(s) then
        M.Add(s);

    for s in M do
      DoAction(Self, s);
  finally
    L.Free;
    M.Free;
  end;
end;

function TPackage.GetFileName: string;
begin
  if IsPriority then
    Result := FFileName.Remove(0, 1)
  else
    Result := FFileName;
end;

function TPackage.GetIsPriority: Boolean;
begin
  Result := FFileName.StartsWith('^');
end;

class function TDelphiDPKAnalyzer.ConstructBuildSequence(LibNames, Packages:
    TArray<string>; aDefines: TArray<string> = nil): string;
var A: TArray<string>;
    Libs: TDictionary<string,string>;
    DPKs: TDictionary<string,TPackage>;
    O: TPair<string,TPackage>;
    PrioPASs, PASs: TDictionary<string,TPackage>;
    P: TPackage;
    s: string;
    i, iCount, LastPackageCount: Integer;
    RemoveLibs: TDictionary<string,TPackage>;
    RequiredBys: TList<TPair<string,string>>;
    Outputs: TStringList;
begin
  Libs := TDictionary<string,string>.Create;
  DPKs := TDictionary<string,TPackage>.Create;
  PrioPASs := TDictionary<string,TPackage>.Create;
  PASs := TDictionary<string,TPackage>.Create;
  RemoveLibs := TDictionary<string,TPackage>.Create;
  RequiredBys := TList<TPair<string,string>>.Create;
  Outputs := TStringList.Create;
  try
    for s in LibNames do
      if not Libs.ContainsKey(s.ToLower) then
        Libs.Add(s.ToLower, '');

    for s in Packages do begin
      P := TPackage.Create(s, aDefines);
      P.ForEachRequire(
        function (DCP: string): Boolean
        begin
          Result := Libs.ContainsKey(DCP);
          if not Result then
            RequiredBys.Add(TPair<string,string>.Create(DCP, P.ID));
        end,
        procedure (Q: TPackage; DCP: string)
        begin
          Q.RemoveRequire(DCP);
        end
      );
      if P.IsSourceFile then
        if P.IsPriority then
          PrioPASs.Add(P.FileName, P)
        else
          PASs.Add(P.FileName, P)
      else
        DPKs.Add(P.ID, P);
    end;

    for i := 0 to RequiredBys.Count - 1 do begin
      if DPKs.ContainsKey(RequiredBys[i].Key) then
        DPKs[RequiredBys[i].Key].AddRequiredBy(RequiredBys[i].Value);
    end;

    iCount := 0;

    if PrioPASs.Count > 0 then begin
      Inc(iCount);

      Outputs.Add(
        Format('%d=%s',
          [iCount,
           string.Join(',', PrioPASs.Keys.ToArray).Replace('\', '/', [rfReplaceAll])
          ]
        )
      );

      for P in PrioPASs.Values do
        P.Free;
    end;

    if PASs.Count > 0 then begin
      Inc(iCount);

      Outputs.Add(
        Format('%d=%s',
          [iCount,
           string.Join(',', PASs.Keys.ToArray).Replace('\', '/', [rfReplaceAll])
          ]
        )
      );

      for P in PASs.Values do
        P.Free;
    end;

    LastPackageCount := MaxInt;
    while (DPKs.Count < LastPackageCount) and (DPKs.Count > 0) do begin
      LastPackageCount := DPKs.Count;
      for O in DPKs do begin
        if not O.Value.HasRequires then begin
          s := O.Value.FileName;
          if O.Value.IsDesign then s := '*' + s;
          RemoveLibs.Add(s, O.Value);
          DPKs.Remove(O.Key);
        end;
      end;

      if RemoveLibs.Keys.Count > 0 then begin
        Inc(iCount);
        Outputs.Add(
          Format('%d=%s',
            [iCount,
             string.Join(',', RemoveLibs.Keys.ToArray).Replace('\', '/', [rfReplaceAll])
            ]
          )
        );
      end;

      for P in RemoveLibs.Values do begin
        for s in P.RequiredBy do
          DPKs[s].RemoveRequire(P.ID);
        P.Free;
      end;
      RemoveLibs.Clear;
    end;

    if DPKs.Count > 0 then begin
      Inc(iCount);
      SetLength(A, DPKs.Count);

      i := 0;
      for O in DPKs do begin
        s := O.Value.FileName;
        if O.Value.IsDesign then s := '*' + s;
        O.Value.Free;

        A[i] := s;
        Inc(i);
      end;

      Outputs.Add(
        Format('%d=%s',
          [iCount,
            string.Join(',', A).Replace('\', '/', [rfReplaceAll])
          ]
        )
      );
    end;

    if iCount > 0 then begin
      SetLength(A, iCount);
      for i := 0 to iCount - 1 do
        A[i] := (i + 1).ToString;

      Outputs.Insert(0, 'Index=' + string.Join(',', A));
    end;

    Result := Outputs.Text;
  finally
    Libs.Free;
    DPKs.Free;
    PrioPASs.Free;
    PASs.Free;
    RemoveLibs.Free;
    RequiredBys.Free;
    Outputs.Free;
  end;
end;

end.
