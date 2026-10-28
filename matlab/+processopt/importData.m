function data=importData(T,cfg,layout)
%IMPORTDATA Explicit wide (aggregated) or long (wafer sites) CSV contract.
cfg=processopt.validateConfig(cfg);
assert(istable(T) && height(T)>0,'CSVにデータ行がありません。');
f=cellstr(string(cfg.Factors.Name)); r=cellstr(string(cfg.Responses.Name));
required=f;
if strcmp(layout,'long')
    required=[required;{'RunID';'WaferX';'WaferY'};cellstr(unique(string(cfg.Responses.Signal),'stable'))];
else
    assert(strcmp(layout,'wide'),'形式はwideまたはlongです。'); required=[required;r];
end
assert(all(ismember(required,T.Properties.VariableNames)), '必要なCSV列: %s',strjoin(required,', '));
numeric=setdiff(required,{'RunID'});
for j=1:numel(numeric)
    a=T.(numeric{j});
    assert(isnumeric(a) && isreal(a) && all(isfinite(a(:))), '列%sに欠測・文字列・非有限値があります。',numeric{j});
end
if strcmp(layout,'wide')
    X=T{:,f}; Y=T{:,r};
else
    ids=string(T.RunID);
    assert(all(~ismissing(ids) & strlength(ids)>0) && ~any(ids=="NaN"),'RunIDに欠測があります。');
    uniqueIDs=unique(ids,'stable'); X=zeros(numel(uniqueIDs),numel(f)); Y=zeros(numel(uniqueIDs),numel(r));
    for k=1:numel(uniqueIDs)
        rows=ids==uniqueIDs(k); localX=T{rows,f};
        assert(all(all(localX==localX(1,:))),'同じRunIDで因子条件が変わっています。');
        xy=T{rows,{'WaferX','WaferY'}};
        assert(size(unique(xy,'rows'),1)==size(xy,1),'同じRunIDに測定位置の重複があります。繰返しWaferはRunIDを分けてください。');
        X(k,:)=localX(1,:);
        for j=1:numel(r)
            Y(k,j)=processopt.aggregate(T{rows,cfg.Responses.Signal{j}}',cfg.Responses.Metric{j});
        end
    end
end
assert(all(all(X>=cfg.Factors.Min' & X<=cfg.Factors.Max')),'設定した因子範囲外のデータがあります。範囲を修正してください。');
[~,~,groups]=unique(X,'rows');
data=struct('X',X,'Y',Y,'Groups',groups,'Source',['CSV-',layout]);
data.DesignMethod=cfg.Design.Method; data.LatinLevels=cfg.Design.LatinLevels;
if strcmp(data.DesignMethod,'Latin square')
    processopt.features(processopt.scale(X,cfg,'code'),'linear',data.LatinLevels);
end
end
