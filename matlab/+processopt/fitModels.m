function [bundle,diagnostic] = fitModels(cfg,data,progress)
%FITMODELS Grouped out-of-fold validation; no training predictions as CV.
if nargin<3, progress=@(~)[]; end
cfg=processopt.validateConfig(cfg);
cfg.Model.LatinLevels=0;
if isfield(data,'DesignMethod') && strcmp(data.DesignMethod,'Latin square')
    cfg.Model.LatinLevels=data.LatinLevels;
end
X=data.X; Y=data.Y;
assert(size(X,1)==size(Y,1) && size(X,2)==height(cfg.Factors) && size(Y,2)==height(cfg.Responses),'学習データと設定の列数が一致しません。');
assert(isreal(X) && isreal(Y) && all(isfinite([X(:);Y(:)])),'欠測・非有限値を修正してください。');
assert(all(all(X>=cfg.Factors.Min' & X<=cfg.Factors.Max')),'学習条件が因子範囲外です。');
[~,~,groups]=unique(X,'rows');
groupIDs=unique(groups); folds=min(cfg.Model.Folds,numel(groupIDs));
assert(folds>=2,'交差検証に異なる条件が2つ以上必要です。');
old=rng; cleanup=onCleanup(@()rng(old)); %#ok<NASGU>
rng(mod(cfg.Seed+2,2^32),'twister');
assignment=zeros(size(groupIDs));
assignment(randperm(numel(groupIDs)))=mod(0:numel(groupIDs)-1,folds)+1;
foldID=assignment(groups);
z=processopt.scale(X,cfg,'code');
m=size(Y,2); oof=nan(size(Y)); predictiveSD=nan(size(Y));
models=cell(1,m); training=zeros(size(Y)); coefficients=cell(1,m);
for j=1:m
    progress(sprintf('応答 %d/%d: 交差検証',j,m));
    for k=1:folds
        train=foldID~=k; test=~train;
        mdl=trainOne(z(train,:),Y(train,j),cfg);
        [oof(test,j),predictiveSD(test,j)]=predictOne(mdl,z(test,:));
    end
    models{j}=trainOne(z,Y(:,j),cfg);
    [training(:,j),~]=predictOne(models{j},z);
    if strcmp(models{j}.Method,'Polynomial')
        [~,names]=processopt.features(z,cfg.Model.Basis,cfg.Model.LatinLevels);
        coefficients{j}=table(names',models{j}.Beta,'VariableNames',{'Term','Coefficient'});
    end
end
errorValue=Y-oof; mse=mean(errorValue.^2,1); total=sum((Y-mean(Y,1)).^2,1);
r2=1-sum(errorValue.^2,1)./total; r2(total<=eps(max(1,max(abs(Y),[],1))).^2*size(Y,1))=NaN;
coverage=mean(abs(errorValue)<=1.96*predictiveSD,1);
coverage(all(isnan(predictiveSD),1))=NaN;
metrics=table(string(cfg.Responses.Name),sqrt(mse)',mean(abs(errorValue),1)',r2', ...
    sqrt(mean((Y-training).^2,1))',mean(errorValue,1)',coverage', ...
    'VariableNames',{'Response','CV_RMSE','CV_MAE','CV_R2','Train_RMSE','CV_Bias','CV_Coverage95'});
metrics.GAM_Interactions=nan(m,1);
if strcmp(cfg.Model.Method,'GAM')
    for j=1:m, metrics.GAM_Interactions(j)=size(models{j}.Fit.Interactions,1); end
end
metrics.GPR_Kernel=repmat("",m,1);
if strcmp(cfg.Model.Method,'GPR'), metrics.GPR_Kernel(:)=string(cfg.Model.Kernel); end
bundle=struct('Models',{models},'Factors',cfg.Factors,'Responses',cfg.Responses, ...
    'Method',cfg.Model.Method,'Basis',cfg.Model.Basis,'LatinLevels',cfg.Model.LatinLevels,'Config',cfg);
diagnostic=struct('Metrics',metrics,'Observed',Y,'OOF',oof,'Residual',errorValue, ...
    'FoldID',foldID,'PredictiveSD',predictiveSD,'Coefficients',{coefficients});
end

function mdl=trainOne(z,y,cfg)
mdl=struct('Method',cfg.Model.Method,'Basis',cfg.Model.Basis,'LatinLevels',cfg.Model.LatinLevels);
categorical=[];
if mdl.LatinLevels>0, categorical=[1,2]; processopt.features(z,'linear',mdl.LatinLevels); end
switch mdl.Method
    case 'Polynomial'
        F=processopt.features(z,cfg.Model.Basis,mdl.LatinLevels); p=size(F,2);
        assert(size(F,1)>p && rank(F)==p,'回帰項%d個を独立に推定できません（検証用の学習部分を含む）。実験を追加するか項を減らしてください。',p);
        assert(cond(F)<1e10,'回帰行列が不安定です。因子条件と回帰項を見直してください。');
        [~,mdl.R]=qr(F,0); mdl.Beta=F\y;
        mdl.Variance=sum((y-F*mdl.Beta).^2)/(size(F,1)-p);
    case 'GPR'
        assert(exist('fitrgp','file')==2,'Statistics and Machine Learning Toolboxが必要です。');
        mdl.Fit=fitrgp(z,y,'KernelFunction',cfg.Model.Kernel, ...
            'BasisFunction','constant','Standardize',true,'FitMethod','exact','PredictMethod','exact', ...
            'CategoricalPredictors',categorical);
    case 'GAM'
        assert(exist('fitrgam','file')==2,'Statistics and Machine Learning Toolboxが必要です。');
        interactions=0;
        if cfg.Model.Interactions && size(z,2)>1, interactions='all'; end
        mdl.Fit=fitrgam(z,y,'Interactions',interactions, ...
            'NumTreesPerPredictor',100,'NumTreesPerInteraction',50,'CategoricalPredictors',categorical);
end
end

function [y,sd]=predictOne(mdl,z)
if strcmp(mdl.Method,'Polynomial')
    F=processopt.features(z,mdl.Basis,mdl.LatinLevels); y=F*mdl.Beta;
    sd=sqrt(max(0,mdl.Variance*(1+sum((F/mdl.R).^2,2))));
elseif strcmp(mdl.Method,'GPR')
    [y,sd]=predict(mdl.Fit,z);
else
    y=predict(mdl.Fit,z); sd=nan(size(y));
end
end
