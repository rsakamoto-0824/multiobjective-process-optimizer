function [Y,SD]=predictModels(bundle,X)
%PREDICTMODELS Use only scaling learned/configured with the fitted model.
cfg=struct('Factors',bundle.Factors); z=processopt.scale(X,cfg,'code');
assert(size(X,2)==height(bundle.Factors) && all(isfinite(X(:))),'予測する因子の列数・値が不正です。');
if bundle.LatinLevels>0, processopt.features(z,'linear',bundle.LatinLevels); end
Y=zeros(size(X,1),numel(bundle.Models)); SD=nan(size(Y));
for j=1:numel(bundle.Models)
    mdl=bundle.Models{j};
    if strcmp(mdl.Method,'Polynomial')
        F=processopt.features(z,mdl.Basis,mdl.LatinLevels); Y(:,j)=F*mdl.Beta;
        if nargout>1, SD(:,j)=sqrt(max(0,mdl.Variance*(1+sum((F/mdl.R).^2,2)))); end
    elseif strcmp(mdl.Method,'GPR')
        if nargout>1
            [Y(:,j),SD(:,j)]=predict(mdl.Fit,z);
        else
            Y(:,j)=predict(mdl.Fit,z);
        end
    else
        Y(:,j)=predict(mdl.Fit,z);
    end
end
assert(isreal(Y) && all(isfinite(Y(:))),'モデル予測に非有限値があります。');
end
