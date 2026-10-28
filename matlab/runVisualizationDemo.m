function summary=runVisualizationDemo(outputFolder)
%RUNVISUALIZATIONDEMO Exercise kernel selection and inspectable response maps.
if nargin<1
    outputFolder=fullfile(fileparts(fileparts(mfilename('fullpath'))),'results','visualization');
end
if ~isfolder(outputFolder), mkdir(outputFolder); end
app=ProcessOptimizerApp('off'); cleanup=onCleanup(@()delete(app));
cfg=processopt.defaultConfig(); cfg.Design.Method='Latin hypercube';
cfg.Model.Method='GPR'; cfg.Model.Kernel='ardmatern52'; cfg.Model.Folds=3;
cfg.Optimization.Population=24; cfg.Optimization.Generations=10;
app.setConfig(cfg); app.generatePlan(); app.simulateData(); app.trainModels(); app.optimizeModels();
app.setAnalysisAnchor('current'); app.drawResponseAnalysis();
response=findall(app.Figure,'Tag','AnalysisResponse'); response.Value='ThicknessNU';
response.ValueChangedFcn(response,[]);
writetable(app.Diagnostic.Metrics,fullfile(outputFolder,'model_metrics.csv'));
landscape=app.Landscape; save(fullfile(outputFolder,'landscape.mat'),'landscape');
summary=struct('Kernel',cfg.Model.Kernel,'ProfileCount',numel(landscape.Profiles), ...
    'PlaneSize',size(landscape.Plane.Overall),'FeasiblePoints',sum(landscape.Plane.Feasible(:)), ...
    'SatisfactionRange',[min(landscape.Plane.Overall(:)),max(landscape.Plane.Overall(:))], ...
    'CalibrationNote',landscape.CalibrationNote);
tabs=findall(app.Figure,'Type','uitab');
model=tabs(startsWith({tabs.Title},'3 ')); model.Parent.SelectedTab=model;
drawnow; pause(0.5); exportapp(app.Figure,fullfile(outputFolder,'kernel_selection.png'));
analysis=tabs(startsWith({tabs.Title},'7 ')); analysis.Parent.SelectedTab=analysis;
app.Figure.Position=[50,50,1460,1400]; drawnow; pause(0.5);
exportapp(app.Figure,fullfile(outputFolder,'response_analysis.png'));
exportgraphics(findall(app.Figure,'Tag','ResponseMap'),fullfile(outputFolder,'response_plane.png'),'Resolution',140);
exportgraphics(findall(app.Figure,'Tag','SatisfactionMap'),fullfile(outputFolder,'satisfaction_plane.png'),'Resolution',140);
disp(summary);
end
