function [individual,overall]=desirability(cfg,Y)
%DESIRABILITY Piecewise-linear response scores, equal-weight geometric mean.
% Bounds are fixed settings, never inferred from the displayed grid extrema.
r=cfg.Responses;
assert(size(Y,2)==height(r) && isreal(Y) && all(isfinite(Y(:))), '満足度の応答データが不正です。');
if any(~isfinite([r.Lower;r.Upper]))
    error('processopt:DesirabilityBounds','満足度には全応答の有限のLower/Upperが必要です。設定タブで指定してください。');
end
if any(r.Lower>=r.Upper)
    error('processopt:DesirabilityBounds','満足度のLowerはUpperより小さくしてください。');
end
individual=zeros(size(Y));
for j=1:height(r)
    lo=r.Lower(j); hi=r.Upper(j); value=Y(:,j);
    switch r.Goal{j}
        case 'min'
            score=(hi-value)/(hi-lo);
        case 'max'
            score=(value-lo)/(hi-lo);
        case 'target'
            target=r.Target(j);
            if target<lo || target>hi
                error('processopt:DesirabilityTarget','targetの目標はLower〜Upper内にしてください。');
            end
            score=zeros(size(value));
            if target>lo
                left=value<target; score(left)=(value(left)-lo)/(target-lo);
            end
            if target<hi
                right=value>target; score(right)=(hi-value(right))/(hi-target);
            end
            score(value==target)=1;
    end
    score=max(0,min(1,score));
    score(value<lo | value>hi)=0;
    individual(:,j)=score;
end
overall=exp(mean(log(individual),2));
end
