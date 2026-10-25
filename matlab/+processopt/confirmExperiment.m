function report=confirmExperiment(cfg,bundle,result,selected,T,layout)
%CONFIRMEXPERIMENT Independent measured baseline/candidate wafers, no truth formula.
assert(~isempty(selected),'先に探索候補を選択してください。');
assert(ismember('Role',T.Properties.VariableNames),'追加実験CSVにはRole列（baseline / candidate）が必要です。');
roles=lower(strtrim(string(T.Role)));
assert(all(ismember(roles,["baseline","candidate"])) && all(ismember(["baseline","candidate"],roles)), ...
    'Roleはbaseline / candidateの両方を含めてください。');
points=[cfg.Factors.Current';result.X(selected,:)];
measured=cell(1,2); prediction=cell(1,2); losses=cell(1,2); observedFeasible=cell(1,2);
for k=1:2
    labels=["baseline","candidate"]; data=processopt.importData(T(roles==labels(k),:),cfg,layout);
    tolerance=1e-8*max(1,(cfg.Factors.Max-cfg.Factors.Min)');
    assert(all(all(abs(data.X-points(k,:))<=tolerance)), ...
        '%sの因子条件が元条件または選択候補と一致しません。CSVと選択行を確認してください。',labels(k));
    measured{k}=data;
    prediction{k}=processopt.predictModels(bundle,data.X);
    evaluation=processopt.evaluate(cfg,data.X,@(~)data.Y,zeros(1,height(cfg.Factors)));
    losses{k}=evaluation.Objectives; observedFeasible{k}=evaluation.Feasible;
end
A=measured{1}.Y; B=measured{2}.Y; m=size(A,2);
sdA=std(A,0,1); sdB=std(B,0,1);
if size(A,1)==1, sdA(:)=NaN; end
if size(B,1)==1, sdB(:)=NaN; end
allError=[A-prediction{1};B-prediction{2}];
metrics=table(string(cfg.Responses.Name),sqrt(mean(allError.^2,1))', ...
    mean(A-prediction{1},1)',mean(B-prediction{2},1)', ...
    'VariableNames',{'Response','Validation_RMSE','BaselineBias','CandidateBias'});
lossA=mean(losses{1},1)'; lossB=mean(losses{2},1)';
comparison=table(string(cfg.Responses.Name),repmat(size(A,1),m,1),repmat(size(B,1),m,1), ...
    mean(A,1)',mean(B,1)',sdA',sdB',lossA,lossB,lossA-lossB, ...
    'VariableNames',{'Response','BaselineN','CandidateN','MeasuredBaseline','MeasuredCandidate', ...
    'BaselineWaferSD','CandidateWaferSD','BaselineLoss','CandidateLoss','LossImprovement'});
report=struct('Metrics',metrics,'Comparison',comparison,'Data',{measured}, ...
    'ObservedFeasible',{observedFeasible},'Selected',selected, ...
    'BaselineAllFeasible',all(observedFeasible{1}),'CandidateAllFeasible',all(observedFeasible{2}));
end
