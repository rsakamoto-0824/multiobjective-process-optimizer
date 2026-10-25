function [evaluation,response]=evaluate(cfg,X,predictor,offsets)
%EVALUATE Expected scaled loss + riskWeight*loss SD, with worst scenario bounds.
if nargin<4, offsets=processopt.scenarios(cfg); end
n=size(X,1); s=size(offsets,1); m=height(cfg.Responses);
allX=repmat(X,s,1)+kron(offsets,ones(n,1));
predicted=predictor(allX);
assert(isequal(size(predicted),[n*s,m]) && isreal(predicted) && all(isfinite(predicted(:))),'予測器の出力が不正です。');
response=reshape(predicted,n,s,m); loss=zeros(n,s,m); violation=zeros(n,s);
for j=1:m
    value=response(:,:,j); scale=cfg.Responses.Scale(j);
    switch cfg.Responses.Goal{j}
        case 'target', loss(:,:,j)=abs(value-cfg.Responses.Target(j))/scale;
        case 'min', loss(:,:,j)=value/scale;
        case 'max', loss(:,:,j)=-value/scale;
    end
    violation=violation+max(0,(cfg.Responses.Lower(j)-value)/scale) ...
        +max(0,(value-cfg.Responses.Upper(j))/scale);
end
span=(cfg.Factors.Max-cfg.Factors.Min)';
outside=sum(max(0,(cfg.Factors.Min'-allX)./span)+max(0,(allX-cfg.Factors.Max')./span),2);
violation=violation+reshape(outside,n,s);
evaluation=struct('Objectives',reshape(mean(loss,2)+cfg.Optimization.RiskWeight*std(loss,0,2),n,m), ...
    'Prediction',reshape(mean(response,2),n,m),'ResponseSD',reshape(std(response,0,2),n,m), ...
    'Violation',max(violation,[],2));
evaluation.Feasible=evaluation.Violation<=1e-9;
end
