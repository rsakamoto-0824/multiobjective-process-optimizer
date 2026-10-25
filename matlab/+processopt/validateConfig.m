function cfg = validateConfig(cfg)
%VALIDATECONFIG Reject ambiguous names, invalid ranges and expensive accidents.
assert(isstruct(cfg) && isscalar(cfg), '設定は構造体で指定してください。');
assert(cfg.Version == 1, '未対応の設定バージョンです。');
% Older project files used a fixed ARD squared-exponential kernel.
if ~isfield(cfg.Model,'Kernel'), cfg.Model.Kernel='ardsquaredexponential'; end
f = cfg.Factors; r = cfg.Responses;
assert(istable(f) && all(ismember({'Name','Min','Max','JitterStd'},f.Properties.VariableNames)), '因子の列が不足しています。');
assert(istable(r) && all(ismember({'Name','Goal','Target','Scale','Lower','Upper','NoiseStd','Metric','Formula','Signal'},r.Properties.VariableNames)), '応答の列が不足しています。');
assert(height(f)>=1 && height(f)<=12, '因子数は1〜12です。');
assert(height(r)>=1 && height(r)<=12, '応答数は1〜12です。');
names = [string(f.Name);string(r.Name)];
assert(all(strlength(names)>0) && all(cellfun(@isvarname,cellstr(names))), '名前は英字で始まるMATLAB変数名にしてください。');
assert(all(strlength(names)<=40),'名前は40文字以下にしてください。');
assert(numel(unique(lower(names)))==numel(names), '因子名・応答名は重複させないでください。');
reserved = lower(["RunID";"WaferX";"WaferY";"RowBlock";"ColumnBlock";"Treatment";"Role"]);
assert(~any(ismember(lower(names),reserved)), 'RunID、WaferX、WaferY、ブロック列名は予約されています。');
assert(all(isfinite([f.Min;f.Max;f.JitterStd])) && all(f.Min<f.Max) && all(f.JitterStd>=0), '因子の上下限・変動標準偏差を確認してください。');
assert(all(isfinite(f.Max-f.Min)),'因子範囲が大きすぎます。単位を見直してください。');
assert(ismember('Current',f.Properties.VariableNames) && all(isfinite(f.Current)) && all(f.Current>=f.Min & f.Current<=f.Max),'現在条件は因子範囲内にしてください。');
assert(all(isfinite([r.Target;r.Scale;r.NoiseStd])) && all(r.Scale>0) && all(r.NoiseStd>=0), '目標・尺度・ノイズを確認してください。');
assert(all(~isnan([r.Lower;r.Upper])) && all(r.Lower<r.Upper), '応答の下限は上限より小さくしてください。');
assert(all(ismember(string(r.Goal),["target","min","max"])), '目的はtarget / min / maxです。');
assert(all(ismember(string(r.Metric),["mean","std","cv","nu","rms","range"])), '未対応の面内集約指標です。');
assert(all(strlength(string(r.Formula))>0), '真のモデル式を入力してください。');
assert(all(cellfun(@isvarname,cellstr(string(r.Signal)))),'信号名はMATLAB変数名にしてください。');
assert(~any(ismember(lower(string(r.Signal)),[reserved;lower(string(f.Name))])), ...
    'Signalに因子名・予約された列名は使えません。');
for j=1:height(r)
    same=find(strcmp(string(r.Signal),string(r.Signal(j))));
    assert(all(strcmp(string(r.Formula(same)),string(r.Formula(j)))) && ...
        all(r.NoiseStd(same)==r.NoiseStd(j)), '同じSignalは真の式とノイズを共通にしてください。');
end
integer(cfg.Seed,0,2^32-1,'乱数シード');
integer(cfg.Design.Runs,3,1000,'実験数');
integer(cfg.Design.LatinLevels,2,20,'ラテン方格の水準数');
integer(cfg.Design.Restarts,1,10,'計画の再試行数');
integer(cfg.Design.Passes,1,10,'交換回数');
integer(cfg.Design.Candidates,20,2000,'候補数');
assert(ismember(cfg.Design.Method,{'D-optimal','I-optimal','DSD','Latin hypercube','Latin square'}),'未対応の計画です。');
assert(ismember(cfg.Model.Method,{'Polynomial','GPR','GAM'}),'未対応のモデルです。');
assert(ismember(cfg.Model.Kernel,processopt.gprKernels()),'未対応のGPRカーネルです。');
bases = {'linear','interaction','purequadratic','quadratic'};
assert(ismember(cfg.Design.Basis,bases) && ismember(cfg.Model.Basis,bases),'未対応の回帰項です。');
integer(cfg.Model.Folds,2,10,'交差検証の分割数');
assert(isscalar(cfg.Model.Interactions) && ismember(cfg.Model.Interactions,[0,1]),'交互作用の設定を確認してください。');
o = cfg.Optimization;
integer(o.Population,12,300,'集団数'); integer(o.Generations,1,300,'世代数');
integer(o.Scenarios,1,128,'変動シナリオ数');
integer(o.ValidationPoints,20,2000,'独立検証点数');
assert(isscalar(o.RiskWeight) && isfinite(o.RiskWeight) && o.RiskWeight>=0,'リスク重みは0以上です。');
integer(cfg.Wafer.GridSize,3,31,'Wafer格子数');
end

function integer(value,lo,hi,label)
assert(isnumeric(value) && isscalar(value) && isfinite(value) && ...
    value==floor(value) && value>=lo && value<=hi, ...
    '%sは%d〜%dの整数です。',label,lo,hi);
end
