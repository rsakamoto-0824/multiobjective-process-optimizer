function y=aggregate(values,metric)
%AGGREGATE Rows are runs, columns are wafer sites. Percent metrics use |mean|.
assert(isnumeric(values) && isreal(values) && all(isfinite(values(:))) && ~isempty(values),'測定値は有限の実数にしてください。');
average=mean(values,2);
switch metric
    case 'mean', y=average;
    case 'std'
        assert(size(values,2)>1,'標準偏差には各RunIDに2測定点以上が必要です。');
        y=std(values,0,2);
    case 'rms', y=sqrt(mean(values.^2,2));
    case 'range', y=max(values,[],2)-min(values,[],2);
    otherwise
        assert(size(values,2)>1,'面内ばらつきには2測定点以上が必要です。');
        assert(all(abs(average)>1e-12),'平均がゼロ付近のためCV/NUを定義できません。std/rangeを使用してください。');
        if strcmp(metric,'cv')
            y=100*std(values,0,2)./abs(average);
        elseif strcmp(metric,'nu')
            y=100*(max(values,[],2)-min(values,[],2))./(2*abs(average));
        else
            error('未対応の集約指標: %s',metric);
        end
end
end
