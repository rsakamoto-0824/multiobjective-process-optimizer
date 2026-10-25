function result=buildStandalone()
%BUILDSTANDALONE Build on Windows with R2021b+ and MATLAB Compiler.
assert(~verLessThan('matlab','9.11'),'MATLAB R2021b以降が必要です。');
assert(ispc,'Windows配布版はWindows上のMATLABでビルドしてください。');
assert(license('test','Compiler'),'MATLAB Compilerが必要です。');
assert(license('test','Statistics_Toolbox'),'Statistics and Machine Learning Toolboxが必要です。');
root=fileparts(mfilename('fullpath')); addpath(root);
output=fullfile(fileparts(root),'build');
result=compiler.build.standaloneApplication(fullfile(root,'launchProcessOptimizer.m'), ...
    'ExecutableName','ProcessOptimizer','OutputDir',output, ...
    'AdditionalFiles',{fullfile(root,'+processopt'),fullfile(fileparts(root),'README.md')});
fprintf('ビルド先: %s\n同じMATLABリリースに対応するRuntimeを配布先に導入してください。\n',output);
end
