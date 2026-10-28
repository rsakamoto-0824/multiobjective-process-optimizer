function appPath=buildLocalMacLauncher(buildLabel)
%BUILDLOCALMACLAUNCHER Package source with a launcher for installed MATLAB.
% This is a local .app launcher, not a MATLAB Compiler standalone binary.
assert(ismac,'この起動用.appはmacOS専用です。');
assert(~verLessThan('matlab','9.11'),'MATLAB R2021b以降が必要です。');
assert(license('test','Statistics_Toolbox'),'Statistics and Machine Learning Toolboxが必要です。');
if nargin<1, buildLabel='mac-local'; end
assert(~isempty(regexp(char(buildLabel),'^[a-z][a-z0-9-]*$','once')), ...
    'ビルド名には英小文字・数字・ハイフンを使用してください。');
sourceRoot=fileparts(mfilename('fullpath'));
buildRoot=fullfile(fileparts(sourceRoot),'build',char(buildLabel));
appPath=fullfile(buildRoot,'ProcessOptimizer.app');
contents=fullfile(appPath,'Contents');
executableFolder=fullfile(contents,'MacOS');
resourceFolder=fullfile(contents,'Resources','matlab');
if ~isfolder(executableFolder), mkdir(executableFolder); end
if ~isfolder(resourceFolder), mkdir(resourceFolder); end
% Copy only runtime source. Tests and build scripts stay in the project.
entryFiles={'ProcessOptimizerApp.m','launchProcessOptimizer.m'};
for j=1:numel(entryFiles)
    copyfile(fullfile(sourceRoot,entryFiles{j}),fullfile(resourceFolder,entryFiles{j}));
end
packageFolder=fullfile(resourceFolder,'+processopt');
if ~isfolder(packageFolder), mkdir(packageFolder); end
packageFiles=dir(fullfile(sourceRoot,'+processopt','*.m'));
for j=1:numel(packageFiles)
    copyfile(fullfile(packageFiles(j).folder,packageFiles(j).name),packageFolder);
end
matlabExecutable=fullfile(matlabroot,'bin','matlab');
command=join([
    "try"
    "addpath(getenv('PROCESSOPT_APP_MATLAB_DIR'))"
    "app=launchProcessOptimizer"
    "drawnow"
    "assert(isvalid(app.Figure) && strcmp(app.Figure.Visible,'on'))"
    "disp('PROCESSOPT_READY')"
    "waitfor(app.Figure)"
    "exit"
    "catch problem"
    "disp(getReport(problem,'extended','hyperlinks','off'))"
    "exit(1)"
    "end"],'; ');
launcher=join([
    "#!/bin/zsh"
    "set -eu"
    "launcher_dir=""${0:A:h}"""
    "export PROCESSOPT_APP_MATLAB_DIR=""${launcher_dir}/../Resources/matlab"""
    "log_dir=""$HOME/Library/Logs/ProcessOptimizer"""
    "mkdir -p ""$log_dir"""
    "log_file=""$log_dir/" + string(buildLabel) + ".log"""
    "printf '\n--- ProcessOptimizer local MATLAB launcher ---\n' >> ""$log_file"""
    "exec " + quoteShell(matlabExecutable) + " -nosplash -nodesktop -r " + quoteShell(command) + ...
        " >> ""$log_file"" 2>&1"
    ""],newline);
executable=fullfile(executableFolder,'ProcessOptimizer');
writeText(executable,launcher);
[status,message]=system(char("chmod u+x " + quoteShell(executable)));
assert(status==0,'起動ファイルの実行権限を設定できません: %s',message);
plist=join([
    "<?xml version=""1.0"" encoding=""UTF-8""?>"
    "<!DOCTYPE plist PUBLIC ""-//Apple//DTD PLIST 1.0//EN"" ""http://www.apple.com/DTDs/PropertyList-1.0.dtd"">"
    "<plist version=""1.0""><dict>"
    "<key>CFBundleName</key><string>ProcessOptimizer</string>"
    "<key>CFBundleDisplayName</key><string>成膜・DRY 多目的最適化（MATLAB版）</string>"
    "<key>CFBundleIdentifier</key><string>local.processopt.matlablauncher</string>"
    "<key>CFBundleExecutable</key><string>ProcessOptimizer</string>"
    "<key>CFBundlePackageType</key><string>APPL</string>"
    "<key>CFBundleShortVersionString</key><string>0.2.0</string>"
    "<key>CFBundleVersion</key><string>2</string>"
    "<key>NSHighResolutionCapable</key><true/>"
    "</dict></plist>"],newline);
writeText(fullfile(contents,'Info.plist'),plist);
writeText(fullfile(contents,'Resources','LAUNCHER-NOTICE.txt'), ...
    "This launcher requires the installed MATLAB and Statistics and Machine Learning Toolbox." + newline + ...
    "It is not a MATLAB Compiler standalone application." + newline);
fprintf('Mac用MATLABランチャーを作成しました: %s\n',appPath);
end

function quoted=quoteShell(value)
% A single-quoted shell word also protects paths containing spaces and $.
quoted="'" + replace(string(value),"'","'" + char(34) + "'" + char(34) + "'") + "'";
end

function writeText(path,value)
file=fopen(path,'w','n','UTF-8');
assert(file>=0,'ファイルを作成できません: %s',path);
cleanup=onCleanup(@()fclose(file));
fprintf(file,'%s',char(value));
end
