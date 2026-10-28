function app=launchProcessOptimizer()
%LAUNCHPROCESSOPTIMIZER MATLAB / MATLAB Runtime application entry point.
app=ProcessOptimizerApp();
if isdeployed
    waitfor(app.Figure);
elseif nargout==0
    clear app;
end
end
