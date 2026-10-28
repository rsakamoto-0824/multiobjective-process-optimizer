function [rankValue,crowding]=rankPopulation(objectives,violation)
%RANKPOPULATION Feasibility-first nondominated sorting and crowding distance.
n=size(objectives,1); dominates=cell(n,1); count=zeros(n,1);
for a=1:n-1
    for b=a+1:n
        if better(a,b), dominates{a}(end+1)=b; count(b)=count(b)+1;
        elseif better(b,a), dominates{b}(end+1)=a; count(a)=count(a)+1; end
    end
end
rankValue=inf(n,1); crowding=zeros(n,1); front=find(count==0); level=1;
while ~isempty(front)
    rankValue(front)=level;
    for j=1:size(objectives,2)
        [v,order]=sort(objectives(front,j)); ids=front(order);
        if numel(ids)<=2, crowding(ids)=Inf; continue; end
        if v(end)>v(1)
            crowding(ids([1,end]))=Inf;
            crowding(ids(2:end-1))=crowding(ids(2:end-1))+(v(3:end)-v(1:end-2))/(v(end)-v(1));
        end
    end
    next=[];
    for a=front(:)'
        for b=dominates{a}
            count(b)=count(b)-1;
            if count(b)==0, next(end+1)=b; end %#ok<AGROW>
        end
    end
    front=next(:); level=level+1;
end
    function yes=better(a,b)
        av=violation(a); bv=violation(b); af=av<=1e-9; bf=bv<=1e-9;
        if af && ~bf
            yes=true;
        elseif ~af && bf
            yes=false;
        elseif ~af && ~bf
            yes=av<bv;
        else
            yes=all(objectives(a,:)<=objectives(b,:)) && any(objectives(a,:)<objectives(b,:));
        end
    end
end
