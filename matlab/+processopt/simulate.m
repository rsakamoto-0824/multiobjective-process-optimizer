function [Y,wafer]=simulate(cfg,X,addNoise,seed)
%SIMULATE Synthetic wafer measurements; same Signal shares measured samples.
if nargin<3, addNoise=false; end
if nargin<4, seed=cfg.Seed+1; end
assert(size(X,2)==height(cfg.Factors) && all(isfinite(X(:))),'因子データが不正です。');
old=rng; cleanup=onCleanup(@()rng(old)); %#ok<NASGU>
rng(mod(seed,2^32),'twister');
axisValues=linspace(-1,1,cfg.Wafer.GridSize);
[u,v]=meshgrid(axisValues); inside=u.^2+v.^2<=1+1e-12;
u=u(inside)'; v=v(inside)';
m=height(cfg.Responses); Y=zeros(size(X,1),m); raw=cell(1,m);
for j=1:m
    first=find(strcmp(string(cfg.Responses.Signal),string(cfg.Responses.Signal(j))),1);
    if first<j
        raw{j}=raw{first};
    else
        if strcmp(cfg.Responses.Formula{j},'custom')
            raw{j}=processopt.customTruth(X,u,v,cfg.Responses.Signal{j});
        else
            raw{j}=processopt.expression(cfg.Responses.Formula{j},X,u,v);
        end
        if addNoise, raw{j}=raw{j}+cfg.Responses.NoiseStd(j)*randn(size(raw{j})); end
    end
    Y(:,j)=processopt.aggregate(raw{j},cfg.Responses.Metric{j});
end
wafer=struct('U',u,'V',v,'Values',{raw});
end
