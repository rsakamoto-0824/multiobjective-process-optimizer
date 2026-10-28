function results=runTests()
%RUNTESTS Numerical invariants, data contracts, model paths and UI workflow.
root=fileparts(mfilename('fullpath')); addpath(root);
results=runtests(fullfile(root,'tests'));
disp(table(results));
assert(all([results.Passed]),'テストが失敗しました。詳細を確認してください。');
end
