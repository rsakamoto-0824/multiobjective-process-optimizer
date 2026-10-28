function values=customTruth(X,u,v,signal)
%CUSTOMTRUTH Extension point for an arbitrary, compile-time MATLAB function.
% Set Formula="custom", Signal="CustomExample" to run this example.
% Add cases here and rebuild the Windows application for other functions.
switch char(signal)
    case 'CustomExample'
        values=X(:,1)+sin(pi*u).*cos(pi*v);
    otherwise
        error('独自関数のSignal %sはcustomTruth.mに未実装です。実装して再ビルドしてください。',char(signal));
end
assert(isreal(values) && all(isfinite(values(:))),'独自関数から非有限値が返りました。');
values=values+zeros(size(X,1),numel(u));
end
