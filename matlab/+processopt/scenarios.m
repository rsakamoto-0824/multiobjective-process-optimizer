function offsets=scenarios(cfg,seed)
%SCENARIOS Fixed common random numbers make candidate comparisons repeatable.
if nargin<2, seed=cfg.Seed+3; end
old=rng; cleanup=onCleanup(@()rng(old)); %#ok<NASGU>
rng(mod(seed,2^32),'twister');
if all(cfg.Factors.JitterStd==0)
    offsets=zeros(1,height(cfg.Factors));
else
    count=cfg.Optimization.Scenarios;
    assert(count>=2,'条件変動を指定した場合はシナリオ数を2以上にしてください。');
    offsets=[zeros(1,height(cfg.Factors));randn(count-1,height(cfg.Factors)).*cfg.Factors.JitterStd'];
end
end
