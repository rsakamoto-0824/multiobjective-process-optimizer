function x = latinHypercube(n,p)
%LATINHYPERCUBE Each factor uses each of n equal probability strata once.
x=zeros(n,p);
for j=1:p, x(:,j)=(randperm(n)'-rand(n,1))/n; end
end
