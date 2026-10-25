function [terms,names] = basis(z,kind)
%BASIS Hierarchical polynomial features in coded [-1,1] factor coordinates.
[n,p] = size(z);
terms = [ones(n,1), z]; names = [{'Intercept'},arrayfun(@(k)sprintf('x%d',k),1:p,'UniformOutput',false)];
if ismember(kind,{'purequadratic','quadratic'})
    terms = [terms,z.^2];
    names = [names,arrayfun(@(k)sprintf('x%d^2',k),1:p,'UniformOutput',false)];
end
if ismember(kind,{'interaction','quadratic'})
    for j=1:p-1
        for k=j+1:p
            terms(:,end+1) = z(:,j).*z(:,k); %#ok<AGROW>
            names{end+1} = sprintf('x%d*x%d',j,k); %#ok<AGROW>
        end
    end
end
end
