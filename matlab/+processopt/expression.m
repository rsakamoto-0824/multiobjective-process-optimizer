function values = expression(formula,X,u,v)
%EXPRESSION Small arithmetic parser, usable in MATLAB Runtime without eval.
% x1..xp are physical process factors; u,v are normalized wafer coordinates.
source=regexprep(char(formula),'\s','');
assert(numel(source)<=4000,'式は4000文字以下にしてください。');
tokens=regexp(source,'(?:\d+\.?\d*|\.\d+)(?:[eE][+-]?\d+)?|[A-Za-z][A-Za-z0-9_]*|\.\^|\.\*|\./|[+*/^(),-]','match');
assert(~isempty(tokens) && strcmp([tokens{:}],source),'式に使用できない文字が含まれています。');
assert(numel(tokens)<=1500,'式が長すぎます。');
position=1; depth=0;
values=sumExpr();
assert(position>numel(tokens),'式の末尾を解釈できません。');
assert(isreal(values) && all(isfinite(values(:))),'式から複素数・NaN・Infが発生しました。');
assert(ismember(size(values,1),[1,size(X,1)]) && ismember(size(values,2),[1,numel(u)]), '式の出力サイズが不正です。');
values=values+zeros(size(X,1),numel(u));

    function out=sumExpr()
        out=productExpr();
        while peek('+') || peek('-')
            op=take(); rhs=productExpr();
            if strcmp(op,'+'), out=out+rhs; else, out=out-rhs; end
        end
    end
    function out=productExpr()
        out=unaryExpr();
        while peek('*') || peek('/') || peek('.*') || peek('./')
            op=take(); rhs=unaryExpr();
            if contains(op,'*'), out=out.*rhs; else, out=out./rhs; end
        end
    end
    function out=unaryExpr()
        enter();
        if peek('+')
            take(); out=unaryExpr();
        elseif peek('-')
            take(); out=-unaryExpr();
        else
            out=powerExpr();
        end
        depth=depth-1;
    end
    function out=powerExpr()
        out=atom();
        if peek('^') || peek('.^'), take(); out=out.^unaryExpr(); end
    end
    function out=atom()
        token=take();
        if strcmp(token,'(')
            out=sumExpr(); expect(')'); return
        end
        number=str2double(token);
        if ~isnan(number), out=number; return; end
        if strcmp(token,'pi'), out=pi; return; end
        if strcmp(token,'u'), out=u; return; end
        if strcmp(token,'v'), out=v; return; end
        index=regexp(token,'^x([1-9][0-9]*)$','tokens','once');
        if ~isempty(index)
            j=str2double(index{1});
            assert(j<=size(X,2),'存在しない因子%sです。',token);
            out=X(:,j); return
        end
        allowed={'sin','cos','tan','tanh','exp','log','sqrt','abs','min','max'};
        assert(ismember(token,allowed),'未対応の変数または関数: %s',token);
        expect('('); first=sumExpr();
        if ismember(token,{'min','max'})
            expect(','); second=sumExpr(); expect(')');
            if strcmp(token,'min'), out=min(first,second); else, out=max(first,second); end
            return
        end
        expect(')');
        switch token
            case 'sin', out=sin(first);
            case 'cos', out=cos(first);
            case 'tan', out=tan(first);
            case 'tanh', out=tanh(first);
            case 'exp', out=exp(first);
            case 'log', out=log(first);
            case 'sqrt', out=sqrt(first);
            case 'abs', out=abs(first);
        end
    end
    function yes=peek(token)
        yes=position<=numel(tokens) && strcmp(tokens{position},token);
    end
    function token=take()
        assert(position<=numel(tokens),'式が途中で終わっています。');
        token=tokens{position}; position=position+1;
    end
    function expect(token)
        assert(peek(token),'式に %s が必要です。',token); take();
    end
    function enter()
        depth=depth+1; assert(depth<=64,'括弧・演算の入れ子が深すぎます。');
    end
end
