function result=optimize(cfg,bundle,data,progress,cancelled)
%OPTIMIZE NSGA-II environmental selection with blend crossover/Gaussian mutation.
if nargin<4, progress=@(~)[]; end
if nargin<5, cancelled=@()false; end
cfg=processopt.validateConfig(cfg); old=rng; cleanup=onCleanup(@()rng(old)); %#ok<NASGU>
rng(mod(cfg.Seed+4,2^32),'twister');
o=cfg.Optimization; n=o.Population; p=height(cfg.Factors);
blocked=bundle.LatinLevels>0; current=processopt.scale(cfg.Factors.Current',cfg,'code');
if blocked
    processopt.features(current,'linear',bundle.LatinLevels);
    assert(all(cfg.Factors.JitterStd(1:2)==0),'ラテン方格の行・列ブロックに条件変動を指定できません。');
end
z=2*processopt.latinHypercube(n,p)-1;
z(1,:)=processopt.scale(cfg.Factors.Current',cfg,'code');
if ~isempty(data)
    count=min(floor(n/3),size(data.X,1));
    z(2:count+1,:)=processopt.scale(data.X(1:count,:),cfg,'code');
end
if blocked, z(:,1:2)=repmat(current(1:2),n,1); end
offsets=processopt.scenarios(cfg); predictor=@(x)processopt.predictModels(bundle,x);
ev=processopt.evaluate(cfg,processopt.scale(z,cfg,'physical'),predictor,offsets);
history=zeros(o.Generations,3); stopped=false;
for generation=1:o.Generations
    if cancelled(), stopped=true; break; end
    [rankValue,crowd]=processopt.rankPopulation(ev.Objectives,ev.Violation);
    children=zeros(n,p);
    for j=1:n
        a=tournament(rankValue,crowd); b=tournament(rankValue,crowd);
        blend=-0.15+1.3*rand(1,p);
        child=blend.*z(a,:)+(1-blend).*z(b,:);
        mutated=rand(1,p)<1/p;
        mutationSD=0.04+0.25*(1-generation/o.Generations);
        child=child+mutated.*randn(1,p)*mutationSD;
        children(j,:)=max(-1,min(1,child));
    end
    if blocked, children(:,1:2)=repmat(current(1:2),n,1); end
    combined=[z;children];
    allEv=processopt.evaluate(cfg,processopt.scale(combined,cfg,'physical'),predictor,offsets);
    [rankValue,crowd]=processopt.rankPopulation(allEv.Objectives,allEv.Violation);
    [~,order]=sortrows([rankValue,-crowd],[1,2]); selected=order(1:n);
    z=combined(selected,:); ev=subset(allEv,selected);
    history(generation,:)=[generation,sum(ev.Feasible),min(ev.Violation)];
    progress(sprintf('世代 %d/%d、実行可能 %d/%d',generation,o.Generations,sum(ev.Feasible),n));
end
[rankValue,~]=processopt.rankPopulation(ev.Objectives,ev.Violation);
indices=find(rankValue==1 & ev.Feasible);
X=processopt.scale(z(indices,:),cfg,'physical');
[X,uniqueID]=unique(X,'rows','stable'); indices=indices(uniqueID);
front=subset(ev,indices);
compromise=[];
if ~isempty(indices)
    ideal=min(front.Objectives,[],1); span=max(front.Objectives,[],1)-ideal;
    span(span<1e-12)=1;
    [~,compromise]=min(sum(((front.Objectives-ideal)./span).^2,2));
end
result=struct('X',X,'Evaluation',front,'Compromise',compromise, ...
    'History',history(history(:,1)>0,:),'Cancelled',stopped,'Offsets',offsets, ...
    'PopulationX',processopt.scale(z,cfg,'physical'),'PopulationEvaluation',ev, ...
    'Config',cfg);
end

function chosen=tournament(rankValue,crowding)
ids=randi(numel(rankValue),1,2);
if rankValue(ids(1))<rankValue(ids(2)) || ...
        (rankValue(ids(1))==rankValue(ids(2)) && crowding(ids(1))>crowding(ids(2)))
    chosen=ids(1);
else
    chosen=ids(2);
end
end

function out=subset(in,rows)
out=in; names=fieldnames(in);
for j=1:numel(names), out.(names{j})=in.(names{j})(rows,:); end
end
