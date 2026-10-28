function plan = makeDesign(cfg)
%MAKEDESIGN Finite candidate D/I exchange, conference DSD, LHS or Latin square.
cfg=processopt.validateConfig(cfg);
old=rng; cleanup=onCleanup(@()rng(old)); %#ok<NASGU>
rng(cfg.Seed,'twister');
p=height(cfg.Factors); n=cfg.Design.Runs; blocks=[];
switch cfg.Design.Method
    case 'Latin hypercube'
        z=2*processopt.latinHypercube(n,p)-1;
    case 'Latin square'
        assert(p==3,'ラテン方格は因子を3つ（行ブロック、列ブロック、処理）にしてください。');
        levels=cfg.Design.LatinLevels;
        [row,col]=ndgrid(1:levels,1:levels);
        rp=randperm(levels); cp=randperm(levels); tp=randperm(levels);
        treatment=tp(mod(rp(row(:))+cp(col(:))-2,levels)+1);
        blocks=[row(:),col(:),treatment(:)];
        z=2*(blocks-1)/(levels-1)-1;
    case 'DSD'
        % Symmetric Paley conference matrices for prime q = 1 mod 4.
        primesQ=[5,13,17,29,37]; q=primesQ(find(primesQ+1>=p,1));
        residues=mod((1:q-1).^2,q); Q=zeros(q);
        for j=1:q
            for k=1:q
                if j~=k, Q(j,k)=2*ismember(mod(j-k,q),residues)-1; end
            end
        end
        C=[0,ones(1,q);ones(q,1),Q];
        assert(norm(C'*C-q*eye(q+1),'fro')<1e-10,'Conference行列の直交性が不正です。');
        C=C(:,1:p); z=[C;-C;zeros(1,p)];
    otherwise
        z=exchangeDesign(cfg,p,n);
end
order=randperm(size(z,1)); z=z(order,:);
X=processopt.scale(z,cfg,'physical');
T=array2table(X,'VariableNames',cellstr(string(cfg.Factors.Name)));
T=addvars(T,(1:size(X,1))','Before',1,'NewVariableNames','RunID');
if ~isempty(blocks)
    blocks=blocks(order,:);
    T.RowBlock=blocks(:,1); T.ColumnBlock=blocks(:,2); T.Treatment=blocks(:,3);
end
latinLevels=0;
if strcmp(cfg.Design.Method,'Latin square'), latinLevels=cfg.Design.LatinLevels; end
F=processopt.features(z,cfg.Design.Basis,latinLevels);
plan=struct('X',X,'Table',T,'Rank',rank(F),'Terms',size(F,2), ...
    'Condition',cond(F),'Method',cfg.Design.Method,'Seed',cfg.Seed);
end

function bestZ=exchangeDesign(cfg,p,n)
integrationCount=1500;
maximumExchangeCandidates=100;
count=max(cfg.Design.Candidates,n);
candidates=2*processopt.latinHypercube(count,p)-1;
candidates=[candidates;randi(3,count,p)-2;zeros(1,p)];
candidates=unique(candidates,'rows','stable');
F=processopt.basis(candidates,cfg.Design.Basis); k=size(F,2);
assert(n>=k+2,'この回帰項には最低%d実験（項数%d+残差自由度2）が必要です。',k+2,k);
assert(n<=size(F,1),'候補点数を増やしてください。');
integration=processopt.basis(2*processopt.latinHypercube(integrationCount,p)-1,cfg.Design.Basis);
moment=(integration'*integration)/size(integration,1);
bestScore=Inf;
for restart=1:cfg.Design.Restarts
    shuffle=randperm(size(F,1));
    [~,~,pivot]=qr(F(shuffle,:)','vector');
    selected=shuffle(pivot(1:k));
    others=setdiff(1:size(F,1),selected); others=others(randperm(numel(others)));
    selected=[selected,others(1:n-k)];
    A=F(selected,:); score=criterion(A'*A,moment,cfg.Design.Method);
    for pass=1:cfg.Design.Passes
        improved=false;
        for row=randperm(n)
            choices=setdiff(1:size(F,1),selected);
            choices=choices(randperm(numel(choices),min(maximumExchangeCandidates,numel(choices))));
            base=A'*A-A(row,:)'*A(row,:); winner=0;
            for candidate=choices
                trial=criterion(base+F(candidate,:)'*F(candidate,:),moment,cfg.Design.Method);
                if trial < score-1e-9
                    score=trial; winner=candidate;
                end
            end
            if winner>0
                selected(row)=winner; A(row,:)=F(winner,:); improved=true;
            end
        end
        if ~improved, break; end
    end
    if score<bestScore, bestScore=score; bestZ=candidates(selected,:); end
end
assert(isfinite(bestScore),'指定した回帰項を推定できる計画を作れませんでした。');
end

function value=criterion(M,B,method)
[R,failed]=chol((M+M')/2);
if failed || rcond(M)<1e-12, value=Inf; return; end
if strcmp(method,'D-optimal')
    value=-2*sum(log(diag(R)));
else
    value=trace(R\(R'\B));
end
end
