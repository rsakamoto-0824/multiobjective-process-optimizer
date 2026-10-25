function values = scale(values,cfg,direction)
%SCALE Convert physical factor values to coded values and back.
lo=cfg.Factors.Min'; span=(cfg.Factors.Max-cfg.Factors.Min)';
if strcmp(direction,'code')
    values=2*(values-lo)./span-1;
else
    values=lo+(values+1).*span/2;
end
end
