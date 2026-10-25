function cfg = defaultConfig(preset)
%DEFAULTCONFIG Synthetic examples; values do not describe an actual process.
if nargin == 0, preset = 'CVD'; end
cfg.Version = 1;
cfg.Seed = 1729;
cfg.Factors = table({'Temperature';'Pressure';'Flow'}, [350;1;50], ...
    [450;5;150], [0;0;0], ...
    'VariableNames', {'Name','Min','Max','JitterStd'});
cfg.Factors.Current = (cfg.Factors.Min+cfg.Factors.Max)/2;
thickness = '100+0.10*(x1-400)+2*(x2-3)+0.02*(x3-100)+(2+0.002*(x1-395)^2+0.10*(x2-2.5)^2)*(u^2+v^2)+0.01*(x3-95)*u';
warp = '3+0.001*(x1-375)^2+0.02*(x2-3)^2+0.3*(u^2+v^2)';
cfg.Responses = table({'Thickness';'ThicknessNU';'Warp'}, ...
    {'target';'min';'min'}, [100;0;0], [5;1;3], ...
    [90;0;0], [110;5;15], [0.1;0.1;0.02], ...
    {'mean';'nu';'rms'}, {thickness;thickness;warp}, ...
    'VariableNames', {'Name','Goal','Target','Scale','Lower','Upper', ...
    'NoiseStd','Metric','Formula'});
cfg.Responses.Signal = {'Thickness';'Thickness';'Warp'};
if strcmpi(preset, 'DRY')
    cfg.Factors.Name = {'Power';'Pressure';'GasFlow'};
    cfg.Factors.Min = [100;10;20]; cfg.Factors.Max = [300;50;100];
    cfg.Factors.Current = (cfg.Factors.Min+cfg.Factors.Max)/2;
    rate = '120+0.15*(x1-200)-0.2*(x2-30)+0.1*(x3-60)+(1+0.0005*(x1-180)^2+0.01*(x2-25)^2)*(u^2+v^2)+0.02*(x3-60)*u';
    cfg.Responses.Name = {'EtchRate';'EtchRateCV';'Warp'};
    cfg.Responses.Target = [120;0;0]; cfg.Responses.Scale = [10;1;3];
    cfg.Responses.Lower = [100;0;0]; cfg.Responses.Upper = [140;5;15];
    cfg.Responses.Metric = {'mean';'cv';'rms'};
    cfg.Responses.Formula = {rate;rate;'2+0.0003*(x1-130)^2+0.2*(u^2+v^2)'};
    cfg.Responses.Signal = {'EtchRate';'EtchRate';'Warp'};
end
cfg.Design = struct('Method','D-optimal','Runs',40,'Basis','quadratic', ...
    'LatinLevels',4,'Restarts',2,'Passes',3,'Candidates',160);
cfg.Model = struct('Method','Polynomial','Basis','quadratic', ...
    'Folds',5,'Interactions',true,'Kernel','ardsquaredexponential');
cfg.Optimization = struct('Population',64,'Generations',40, ...
    'Scenarios',16,'RiskWeight',0,'ValidationPoints',150);
cfg.Wafer = struct('GridSize',9);
end
