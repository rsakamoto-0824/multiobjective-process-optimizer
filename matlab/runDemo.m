function summary=runDemo(preset,outputFolder)
%RUNDEMO Reproducible full workflow with optional app snapshots and CSV results.
if nargin<1, preset='CVD'; end
if nargin<2, outputFolder=fullfile(fileparts(fileparts(mfilename('fullpath'))),'results',['demo_',lower(preset)]); end
if ~isfolder(outputFolder), mkdir(outputFolder); end
app=ProcessOptimizerApp('off'); cleanup=onCleanup(@()delete(app));
cfg=processopt.defaultConfig(preset); app.setConfig(cfg);
app.generatePlan(); app.simulateData(); app.trainModels(); app.optimizeModels();
assert(~isempty(app.Selected),'デモで実行可能な候補が見つかりませんでした。');
app.verifyTruth();
writetable(app.Diagnostic.Metrics,fullfile(outputFolder,'cross_validation.csv'));
writetable(app.Verification.Metrics,fullfile(outputFolder,'independent_errors.csv'));
writetable(app.Verification.Comparison,fullfile(outputFolder,'comparison.csv'));
summary=struct('Preset',preset,'Runs',size(app.Data.X,1), ...
    'Candidates',size(app.Result.X,1),'Selected',app.Selected, ...
    'CandidateFactors',app.Result.X(app.Selected,:), ...
    'TruthFeasible',app.Verification.Actual.Feasible(2), ...
    'CV',app.Diagnostic.Metrics,'Independent',app.Verification.Metrics, ...
    'Comparison',app.Verification.Comparison);
save(fullfile(outputFolder,'demo_summary.mat'),'summary');
tabs=findall(app.Figure,'Type','uitab');
drawnow; pause(0.5);
for j=1:numel(tabs)
    titleText=tabs(j).Title;
    if startsWith(titleText,{'1 ','3 ','4 ','5 ','6 '})
        tabs(j).Parent.SelectedTab=tabs(j); drawnow; pause(0.5);
        exportapp(app.Figure,fullfile(outputFolder,sprintf('tab_%s.png',titleText(1))));
    end
end
disp(summary); disp(summary.Comparison);
end
