function report=verify(cfg,bundle,result,selected)
%VERIFY Independent truth samples, fresh perturbations, paired baseline check.
if nargin<4 || isempty(selected), selected=result.Compromise; end
assert(~isempty(selected) && selected>=1 && selected<=size(result.X,1),'実行可能な候補を選択してください。');
old=rng; cleanup=onCleanup(@()rng(old)); %#ok<NASGU>
rng(mod(cfg.Seed+100,2^32),'twister');
z=2*processopt.latinHypercube(cfg.Optimization.ValidationPoints,height(cfg.Factors))-1;
if bundle.LatinLevels>0
    z(:,1:2)=2*(randi(bundle.LatinLevels,size(z,1),2)-1)/(bundle.LatinLevels-1)-1;
end
X=processopt.scale(z,cfg,'physical');
truth=@(x)processopt.simulate(cfg,x,false);
Ytrue=truth(X); Ypred=processopt.predictModels(bundle,X);
delta=Ypred-Ytrue;
metrics=table(string(cfg.Responses.Name),sqrt(mean(delta.^2,1))',mean(abs(delta),1)',max(abs(delta),[],1)', ...
    'VariableNames',{'Response','Truth_RMSE','Truth_MAE','Truth_MaxError'});
points=[cfg.Factors.Current';result.X(selected,:)];
% Use more fresh scenarios than in the search to expose optimization overfit.
fresh=cfg; fresh.Optimization.Scenarios=min(128,max(64,4*cfg.Optimization.Scenarios));
offsets=processopt.scenarios(fresh,cfg.Seed+101);
pred=processopt.evaluate(cfg,points,@(x)processopt.predictModels(bundle,x),offsets);
actual=processopt.evaluate(cfg,points,truth,offsets);
names=string(cfg.Responses.Name);
comparison=table(names,pred.Prediction(1,:)',pred.Prediction(2,:)', ...
    actual.Prediction(1,:)',actual.Prediction(2,:)', ...
    actual.ResponseSD(1,:)',actual.ResponseSD(2,:)', ...
    actual.Objectives(1,:)',actual.Objectives(2,:)', ...
    (actual.Objectives(1,:)-actual.Objectives(2,:))', ...
    'VariableNames',{'Response','PredictedBaseline','PredictedCandidate', ...
    'TrueBaseline','TrueCandidate','BaselineSD','CandidateSD', ...
    'BaselineLoss','CandidateLoss','LossImprovement'});
frontTruth=processopt.evaluate(cfg,result.X,truth,offsets);
[rankValue,~]=processopt.rankPopulation(frontTruth.Objectives,frontTruth.Violation);
report=struct('Metrics',metrics,'X',X,'Truth',Ytrue,'Prediction',Ypred, ...
    'Comparison',comparison,'Predicted',pred,'Actual',actual,'FrontTruth',frontTruth, ...
    'TrueNondominated',rankValue==1 & frontTruth.Feasible,'Selected',selected, ...
    'ScenarioCount',size(offsets,1),'Seed',cfg.Seed+100);
end
