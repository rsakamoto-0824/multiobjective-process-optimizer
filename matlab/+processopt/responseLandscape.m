function view=responseLandscape(cfg,bundle,anchor,pair,gridSize,mode)
%RESPONSELANDSCAPE Conditional profiles and an explicitly fixed two-factor slice.
% Profiles describe model behavior, not causal effects or global importance.
if nargin<6, mode='nominal'; end
if nargin<5, gridSize=31; end
if nargin<4, pair=[1,min(2,height(cfg.Factors))]; end
cfg=processopt.validateConfig(cfg); p=height(cfg.Factors);
anchor=reshape(anchor,1,[]);
assert(numel(anchor)==p && isreal(anchor) && all(isfinite(anchor)) && ...
    all(anchor>=cfg.Factors.Min' & anchor<=cfg.Factors.Max'),'固定値は因子の設定範囲内にしてください。');
assert(isscalar(gridSize) && gridSize==floor(gridSize) && gridSize>=11 && gridSize<=61,'平面の格子数は11〜61です。');
assert(ismember(mode,{'nominal','scenarios'}),'未対応の表示モードです。');
if bundle.LatinLevels>0
    processopt.features(processopt.scale(anchor,cfg,'code'),'linear',bundle.LatinLevels);
    assert(all(cfg.Factors.JitterStd(1:2)==0),'ラテン方格の行・列ブロックには条件変動を指定できません。');
end
if strcmp(mode,'scenarios'), offsets=processopt.scenarios(cfg);
else, offsets=zeros(1,p); end
calibrationNote='';
try
    processopt.desirability(cfg,zeros(1,height(cfg.Responses)));
catch problem
    if startsWith(problem.identifier,'processopt:Desirability')
        calibrationNote=problem.message;
    else
        rethrow(problem);
    end
end
profilePoints=61;
profiles=cell(1,p); ranges=zeros(p,height(cfg.Responses));
for j=1:p
    values=axisValues(j,profilePoints); X=repmat(anchor,numel(values),1); X(:,j)=values(:);
    profiles{j}=evaluateView(X); profiles{j}.X=values;
    ranges(j,:)=max(profiles{j}.Prediction,[],1)-min(profiles{j}.Prediction,[],1);
end
plane=[];
if p>=2
    assert(isnumeric(pair) && numel(pair)==2 && all(pair==floor(pair)) && ...
        all(pair>=1 & pair<=p) && pair(1)~=pair(2),'横軸・縦軸は異なる因子を選んでください。');
    horizontal=axisValues(pair(1),gridSize); vertical=axisValues(pair(2),gridSize);
    [xx,yy]=meshgrid(horizontal,vertical);
    X=repmat(anchor,numel(xx),1); X(:,pair(1))=xx(:); X(:,pair(2))=yy(:);
    plane=evaluateView(X); plane.XValues=horizontal; plane.YValues=vertical; plane.Pair=pair;
    plane.Prediction=reshape(plane.Prediction,numel(vertical),numel(horizontal),[]);
    plane.Satisfaction=reshape(plane.Satisfaction,numel(vertical),numel(horizontal),[]);
    plane.Overall=reshape(plane.Overall,size(xx)); plane.Feasible=reshape(plane.Feasible,size(xx));
end
view=struct('Profiles',{profiles},'Ranges',ranges,'Plane',plane,'Anchor',anchor, ...
    'Mode',mode,'ScenarioCount',size(offsets,1),'CalibrationNote',calibrationNote, ...
    'Config',cfg);

    function values=axisValues(j,count)
        if bundle.LatinLevels>0 && j<=2, count=bundle.LatinLevels; end
        values=linspace(cfg.Factors.Min(j),cfg.Factors.Max(j),count);
    end
    function out=evaluateView(X)
        [ev,samples]=processopt.evaluate(cfg,X,@predictBatches,offsets);
        n=size(X,1); m=height(cfg.Responses); s=size(offsets,1);
        if isempty(calibrationNote)
            [score,total]=processopt.desirability(cfg,reshape(samples,n*s,m));
            score=reshape(mean(reshape(score,n,s,m),2),n,m);
            total=mean(reshape(total,n,s),2);
        else
            score=nan(n,m); total=nan(n,1);
        end
        out=struct('Prediction',ev.Prediction,'Satisfaction',score, ...
            'Overall',total,'Feasible',ev.Feasible);
    end
    function Y=predictBatches(X)
        batchSize=1024; Y=zeros(size(X,1),height(cfg.Responses));
        for first=1:batchSize:size(X,1)
            rows=first:min(first+batchSize-1,size(X,1));
            Y(rows,:)=processopt.predictModels(bundle,X(rows,:));
        end
    end
end
