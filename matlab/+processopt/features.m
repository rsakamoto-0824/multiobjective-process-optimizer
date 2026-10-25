function [F,names]=features(z,basis,latinLevels)
%FEATURES Latin-square row/column blocks are categorical nuisance effects.
if nargin<3 || latinLevels==0
    [F,names]=processopt.basis(z,basis); return
end
assert(size(z,2)==3,'ラテン方格は行ブロック・列ブロック・処理の3列です。');
levels=linspace(-1,1,latinLevels);
F=ones(size(z,1),1); names={'Intercept'};
for block=1:2
    distance=abs(z(:,block)-levels);
    assert(all(min(distance,[],2)<1e-8),'ブロック因子はラテン方格の水準を指定してください。');
    for level=2:latinLevels
        F(:,end+1)=distance(:,level)<1e-8; %#ok<AGROW>
        names{end+1}=sprintf('Block%d_Level%d',block,level); %#ok<AGROW>
    end
end
F(:,end+1)=z(:,3); names{end+1}='x3';
if ismember(basis,{'purequadratic','quadratic'})
    F(:,end+1)=z(:,3).^2; names{end+1}='x3^2';
end
end
