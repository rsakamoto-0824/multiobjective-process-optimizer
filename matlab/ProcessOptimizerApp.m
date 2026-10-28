classdef ProcessOptimizerApp < handle
    %PROCESSOPTIMIZERAPP Local workflow for wafer DOE, surrogates and Pareto search.
    properties (SetAccess=private)
        Figure
        Config
        Plan = []
        Data = []
        Bundle = []
        Diagnostic = []
        Result = []
        Verification = []
        Confirmation = []
        Landscape = []
        Selected = []
    end
    properties (Access=private)
        U = struct()
        Busy = false
        StopRequested = false
        FactorRow = 1
        ResponseRow = 1
    end
    methods
        function app=ProcessOptimizerApp(visible)
            if nargin<1, visible='on'; end
            assert(~verLessThan('matlab','9.11'),'MATLAB R2021b以降が必要です。');
            app.Config=processopt.defaultConfig();
            app.buildUI(visible); app.applyConfig(app.Config);
            % Finish creating web-backed controls before callbacks can redraw them.
            drawnow;
        end
        function delete(app)
            if ~isempty(app.Figure) && isvalid(app.Figure), delete(app.Figure); end
        end
        function generatePlan(app)
            app.run(@work);
            function work()
                cfg=app.captureConfig();
                if strcmp(cfg.Design.Method,'Latin square')
                    % Select actual block levels for the conditional treatment search.
                    assert(height(cfg.Factors)==3,'ラテン方格は因子3つ（行・列ブロック、処理）です。');
                    span=cfg.Factors.Max-cfg.Factors.Min; levels=cfg.Design.LatinLevels;
                    cfg.Factors.Current(1:2)=cfg.Factors.Min(1:2)+ ...
                        round((cfg.Factors.Current(1:2)-cfg.Factors.Min(1:2))./span(1:2)*(levels-1)).*span(1:2)/(levels-1);
                    app.applyConfig(cfg);
                end
                app.invalidate('data');
                app.Plan=processopt.makeDesign(cfg); app.U.DataTable.Data=app.Plan.Table;
                app.setStatus(sprintf('計画: %d実験、回帰行列の階数 %d/%d、条件数 %.3g', ...
                    size(app.Plan.X,1),app.Plan.Rank,app.Plan.Terms,app.Plan.Condition));
            end
        end
        function simulateData(app)
            app.run(@work);
            function work()
                cfg=app.captureConfig(); assert(~isempty(app.Plan),'先に実験計画を生成してください。');
                app.invalidate('models');
                [Y,~]=processopt.simulate(cfg,app.Plan.X,true,cfg.Seed+1);
                [~,~,groups]=unique(app.Plan.X,'rows');
                app.Data=struct('X',app.Plan.X,'Y',Y,'Groups',groups,'Source','Synthetic');
                app.Data.DesignMethod=app.Plan.Method; app.Data.LatinLevels=cfg.Design.LatinLevels;
                app.displayData(); app.setStatus('仮想測定を生成しました。学習・検証へ進んでください。');
            end
        end
        function trainModels(app)
            app.run(@work);
            function work()
                cfg=app.captureConfig(); assert(~isempty(app.Data),'測定CSVを読むか仮想測定を生成してください。');
                app.invalidate('models');
                [app.Bundle,app.Diagnostic]=processopt.fitModels(cfg,app.Data,@(s)app.progress(s));
                app.U.Metrics.Data=app.Diagnostic.Metrics;
                app.refreshResponseMenus(); app.plotDiagnostic();
                app.setStatus('交差検証が完了しました。CV_RMSE・残差を確認。GAM_Interactionsは実際に採用された相互作用の数です。');
            end
        end
        function optimizeModels(app)
            app.run(@work);
            function work()
                cfg=app.captureConfig(); assert(~isempty(app.Bundle),'先にモデルを作成してください。');
                app.invalidate('results'); app.StopRequested=false;
                app.U.Cancel.Enable='on';
                app.Result=processopt.optimize(cfg,app.Bundle,app.Data,@(s)app.progress(s),@()app.StopRequested);
                app.U.Cancel.Enable='off'; app.Selected=app.Result.Compromise;
                app.U.Candidates.Data=app.candidateTable(); app.plotPareto();
                if isempty(app.Selected)
                    app.setStatus(sprintf('実行可能な候補がありません。最小制約違反 %.4g。範囲・応答制約・条件変動を確認してください。', ...
                        min(app.Result.PopulationEvaluation.Violation)));
                else
                    app.setStatus(sprintf('%d件の非劣解を表示。初期選択は正規化した各目的の理想点に近い候補です。',size(app.Result.X,1)));
                end
            end
        end
        function verifyTruth(app)
            app.run(@work);
            function work()
                cfg=app.captureConfig(); assert(~isempty(app.Result),'先に最適化してください。');
                app.Verification=processopt.verify(cfg,app.Bundle,app.Result,app.Selected);
                app.U.TruthMetrics.Data=app.Verification.Metrics;
                app.U.Comparison.Data=app.Verification.Comparison;
                app.plotVerification(); app.plotWafer();
                app.setStatus(sprintf('真のモデルで独立検証完了。候補の制約適合: %d、元条件: %d（%dシナリオ）。正のLossImprovementは改善。', ...
                    app.Verification.Actual.Feasible(2),app.Verification.Actual.Feasible(1),app.Verification.ScenarioCount));
            end
        end
        function cfg=getConfig(app)
            cfg=app.captureConfig();
        end
        function drawResponseAnalysis(app)
            app.run(@work);
            function work()
                cfg=app.captureConfig(); assert(~isempty(app.Bundle),'先にモデルを学習してください。');
                anchor=app.U.AnalysisAnchor.Data.Fixed';
                names=string(cfg.Factors.Name);
                pair=[find(names==string(app.U.AnalysisX.Value),1),find(names==string(app.U.AnalysisY.Value),1)];
                app.setStatus('因子効果・応答面・満足度を計算しています。'); drawnow;
                app.Landscape=processopt.responseLandscape(cfg,app.Bundle,anchor,pair, ...
                    app.U.AnalysisPoints.Value,app.U.AnalysisMode.Value);
                app.plotResponseAnalysis();
                if isempty(app.Landscape.CalibrationNote)
                    app.setStatus('固定断面の応答と満足度を表示しました。灰色は全応答の制約を満たさない領域です。');
                else
                    app.setStatus(app.Landscape.CalibrationNote);
                end
            end
        end
        function setAnalysisAnchor(app,source)
            cfg=app.captureConfig(); anchor=cfg.Factors.Current';
            if strcmp(source,'candidate')
                if isempty(app.Result) || isempty(app.Selected)
                    app.setStatus('先に最適化して候補を選択してください。'); return
                end
                anchor=app.Result.X(app.Selected,:);
            end
            app.U.AnalysisAnchor.Data=table(string(cfg.Factors.Name),anchor', ...
                'VariableNames',{'Factor','Fixed'});
            app.clearResponseAnalysis();
        end
        function saveProjectFile(app,path)
            project=struct('Config',app.captureConfig(),'Data',app.Data); %#ok<NASGU>
            save(path,'project'); app.setStatus('設定と学習データを保存しました。');
        end
        function loadProjectFile(app,path)
            saved=load(path,'project'); project=saved.project;
            cfg=processopt.validateConfig(project.Config); incoming=project.Data;
            if ~isempty(incoming)
                names=[cellstr(string(cfg.Factors.Name));cellstr(string(cfg.Responses.Name))];
                T=array2table([incoming.X,incoming.Y],'VariableNames',names);
                source=incoming.Source; savedData=incoming;
                incoming=processopt.importData(T,cfg,'wide'); incoming.Source=source;
                if isfield(savedData,'DesignMethod')
                    incoming.DesignMethod=savedData.DesignMethod; incoming.LatinLevels=savedData.LatinLevels;
                end
            end
            app.invalidate('data'); app.applyConfig(cfg); app.Data=incoming;
            if ~isempty(incoming), app.displayData(); end
            app.setStatus('設定・学習データを読み込みました。モデルを再学習してください。');
        end
        function setConfig(app,cfg)
            assert(~app.Busy,'処理中は設定を変更できません。');
            cfg=processopt.validateConfig(cfg); app.invalidate('data'); app.applyConfig(cfg);
        end
    end
    methods (Access=private)
        function buildUI(app,visible)
            app.Figure=uifigure('Name','成膜・DRY 多目的最適化', ...
                'Position',[50,50,1460,930],'Visible',visible, ...
                'CloseRequestFcn',@(~,~)app.closeRequested());
            layout=uigridlayout(app.Figure,[3,1]); layout.RowHeight={38,'1x',42};
            toolbar=uigridlayout(layout,[1,6]); toolbar.ColumnWidth={190,140,140,140,'1x',150};
            app.U.Preset=uidropdown(toolbar,'Items',{'CVD（仮想例）','DRY（仮想例）'});
            uibutton(toolbar,'Text','例を読み込む','ButtonPushedFcn',@(~,~)app.loadPreset());
            uibutton(toolbar,'Text','プロジェクトを開く','ButtonPushedFcn',@(~,~)app.loadProject());
            uibutton(toolbar,'Text','プロジェクトを保存','ButtonPushedFcn',@(~,~)app.saveProject());
            uilabel(toolbar,'Text','ローカル処理 | MATLAB R2021b+','HorizontalAlignment','right');
            app.U.Cancel=uibutton(toolbar,'Text','探索を中止','Enable','off','ButtonPushedFcn',@(~,~)app.requestStop());
            tabs=uitabgroup(layout);
            settings=uitab(tabs,'Title','1 設定・真のモデル');
            doe=uitab(tabs,'Title','2 実験計画・データ');
            modeling=uitab(tabs,'Title','3 モデル・交差検証');
            optimization=uitab(tabs,'Title','4 多目的最適化');
            verification=uitab(tabs,'Title','5 効果・真値検証');
            confirmation=uitab(tabs,'Title','6 追加実験で確認');
            analysis=uitab(tabs,'Title','7 因子効果・満足度');
            guide=uitab(tabs,'Title','使い方・指標の定義');
            app.buildSettings(settings); app.buildData(doe); app.buildModel(modeling);
            app.buildOptimization(optimization); app.buildVerification(verification);
            app.buildConfirmation(confirmation); app.buildAnalysis(analysis); app.buildGuide(guide);
            app.U.Status=uilabel(layout,'Text','設定 → 実験計画 → 測定 → モデル → 最適化 → 検証', ...
                'WordWrap','on','FontColor',[0.1,0.25,0.35]);
            app.stackRows({toolbar,tabs,app.U.Status});
            grids=findall(app.Figure,'Type','uigridlayout');
            for index=1:numel(grids)
                grid=grids(index);
                if numel(grid.RowHeight)==1, grid.Padding=[0,0,0,0]; end
            end
        end
        function buildSettings(app,parent)
            g=uigridlayout(parent,[7,1]); g.RowHeight={34,150,34,230,48,34,44}; g.Scrollable='on';
            bar=uigridlayout(g,[1,4]); bar.ColumnWidth={220,120,120,'1x'};
            factorBar=bar;
            uilabel(bar,'Text','説明変数（x1, x2, ... は表の順）','FontWeight','bold');
            uibutton(bar,'Text','因子を追加','ButtonPushedFcn',@(~,~)app.addFactor());
            uibutton(bar,'Text','選択因子を削除','ButtonPushedFcn',@(~,~)app.removeFactor());
            uilabel(bar,'Text','Current: 比較元条件 / JitterStd: 条件の変動標準偏差');
            app.U.Factors=uitable(g,'ColumnEditable',true,'CellEditCallback',@(~,e)app.factorEdited(e), ...
                'CellSelectionCallback',@(~,e)app.selectFactor(e));
            bar=uigridlayout(g,[1,4]); bar.ColumnWidth={220,120,120,'1x'};
            responseBar=bar;
            uilabel(bar,'Text','応答・目的・真のモデル','FontWeight','bold');
            uibutton(bar,'Text','応答を追加','ButtonPushedFcn',@(~,~)app.addResponse());
            uibutton(bar,'Text','選択応答を削除','ButtonPushedFcn',@(~,~)app.removeResponse());
            uilabel(bar,'Text','Goal: target / min / max、Lower/Upper: 許容範囲（±Inf可）');
            app.U.Responses=uitable(g,'ColumnEditable',true,'CellEditCallback',@(~,e)app.responseEdited(e), ...
                'CellSelectionCallback',@(~,e)app.selectResponse(e), ...
                'ColumnWidth',{120,75,65,65,65,65,75,65,520,120});
            description=uilabel(g,'Text',['Metric: mean / std / cv / nu / rms / range。Signalが同じ応答は同じ測定値から集約します。' ...
                '式では x1...（実単位）と u,v（半径1のWafer座標）を使用。NoiseStdは測定点ごとの加法ノイズ。'], 'WordWrap','on');
            bar=uigridlayout(g,[1,4]); bar.ColumnWidth={130,120,160,120};
            uilabel(bar,'Text','乱数シード'); app.U.Seed=uieditfield(bar,'numeric','Limits',[0,2^32-1],'RoundFractionalValues','on','ValueChangedFcn',@(~,~)app.invalidate('data'));
            uilabel(bar,'Text','Waferの一辺の格子数'); app.U.GridSize=uieditfield(bar,'numeric','Limits',[3,31],'RoundFractionalValues','on','ValueChangedFcn',@(~,~)app.invalidate('data'));
            finalNote=uilabel(g,'Text','実測データでは真の式を学習に使いません。真の式による検証は、設定した仮想世界の中での検証です。','WordWrap','on');
            app.stackRows({factorBar,app.U.Factors,responseBar,app.U.Responses,description,bar,finalNote});
        end
        function buildData(app,parent)
            g=uigridlayout(parent,[4,1]); g.RowHeight={42,42,52,420}; g.Scrollable='on';
            b=uigridlayout(g,[1,8]); b.ColumnWidth={70,170,65,85,90,130,110,'1x'};
            planningBar=b;
            uilabel(b,'Text','計画法');
            app.U.DesignMethod=uidropdown(b,'Items',{'D-optimal','I-optimal','DSD','Latin hypercube','Latin square'},'ValueChangedFcn',@(~,~)app.invalidate('plan'));
            uilabel(b,'Text','実験数'); app.U.Runs=uieditfield(b,'numeric','Limits',[3,1000],'RoundFractionalValues','on','ValueChangedFcn',@(~,~)app.invalidate('plan'));
            uilabel(b,'Text','計画の回帰項'); app.U.DesignBasis=uidropdown(b,'Items',{'linear','interaction','purequadratic','quadratic'},'ValueChangedFcn',@(~,~)app.invalidate('plan'));
            uilabel(b,'Text','方格の水準数'); app.U.LatinLevels=uieditfield(b,'numeric','Limits',[2,20],'RoundFractionalValues','on','ValueChangedFcn',@(~,~)app.invalidate('plan'));
            b=uigridlayout(g,[1,6]);
            uibutton(b,'Text','計画を生成','ButtonPushedFcn',@(~,~)app.generatePlan());
            uibutton(b,'Text','計画CSVを保存','ButtonPushedFcn',@(~,~)app.exportPlan());
            uibutton(b,'Text','真の式から仮想測定','ButtonPushedFcn',@(~,~)app.simulateData());
            uibutton(b,'Text','集約済CSVを読む','ButtonPushedFcn',@(~,~)app.readCSV('wide'));
            uibutton(b,'Text','Wafer測定CSVを読む','ButtonPushedFcn',@(~,~)app.readCSV('long'));
            uibutton(b,'Text','学習データCSVを保存','ButtonPushedFcn',@(~,~)app.exportData());
            description=uilabel(g,'Text',['D/I最適は有限候補上の交換探索による近似計画。DSDとラテン方格の実験数は構成で決まります。' ...
                'ラテン方格は因子3つ（行・列ブロック・処理）の均衡配置です。最初の2因子はカテゴリのブロック効果として扱い、探索時はCurrentの水準に固定します。'], 'WordWrap','on');
            app.U.DataTable=uitable(g);
            app.stackRows({planningBar,b,description,app.U.DataTable});
        end
        function buildModel(app,parent)
            g=uigridlayout(parent,[6,1]); g.RowHeight={44,38,60,155,42,300}; g.Scrollable='on';
            b=uigridlayout(g,[1,8]); b.ColumnWidth={65,140,60,145,90,75,150,'1x'};
            modelingBar=b;
            uilabel(b,'Text','モデル'); app.U.ModelMethod=uidropdown(b,'Items',{'Polynomial','GPR','GAM'},'ValueChangedFcn',@(~,~)app.modelChanged());
            uilabel(b,'Text','回帰項'); app.U.ModelBasis=uidropdown(b,'Items',{'linear','interaction','purequadratic','quadratic'},'ValueChangedFcn',@(~,~)app.invalidate('models'));
            uilabel(b,'Text','検証分割数'); app.U.Folds=uieditfield(b,'numeric','Limits',[2,10],'RoundFractionalValues','on','ValueChangedFcn',@(~,~)app.invalidate('models'));
            app.U.Interactions=uicheckbox(b,'Text','GAMの交互作用','Value',true,'ValueChangedFcn',@(~,~)app.invalidate('models'));
            uibutton(b,'Text','学習・交差検証','ButtonPushedFcn',@(~,~)app.trainModels());
            kernelBar=uigridlayout(g,[1,3]); kernelBar.ColumnWidth={100,300,'1x'};
            uilabel(kernelBar,'Text','GPRカーネル'); [kernels,labels]=processopt.gprKernels();
            app.U.GPRKernel=uidropdown(kernelBar,'Items',labels,'ItemsData',kernels,'Tag','GPRKernel', ...
                'ValueChangedFcn',@(~,~)app.invalidate('models'));
            uilabel(kernelBar,'Text','ARD: 因子ごとに長さ尺度を推定。カーネル変更後は交差検証を含めて再学習します。');
            description=uilabel(g,'Text',['回帰項はPolynomial用です。GPRは選択したカーネル、GAMは加法モデルと任意の2因子相互作用を使用。' ...
                '同じ因子条件の繰返しは同じ検証グループに入ります。CV_R2は負値や、定数応答でNaNになる場合があります。'], 'WordWrap','on');
            app.U.Metrics=uitable(g);
            b=uigridlayout(g,[1,3]); b.ColumnWidth={65,220,'1x'};
            uilabel(b,'Text','応答'); app.U.DiagnosticResponse=uidropdown(b,'Items',{'-'},'ValueChangedFcn',@(~,~)app.plotDiagnostic());
            uibutton(b,'Text','回帰係数をCSV保存','ButtonPushedFcn',@(~,~)app.exportCoefficients());
            plots=uigridlayout(g,[1,2]); app.U.FitAxes=uiaxes(plots); app.U.ResidualAxes=uiaxes(plots);
            app.stackRows({modelingBar,kernelBar,description,app.U.Metrics,b,plots});
            app.U.FitAxes.Layout.Column=1; app.U.ResidualAxes.Layout.Column=2;
        end
        function buildOptimization(app,parent)
            g=uigridlayout(parent,[5,1]); g.RowHeight={44,70,44,280,210}; g.Scrollable='on';
            b=uigridlayout(g,[1,8]); b.ColumnWidth={70,75,70,75,85,75,105,90};
            parameterBar=b;
            uilabel(b,'Text','集団数'); app.U.Population=uieditfield(b,'numeric','Limits',[12,300],'RoundFractionalValues','on','ValueChangedFcn',@(~,~)app.invalidate('results'));
            uilabel(b,'Text','世代数'); app.U.Generations=uieditfield(b,'numeric','Limits',[1,300],'RoundFractionalValues','on','ValueChangedFcn',@(~,~)app.invalidate('results'));
            uilabel(b,'Text','シナリオ数'); app.U.Scenarios=uieditfield(b,'numeric','Limits',[1,128],'RoundFractionalValues','on','ValueChangedFcn',@(~,~)app.invalidate('results'));
            uilabel(b,'Text','リスク重み'); app.U.RiskWeight=uieditfield(b,'numeric','Limits',[0,Inf],'ValueChangedFcn',@(~,~)app.invalidate('results'));
            description=uilabel(g,'Text',['各目的の損失 = target: |予測−目標|/Scale、min: 予測/Scale、max: −予測/Scale。' ...
                '条件変動ありでは平均損失 + リスク重み×損失標準偏差を最小化します。' ...
                '全シナリオで因子範囲・応答制約を満たす候補を抽出します。探索結果は近似であり、最適性の保証はありません。'], 'WordWrap','on');
            b=uigridlayout(g,[1,6]); b.ColumnWidth={160,180,65,180,65,180};
            uibutton(b,'Text','多目的探索を実行','ButtonPushedFcn',@(~,~)app.optimizeModels());
            uibutton(b,'Text','結果一式をCSV保存','ButtonPushedFcn',@(~,~)app.exportResults());
            uilabel(b,'Text','横軸'); app.U.ParetoX=uidropdown(b,'Items',{'-'},'ValueChangedFcn',@(~,~)app.plotPareto());
            uilabel(b,'Text','縦軸'); app.U.ParetoY=uidropdown(b,'Items',{'-'},'ValueChangedFcn',@(~,~)app.plotPareto());
            plots=uigridlayout(g,[1,1]); app.U.ParetoAxes=uiaxes(plots);
            app.U.Candidates=uitable(g,'CellSelectionCallback',@(~,e)app.selectCandidate(e));
            app.stackRows({parameterBar,description,b,plots,app.U.Candidates});
        end
        function buildVerification(app,parent)
            g=uigridlayout(parent,[6,1]); g.RowHeight={42,56,120,145,250,220}; g.Scrollable='on';
            b=uigridlayout(g,[1,6]); b.ColumnWidth={125,85,170,65,180,'1x'};
            uilabel(b,'Text','独立した検証点数'); app.U.ValidationPoints=uieditfield(b,'numeric','Limits',[20,2000],'RoundFractionalValues','on','ValueChangedFcn',@(~,~)app.clearVerification());
            uibutton(b,'Text','選択候補を真値で検証','ButtonPushedFcn',@(~,~)app.verifyTruth());
            uilabel(b,'Text','応答'); app.U.VerifyResponse=uidropdown(b,'Items',{'-'},'ValueChangedFcn',@(~,~)app.updateVerificationPlots());
            uilabel(b,'Text','測定ノイズなしの真値と比較');
            description=uilabel(g,'Text',['この検証は設定した真の式に対するものです。実測の効果確認には、候補条件での追加実験が必要です。' ...
                '条件変動は探索時と別の乱数で再検証し、表のSDは測定ノイズを含まない条件変動による標準偏差です。'], 'WordWrap','on');
            app.U.TruthMetrics=uitable(g); app.U.Comparison=uitable(g);
            plots=uigridlayout(g,[1,2]); app.U.TruthAxes=uiaxes(plots); app.U.ImprovementAxes=uiaxes(plots);
            mainPlots=plots;
            plots=uigridlayout(g,[1,2]); app.U.BaselineWafer=uiaxes(plots); app.U.CandidateWafer=uiaxes(plots);
            app.stackRows({b,description,app.U.TruthMetrics,app.U.Comparison,mainPlots,plots});
            app.U.TruthAxes.Layout.Column=1; app.U.ImprovementAxes.Layout.Column=2;
            app.U.BaselineWafer.Layout.Column=1; app.U.CandidateWafer.Layout.Column=2;
        end
        function buildGuide(~,parent)
            g=uigridlayout(parent,[1,1]);
            uitextarea(g,'Editable','off','Value',{
                '成膜・DRY 多目的最適化';
                ''; '1. 設定: 因子範囲・現在条件、応答ごとのGoal / Target / Scaleと許容上下限を指定。';
                '2. 計画生成後に計画CSVを保存して実験するか、真の式から仮想測定を作成。';
                '3. モデルを選び、学習・交差検証。誤差と残差を確認。';
                '4. 探索し、候補表の行をクリックして比較する候補を選択。';
                '5. 真の式による独立検証。実測の場合は「追加実験で確認」で測定値による比較。';
                ''; 'Polynomialの項: linear=主効果、interaction=主効果+2因子積、purequadratic=主効果+二乗、quadratic=全て。';
                '最大次数2の制限はPolynomialに適用。GPR・GAMは非線形の柔軟なモデル。';
                'DSD: conference行列から構成。必要因子数を覆う最小の対応次数に射影。全2次回帰は一般に推定不能。';
                'Latin square: 3因子が行ブロック・列ブロック・処理。各処理が各行と各列に1回ずつ出現。';
                '行・列はカテゴリとして補正し、探索時はCurrentの水準に固定。計画生成時にCurrentを最寄りの実水準へ合わせる。';
                '行・列ブロックにはJitterStd=0を指定。Polynomialはブロックの主効果と処理の最大2次式を使う。';
                'GPRは二乗指数、指数、Matern 3/2・5/2、有理二次と各ARD版を選択できる。';
                '「因子効果・満足度」で他因子をFixedに固定した応答曲線と2因子平面を描画する。因果効果・全域の重要度ではない。';
                '満足度は0〜1。targetは目標で1、上下限で0。minはLowerで1/Upperで0。maxはその逆。範囲外は0。';
                '総合は全応答の幾何平均で、1応答でも0なら0。満足度の計算には全応答の有限Lower/Upperが必要。';
                '満足度は表示用の指標。Pareto探索の損失とリスク重みは変更しない。灰色は全応答の制約違反。';
                '「条件変動の平均」では各シナリオの満足度を計算してから平均する。平均応答に満足度を適用する計算ではない。';
                'Latin hypercube: 各連続因子の範囲を等分し、各区間から1点ずつ抽出。';
                ''; '集約済CSV（1行=1実験）: 因子Name列 + 応答Name列。';
                'Wafer測定CSV（1行=1測定点）: RunID, WaferX, WaferY, 因子Name列 + Signal列。';
                '同じRunIDは同じ因子条件にする。別Wafer・繰返しは別RunID。欠測や重複位置は取込時にエラー。';
                '追加実験CSV: 上記の列にRole列を追加。baselineは元条件、candidateは選択候補の実験。両方を必ず含める。';
                '追加実験の比較は独立した実測値だけを用い、真の式を使わない。繰返し1枚ではWafer間SDをNaNと表示。';
                '面内指標: mean=平均、std=標本標準偏差(N−1)、cv=100*std/|mean| (%)、';
                'nu=100*(max−min)/(2*|mean|) (%)、rms=sqrt(mean(value^2))、range=max−min。';
                '重み付け・面積補正は行わず、測定点を等重みで扱う。座標の単位はCSV内で統一。';
                ''; '真の式: 数値、x1..x12、u、v、pi、+ - * / ^、括弧、sin cos tan tanh exp log sqrt abs、min(a,b) max(a,b)。';
                '演算は全て要素ごと。任意のMATLABコードや外部.mの動的実行はしない。';
                'より一般の関数はcustomTruth.mに実装し、Formula=customと対応Signalを設定して再ビルドする。';
                '同じSignalのFormula / NoiseStdは揃える。式の物理的妥当性は利用者が確認。例は実プロセスの推奨値ではない。';
                ''; 'CV_Coverage95: PolynomialとGPRの近似95%予測区間に交差検証の実測値が入る割合。GAMはNaN。';
                '区間は正規近似で、小標本・モデルの偏りを補正した保証区間ではない。';
                '条件変動: 各因子を独立な正規乱数で変動。先頭シナリオに変動ゼロを含む。境界で切り詰めず範囲逸脱を制約違反にする。';
                '最適化中は同じ乱数シナリオを全候補で共用。真値検証では別乱数を使用。有限標本の検証である。';
                ''; '因子範囲・応答定義変更時はデータとモデルを消去。Goal / Target / Scale / 上下限・Current / Jitter変更は探索結果を消去。';
                'プロジェクトMATは設定と学習データを保存し、読込後にモデルを再学習。信頼するローカルMATだけを読む。';
                'Windows版はWindowsのMATLAB Compilerでビルドし、同じリリースのMATLAB Runtimeを導入して実行。';
                'ソースのR2021b実機確認とWindows Runtimeでの配布確認は、READMEの受入手順を参照。'});
        end
        function buildConfirmation(app,parent)
            g=uigridlayout(parent,[5,1]); g.RowHeight={44,65,130,180,280}; g.Scrollable='on';
            b=uigridlayout(g,[1,2]);
            uibutton(b,'Text','追加実験（集約済CSV）を比較','ButtonPushedFcn',@(~,~)app.readConfirmation('wide'));
            uibutton(b,'Text','追加実験（Wafer測定CSV）を比較','ButtonPushedFcn',@(~,~)app.readConfirmation('long'));
            description=uilabel(g,'Text',['Role列にbaseline / candidateを記入し、元条件と選択候補の独立した測定値を読み込みます。' ...
                '学習データへの追加は行いません。LossImprovementが正ならその応答の平均損失が低減しています。' ...
                'Wafer間SDは繰返しが1枚の場合NaN。統計的有意差や量産保証を意味しません。'], 'WordWrap','on');
            app.U.ConfirmationMetrics=uitable(g); app.U.ConfirmationTable=uitable(g);
            plots=uigridlayout(g,[1,1]); app.U.ConfirmationAxes=uiaxes(plots);
            app.stackRows({b,description,app.U.ConfirmationMetrics,app.U.ConfirmationTable,plots});
        end
        function stackRows(~,objects)
            for row=1:numel(objects)
                objects{row}.Layout.Row=row; objects{row}.Layout.Column=1;
            end
        end
        function buildAnalysis(app,parent)
            g=uigridlayout(parent,[7,1]); g.RowHeight={42,42,110,70,240,340,220}; g.Scrollable='on';
            app.U.AnalysisRoot=g;
            b=uigridlayout(g,[1,7]); b.ColumnWidth={60,180,60,170,60,170,160};
            selectorBar=b;
            uilabel(b,'Text','応答'); app.U.AnalysisResponse=uidropdown(b,'Items',{'-'}, ...
                'Tag','AnalysisResponse','ValueChangedFcn',@(~,~)app.plotResponseAnalysis());
            uilabel(b,'Text','横軸'); app.U.AnalysisX=uidropdown(b,'Items',{'-'}, ...
                'Tag','AnalysisX','ValueChangedFcn',@(~,~)app.clearResponseAnalysis());
            uilabel(b,'Text','縦軸'); app.U.AnalysisY=uidropdown(b,'Items',{'-'}, ...
                'Tag','AnalysisY','ValueChangedFcn',@(~,~)app.clearResponseAnalysis());
            uibutton(b,'Text','描画・更新','ButtonPushedFcn',@(~,~)app.drawResponseAnalysis());
            b=uigridlayout(g,[1,8]); b.ColumnWidth={160,180,70,160,65,180,80,80};
            uibutton(b,'Text','Currentを固定値に','ButtonPushedFcn',@(~,~)app.setAnalysisAnchor('current'));
            uibutton(b,'Text','選択候補を固定値に','ButtonPushedFcn',@(~,~)app.setAnalysisAnchor('candidate'));
            uilabel(b,'Text','満足度'); app.U.AnalysisScore=uidropdown(b,'Items',{'総合（幾何平均）','選択した応答'}, ...
                'ItemsData',{'overall','response'},'Tag','AnalysisScore','ValueChangedFcn',@(~,~)app.plotResponseAnalysis());
            uilabel(b,'Text','評価'); app.U.AnalysisMode=uidropdown(b,'Items',{'名目条件','条件変動の平均'}, ...
                'ItemsData',{'nominal','scenarios'},'Tag','AnalysisMode','ValueChangedFcn',@(~,~)app.clearResponseAnalysis());
            uilabel(b,'Text','平面格子数'); app.U.AnalysisPoints=uieditfield(b,'numeric','Limits',[11,61], ...
                'RoundFractionalValues','on','Value',31,'Tag','AnalysisPoints','ValueChangedFcn',@(~,~)app.clearResponseAnalysis());
            app.U.AnalysisAnchor=uitable(g,'ColumnEditable',[false,true], ...
                'CellEditCallback',@(~,~)app.clearResponseAnalysis());
            app.U.AnalysisNote=uilabel(g,'WordWrap','on','Text', ...
                '他の因子をFixedに固定した断面です。モデル学習後に「描画・更新」を押してください。');
            app.U.EffectGrid=uigridlayout(g,[1,1]); app.U.EffectGrid.Padding=[0,0,0,0];
            app.U.EffectAxes={};
            maps=uigridlayout(g,[1,2]);
            app.U.ResponseMap=uiaxes(maps,'Tag','ResponseMap'); app.U.ResponseMap.Layout.Column=1;
            app.U.SatisfactionMap=uiaxes(maps,'Tag','SatisfactionMap'); app.U.SatisfactionMap.Layout.Column=2;
            bottom=uigridlayout(g,[1,1]); app.U.EffectRangeAxes=uiaxes(bottom);
            app.stackRows({selectorBar,b,app.U.AnalysisAnchor,app.U.AnalysisNote,app.U.EffectGrid,maps,bottom});
        end
        function refreshAnalysisMenus(app)
            names=cellstr(string(app.U.Factors.Data.Name));
            app.U.AnalysisX.Items=names; app.U.AnalysisX.Value=names{1};
            app.U.AnalysisY.Items=names; app.U.AnalysisY.Value=names{min(2,numel(names))};
            app.U.AnalysisAnchor.Data=table(string(app.U.Factors.Data.Name),app.U.Factors.Data.Current, ...
                'VariableNames',{'Factor','Fixed'});
            p=numel(names);
            if numel(app.U.EffectAxes)~=p
                delete(app.U.EffectGrid.Children); columns=min(3,p); rows=ceil(p/columns);
                app.U.EffectGrid.ColumnWidth=repmat({'1x'},1,columns);
                app.U.EffectGrid.RowHeight=repmat({240},1,rows);
                app.U.AnalysisRoot.RowHeight{5}=240*rows+10*(rows-1);
                app.U.EffectAxes=cell(1,p);
                for j=1:p
                    ax=uiaxes(app.U.EffectGrid); ax.Layout.Row=ceil(j/columns); ax.Layout.Column=mod(j-1,columns)+1;
                    app.U.EffectAxes{j}=ax;
                end
            end
        end
        function clearResponseAnalysis(app)
            app.Landscape=[];
            for j=1:numel(app.U.EffectAxes), cla(app.U.EffectAxes{j},'reset'); end
            for ax=[app.U.ResponseMap,app.U.SatisfactionMap,app.U.EffectRangeAxes]
                colorbar(ax,'off'); cla(ax,'reset');
            end
            app.U.ResponseMap.Tag='ResponseMap'; app.U.SatisfactionMap.Tag='SatisfactionMap';
            app.U.AnalysisNote.Text='固定値・平面・モデル・目的が変わった場合は「描画・更新」を押してください。';
        end
        function plotResponseAnalysis(app)
            if isempty(app.Landscape), return; end
            view=app.Landscape; cfg=view.Config; j=app.responseIndex('AnalysisResponse');
            responseName=cfg.Responses.Name{j};
            for k=1:numel(view.Profiles)
                profile=view.Profiles{k}; ax=app.U.EffectAxes{k}; cla(ax,'reset');
                yyaxis(ax,'left'); plot(ax,profile.X,profile.Prediction(:,j),'LineWidth',1.5);
                ylabel(ax,responseName,'Interpreter','none');
                if strcmp(cfg.Responses.Goal{j},'target'), yline(ax,cfg.Responses.Target(j),'k:','目標'); end
                xline(ax,view.Anchor(k),'k:');
                yyaxis(ax,'right'); plot(ax,profile.X,profile.Satisfaction(:,j),'--','LineWidth',1.2);
                ylim(ax,[0,1]); ylabel(ax,'応答の満足度');
                xlabel(ax,cfg.Factors.Name{k},'Interpreter','none'); title(ax,'他因子を固定した応答'); grid(ax,'on');
            end
            ax=app.U.EffectRangeAxes; cla(ax,'reset'); bar(ax,view.Ranges(:,j));
            ax.XTick=1:height(cfg.Factors); ax.XTickLabel=cfg.Factors.Name; ax.TickLabelInterpreter='none';
            ylabel(ax,[responseName,' の予測変化幅'],'Interpreter','none'); grid(ax,'on');
            title(ax,'固定断面のmax−min（制約外を含む／因果効果・全域の重要度ではない）');
            modeLabel='名目条件';
            if strcmp(view.Mode,'scenarios'), modeLabel=sprintf('条件変動の平均（%dシナリオ）',view.ScenarioCount); end
            app.U.AnalysisNote.Text=[modeLabel,'。実線=予測応答、破線=応答の満足度。' ...
                '平面以外の因子はFixedに固定。満足度0〜1、総合は全応答の幾何平均。灰色は全応答の制約違反。' ...
                '表示用の満足度はPareto探索の損失・リスク重みとは別の指標です。'];
            if isempty(view.Plane)
                cla(app.U.ResponseMap,'reset'); cla(app.U.SatisfactionMap,'reset');
                text(app.U.SatisfactionMap,0.5,0.5,'2因子以上で平面を表示します。','HorizontalAlignment','center'); return
            end
            plane=view.Plane; pair=plane.Pair;
            raw=plane.Prediction(:,:,j); ax=app.U.ResponseMap; colorbar(ax,'off'); cla(ax,'reset'); ax.Tag='ResponseMap';
            imagesc(ax,plane.XValues,plane.YValues,raw); ax.YDir='normal';
            app.labelResponsePlane(ax,cfg,pair); title(ax,[responseName,' の予測応答'],'Interpreter','none');
            app.drawPlaneReference(ax,plane,view.Anchor); colorbar(ax); ax.Tag='ResponseMap';
            ax=app.U.SatisfactionMap; colorbar(ax,'off'); cla(ax,'reset'); ax.Tag='SatisfactionMap';
            if ~isempty(view.CalibrationNote)
                colorbar(ax,'off'); text(ax,0.5,0.5,view.CalibrationNote,'Units','normalized', ...
                    'HorizontalAlignment','center','Interpreter','none'); app.U.AnalysisNote.Text=view.CalibrationNote; return
            end
            if strcmp(app.U.AnalysisScore.Value,'overall')
                score=plane.Overall; scoreName='総合満足度（全応答の幾何平均）';
            else
                score=plane.Satisfaction(:,:,j); scoreName=[responseName,' の満足度'];
            end
            imagesc(ax,plane.XValues,plane.YValues,score,'AlphaData',double(plane.Feasible));
            ax.YDir='normal'; ax.Color=[0.8,0.8,0.8]; ax.CLim=[0,1];
            app.labelResponsePlane(ax,cfg,pair); title(ax,scoreName,'Interpreter','none');
            app.drawPlaneReference(ax,plane,view.Anchor);
            barHandle=colorbar(ax); barHandle.Label.String='満足度（0〜1）';
            ax.Tag='SatisfactionMap';
        end
        function labelResponsePlane(~,ax,cfg,pair)
            xlabel(ax,cfg.Factors.Name{pair(1)},'Interpreter','none');
            ylabel(ax,cfg.Factors.Name{pair(2)},'Interpreter','none');
            xlim(ax,[cfg.Factors.Min(pair(1)),cfg.Factors.Max(pair(1))]);
            ylim(ax,[cfg.Factors.Min(pair(2)),cfg.Factors.Max(pair(2))]); colormap(ax,parula(256));
        end
        function drawPlaneReference(~,ax,plane,anchor)
            hold(ax,'on');
            if any(plane.Feasible(:)) && any(~plane.Feasible(:))
                contour(ax,plane.XValues,plane.YValues,double(plane.Feasible),[0.5,0.5],'k--');
            end
            scatter(ax,anchor(plane.Pair(1)),anchor(plane.Pair(2)),70,'p','filled', ...
                'MarkerFaceColor','w','MarkerEdgeColor','k'); hold(ax,'off');
        end
        function modelChanged(app)
            app.invalidate('models'); app.updateModelControls();
        end
        function updateModelControls(app)
            if ~app.Busy && strcmp(app.U.ModelMethod.Value,'GPR'), app.U.GPRKernel.Enable='on';
            else, app.U.GPRKernel.Enable='off'; end
        end
        function cfg=captureConfig(app)
            cfg=app.Config; cfg.Factors=app.U.Factors.Data; cfg.Responses=app.U.Responses.Data;
            cfg.Seed=app.U.Seed.Value; cfg.Wafer.GridSize=app.U.GridSize.Value;
            cfg.Design.Method=app.U.DesignMethod.Value; cfg.Design.Runs=app.U.Runs.Value;
            cfg.Design.Basis=app.U.DesignBasis.Value; cfg.Design.LatinLevels=app.U.LatinLevels.Value;
            cfg.Model.Method=app.U.ModelMethod.Value; cfg.Model.Basis=app.U.ModelBasis.Value;
            cfg.Model.Folds=app.U.Folds.Value; cfg.Model.Interactions=app.U.Interactions.Value;
            cfg.Model.Kernel=app.U.GPRKernel.Value;
            cfg.Optimization.Population=app.U.Population.Value; cfg.Optimization.Generations=app.U.Generations.Value;
            cfg.Optimization.Scenarios=app.U.Scenarios.Value; cfg.Optimization.RiskWeight=app.U.RiskWeight.Value;
            cfg.Optimization.ValidationPoints=app.U.ValidationPoints.Value;
            cfg=processopt.validateConfig(cfg); app.Config=cfg;
        end
        function applyConfig(app,cfg)
            app.Config=cfg; app.U.Factors.Data=cfg.Factors; app.U.Responses.Data=cfg.Responses;
            app.U.Seed.Value=cfg.Seed; app.U.GridSize.Value=cfg.Wafer.GridSize;
            app.U.DesignMethod.Value=cfg.Design.Method; app.U.Runs.Value=cfg.Design.Runs;
            app.U.DesignBasis.Value=cfg.Design.Basis; app.U.LatinLevels.Value=cfg.Design.LatinLevels;
            app.U.ModelMethod.Value=cfg.Model.Method; app.U.ModelBasis.Value=cfg.Model.Basis;
            app.U.Folds.Value=cfg.Model.Folds; app.U.Interactions.Value=cfg.Model.Interactions;
            app.U.GPRKernel.Value=cfg.Model.Kernel;
            app.U.Population.Value=cfg.Optimization.Population; app.U.Generations.Value=cfg.Optimization.Generations;
            app.U.Scenarios.Value=cfg.Optimization.Scenarios; app.U.RiskWeight.Value=cfg.Optimization.RiskWeight;
            app.U.ValidationPoints.Value=cfg.Optimization.ValidationPoints;
            app.refreshResponseMenus();
            app.refreshAnalysisMenus(); app.updateModelControls();
        end
        function run(app,action)
            if app.Busy, return; end
            app.Busy=true; app.enableInputs(false); cleanup=onCleanup(@()app.finish());
            try
                action();
            catch problem
                if isvalid(app) && ~isempty(app.Figure) && isvalid(app.Figure)
                    app.setStatus(['エラー: ',problem.message]);
                    if strcmp(app.Figure.Visible,'on')
                        uialert(app.Figure,problem.message,'処理を実行できません');
                    else
                        rethrow(problem);
                    end
                else
                    rethrow(problem);
                end
            end
        end
        function finish(app)
            if isvalid(app)
                app.Busy=false;
                if ~isempty(app.Figure) && isvalid(app.Figure)
                    app.enableInputs(true); app.U.Cancel.Enable='off';
                    app.updateModelControls();
                end
            end
        end
        function enableInputs(app,enable)
            controls=findall(app.Figure,'-property','Enable');
            if enable, state='on'; else, state='off'; end
            for j=1:numel(controls), controls(j).Enable=state; end
            app.U.Cancel.Enable='off';
        end
        function invalidate(app,level)
            if ismember(level,{'data','plan'})
                app.Plan=[];
                if strcmp(level,'plan')
                    % An imported dataset is independent of a new planning choice.
                    if ~isempty(app.Data), return; end
                end
            end
            if strcmp(level,'data'), app.Data=[]; app.U.DataTable.Data=table(); end
            if ismember(level,{'data','models','plan'})
                app.Bundle=[]; app.Diagnostic=[]; app.U.Metrics.Data=table();
                cla(app.U.FitAxes); cla(app.U.ResidualAxes);
            end
            app.Result=[]; app.Selected=[]; app.U.Candidates.Data=table(); cla(app.U.ParetoAxes);
            app.clearResponseAnalysis();
            app.clearVerification(); app.setStatus('設定が変わりました。必要な処理を再実行してください。');
        end
        function clearVerification(app)
            app.Verification=[]; app.U.TruthMetrics.Data=table(); app.U.Comparison.Data=table();
            cla(app.U.TruthAxes); cla(app.U.ImprovementAxes); cla(app.U.BaselineWafer); cla(app.U.CandidateWafer);
            app.Confirmation=[]; app.U.ConfirmationMetrics.Data=table(); app.U.ConfirmationTable.Data=table(); cla(app.U.ConfirmationAxes);
        end
        function factorEdited(app,e)
            name=app.U.Factors.Data.Properties.VariableNames{e.Indices(2)};
            if ismember(name,{'Current','JitterStd'}), app.invalidate('results');
            else, app.invalidate('data'); app.refreshAnalysisMenus(); end
        end
        function responseEdited(app,e)
            name=app.U.Responses.Data.Properties.VariableNames{e.Indices(2)};
            if ismember(name,{'Goal','Target','Scale','Lower','Upper'}), app.invalidate('results');
            else, app.invalidate('data'); end
        end
        function selectFactor(app,e)
            if ~isempty(e.Indices), app.FactorRow=e.Indices(1); end
        end
        function selectResponse(app,e)
            if ~isempty(e.Indices), app.ResponseRow=e.Indices(1); end
        end
        function addFactor(app)
            T=app.U.Factors.Data;
            if height(T)>=12, return; end
            row=T(1,:); row.Name={app.unusedName('Factor')}; row.Min=-1; row.Max=1; row.Current=0; row.JitterStd=0;
            app.U.Factors.Data=[T;row]; app.invalidate('data'); app.refreshAnalysisMenus();
        end
        function removeFactor(app)
            T=app.U.Factors.Data;
            if height(T)<=1, return; end
            T(min(app.FactorRow,height(T)),:)=[]; app.U.Factors.Data=T; app.FactorRow=1; app.invalidate('data'); app.refreshAnalysisMenus();
        end
        function addResponse(app)
            T=app.U.Responses.Data;
            if height(T)>=12, return; end
            row=T(1,:); row.Name={app.unusedName('Response')}; row.Signal=row.Name;
            row.Goal={'min'}; row.Target=0; row.Scale=1; row.Lower=-Inf; row.Upper=Inf;
            row.NoiseStd=0; row.Metric={'mean'}; row.Formula={'x1'};
            app.U.Responses.Data=[T;row]; app.invalidate('data'); app.refreshResponseMenus();
        end
        function removeResponse(app)
            T=app.U.Responses.Data;
            if height(T)<=1, return; end
            T(min(app.ResponseRow,height(T)),:)=[]; app.U.Responses.Data=T; app.ResponseRow=1;
            app.invalidate('data'); app.refreshResponseMenus();
        end
        function name=unusedName(app,prefix)
            used=[string(app.U.Factors.Data.Name);string(app.U.Responses.Data.Name)]; index=1;
            while any(strcmpi(used,sprintf('%s%d',prefix,index))), index=index+1; end
            name=sprintf('%s%d',prefix,index);
        end
        function loadPreset(app)
            if startsWith(app.U.Preset.Value,'CVD'), preset='CVD'; else, preset='DRY'; end
            app.setConfig(processopt.defaultConfig(preset)); app.setStatus([preset,'の仮想例を読み込みました。']);
        end
        function readCSV(app,layout)
            [name,folder]=uigetfile('*.csv','測定CSV'); if isequal(name,0), return; end
            app.run(@work);
            function work()
                cfg=app.captureConfig(); T=readtable(fullfile(folder,name),'VariableNamingRule','preserve');
                incoming=processopt.importData(T,cfg,layout);
                app.invalidate('data'); app.Data=incoming; app.displayData();
                app.setStatus(sprintf('%d実験の測定値を取り込みました。',size(incoming.X,1)));
            end
        end
        function readConfirmation(app,layout)
            if isempty(app.Result) || isempty(app.Selected), app.setStatus('先に探索し、候補を選択してください。'); return; end
            [name,folder]=uigetfile('*.csv','Role列を持つ追加実験CSV'); if isequal(name,0), return; end
            app.run(@work);
            function work()
                cfg=app.captureConfig(); T=readtable(fullfile(folder,name),'VariableNamingRule','preserve');
                app.Confirmation=processopt.confirmExperiment(cfg,app.Bundle,app.Result,app.Selected,T,layout);
                c=app.Confirmation; app.U.ConfirmationMetrics.Data=c.Metrics; app.U.ConfirmationTable.Data=c.Comparison;
                ax=app.U.ConfirmationAxes; cla(ax); bar(ax,[c.Comparison.BaselineLoss,c.Comparison.CandidateLoss]);
                ax.XTick=1:height(cfg.Responses); ax.XTickLabel=cfg.Responses.Name;
                ylabel(ax,'実測による平均損失（小さいほどよい）'); legend(ax,{'元条件','選択候補'},'Location','best'); grid(ax,'on');
                title(ax,'追加実験による効果確認');
                app.setStatus(sprintf('実測の全Waferが制約内: 元条件 %d、候補 %d。繰返し数と損失差を確認してください。',c.BaselineAllFeasible,c.CandidateAllFeasible));
            end
        end
        function displayData(app)
            cfg=app.Config;
            names=[cellstr(string(cfg.Factors.Name));cellstr(string(cfg.Responses.Name))];
            T=array2table([app.Data.X,app.Data.Y],'VariableNames',names);
            T=addvars(T,(1:height(T))','Before',1,'NewVariableNames','RunID'); app.U.DataTable.Data=T;
        end
        function refreshResponseMenus(app)
            names=cellstr(string(app.U.Responses.Data.Name));
            controls={'DiagnosticResponse','ParetoX','ParetoY','VerifyResponse','AnalysisResponse'};
            for j=1:numel(controls), app.U.(controls{j}).Items=names; app.U.(controls{j}).Value=names{1}; end
            app.U.ParetoY.Value=names{min(2,numel(names))};
        end
        function j=responseIndex(app,control)
            j=find(strcmp(string(app.Config.Responses.Name),string(app.U.(control).Value)),1);
            if isempty(j), j=1; end
        end
        function plotDiagnostic(app)
            if isempty(app.Diagnostic), return; end
            j=app.responseIndex('DiagnosticResponse'); d=app.Diagnostic;
            ax=app.U.FitAxes; cla(ax); scatter(ax,d.Observed(:,j),d.OOF(:,j),30,d.FoldID,'filled');
            hold(ax,'on'); bounds=[min([d.Observed(:,j);d.OOF(:,j)]),max([d.Observed(:,j);d.OOF(:,j)])];
            plot(ax,bounds,bounds,'k--'); hold(ax,'off'); grid(ax,'on');
            xlabel(ax,'実測 / 仮想測定'); ylabel(ax,'検証側の予測'); title(ax,'交差検証: 実測と予測');
            ax=app.U.ResidualAxes; cla(ax); scatter(ax,d.OOF(:,j),d.Residual(:,j),30,d.FoldID,'filled');
            yline(ax,0,'k--'); xlabel(ax,'検証側の予測'); ylabel(ax,'実測 − 予測'); title(ax,'交差検証の残差'); grid(ax,'on');
        end
        function T=candidateTable(app)
            if isempty(app.Result), T=table(); return; end
            cfg=app.Config; e=app.Result.Evaluation;
            names=[strcat('Factor_',string(cfg.Factors.Name));strcat('Pred_',string(cfg.Responses.Name)); ...
                strcat('SD_',string(cfg.Responses.Name));strcat('Loss_',string(cfg.Responses.Name))];
            T=array2table([app.Result.X,e.Prediction,e.ResponseSD,e.Objectives],'VariableNames',cellstr(names));
            T=addvars(T,(1:height(T))','Before',1,'NewVariableNames','CandidateID');
        end
        function plotPareto(app)
            ax=app.U.ParetoAxes; cla(ax);
            if isempty(app.Result) || isempty(app.Result.X), return; end
            a=app.responseIndex('ParetoX'); b=app.responseIndex('ParetoY'); F=app.Result.Evaluation.Objectives;
            scatter(ax,F(:,a),F(:,b),36,(1:size(F,1))','filled'); hold(ax,'on');
            if ~isempty(app.Selected), scatter(ax,F(app.Selected,a),F(app.Selected,b),110,'r','LineWidth',2); end
            hold(ax,'off'); grid(ax,'on');
            xlabel(ax,[app.Config.Responses.Name{a},' 損失']); ylabel(ax,[app.Config.Responses.Name{b},' 損失']);
            title(ax,'全目的で判定した非劣解の2軸表示（全て最小化）');
        end
        function selectCandidate(app,e)
            if isempty(e.Indices) || isempty(app.Result), return; end
            app.Selected=e.Indices(1); app.clearVerification(); app.plotPareto();
            app.setStatus(sprintf('候補%dを選択しました。「効果・真値検証」で比較できます。',app.Selected));
        end
        function updateVerificationPlots(app)
            app.plotVerification(); app.plotWafer();
        end
        function plotVerification(app)
            if isempty(app.Verification), return; end
            d=app.Verification; j=app.responseIndex('VerifyResponse');
            ax=app.U.TruthAxes; cla(ax); scatter(ax,d.Truth(:,j),d.Prediction(:,j),20,'filled');
            hold(ax,'on'); bounds=[min([d.Truth(:,j);d.Prediction(:,j)]),max([d.Truth(:,j);d.Prediction(:,j)])];
            plot(ax,bounds,bounds,'k--'); hold(ax,'off'); grid(ax,'on'); xlabel(ax,'真値'); ylabel(ax,'モデル予測'); title(ax,'独立した条件での誤差');
            ax=app.U.ImprovementAxes; cla(ax); bar(ax,[d.Actual.Objectives(1,:)',d.Actual.Objectives(2,:)']);
            ax.XTick=1:height(app.Config.Responses); ax.XTickLabel=app.Config.Responses.Name;
            ylabel(ax,'正規化した損失（小さいほどよい）'); legend(ax,{'元条件','選択候補'},'Location','best'); grid(ax,'on'); title(ax,'真の式で効果を確認');
        end
        function plotWafer(app)
            if isempty(app.Verification), return; end
            cfg=app.Config; j=app.responseIndex('VerifyResponse'); points=[cfg.Factors.Current';app.Result.X(app.Selected,:)];
            [~,w]=processopt.simulate(cfg,points,false); values=w.Values{j}; range=[min(values(:)),max(values(:))];
            if range(1)==range(2), range=range+[-1,1]*max(1,abs(range(1)))*0.01; end
            axesList={app.U.BaselineWafer,app.U.CandidateWafer}; labels={'元条件','選択候補'};
            for k=1:2
                ax=axesList{k}; cla(ax); scatter(ax,w.U,w.V,35,values(k,:),'filled'); axis(ax,'equal');
                xlim(ax,[-1.1,1.1]); ylim(ax,[-1.1,1.1]); ax.CLim=range; colorbar(ax);
                title(ax,[labels{k},': ',cfg.Responses.Signal{j},'（変動なしの真値）']);
            end
        end
        function exportPlan(app)
            if isempty(app.Plan), app.setStatus('先に実験計画を作成してください。'); return; end
            app.writeCSV(app.Plan.Table,'experiment_plan.csv');
        end
        function exportData(app)
            if isempty(app.Data), app.setStatus('学習データがありません。'); return; end
            names=[cellstr(string(app.Config.Factors.Name));cellstr(string(app.Config.Responses.Name))];
            app.writeCSV(array2table([app.Data.X,app.Data.Y],'VariableNames',names),'training_data.csv');
        end
        function exportCoefficients(app)
            if isempty(app.Diagnostic), return; end
            j=app.responseIndex('DiagnosticResponse'); T=app.Diagnostic.Coefficients{j};
            if isempty(T), app.setStatus('回帰係数の書出しはPolynomialを選択してください。'); return; end
            app.writeCSV(T,'polynomial_coefficients.csv');
        end
        function writeCSV(app,T,suggestion)
            [name,folder]=uiputfile('*.csv','CSVに保存',suggestion); if isequal(name,0), return; end
            app.run(@()writetable(T,fullfile(folder,name),'Encoding','UTF-8'));
        end
        function exportResults(app)
            if isempty(app.Result), app.setStatus('探索結果がありません。'); return; end
            folder=uigetdir(pwd,'結果の保存先'); if isequal(folder,0), return; end
            app.run(@work);
            function work()
                % A new timestamped subfolder keeps prior results intact.
                [~,uniqueName]=fileparts(tempname(folder)); timestamp=char(datetime('now','Format','yyyyMMdd_HHmmss'));
                output=fullfile(folder,['processopt_',timestamp,'_',uniqueName]); mkdir(output);
                writetable(app.candidateTable(),fullfile(output,'pareto_candidates.csv'),'Encoding','UTF-8');
                writetable(app.Diagnostic.Metrics,fullfile(output,'cross_validation.csv'),'Encoding','UTF-8');
                history=array2table(app.Result.History,'VariableNames',{'Generation','FeasibleCount','MinimumViolation'});
                writetable(history,fullfile(output,'search_history.csv'));
                if ~isempty(app.Verification)
                    writetable(app.Verification.Metrics,fullfile(output,'independent_truth_errors.csv'));
                    writetable(app.Verification.Comparison,fullfile(output,'baseline_comparison.csv'));
                    names=[strcat('TruthLoss_',string(app.Config.Responses.Name));"Feasible";"Nondominated"];
                    truthTable=array2table([app.Verification.FrontTruth.Objectives, ...
                        app.Verification.FrontTruth.Feasible,app.Verification.TrueNondominated], 'VariableNames',cellstr(names));
                    truthTable=addvars(truthTable,(1:height(truthTable))','Before',1,'NewVariableNames','CandidateID');
                    writetable(truthTable,fullfile(output,'pareto_truth_check.csv'));
                end
                if ~isempty(app.Confirmation)
                    writetable(app.Confirmation.Metrics,fullfile(output,'confirmation_errors.csv'));
                    writetable(app.Confirmation.Comparison,fullfile(output,'confirmation_comparison.csv'));
                end
                cfg=app.captureConfig(); selectedCandidate=app.Selected; %#ok<NASGU>
                save(fullfile(output,'settings.mat'),'cfg','selectedCandidate');
                app.setStatus(['結果を保存: ',output]);
            end
        end
        function saveProject(app)
            [name,folder]=uiputfile('*.mat','プロジェクト保存','process_project.mat'); if isequal(name,0), return; end
            app.run(@()app.saveProjectFile(fullfile(folder,name)));
        end
        function loadProject(app)
            [name,folder]=uigetfile('*.mat','信頼するローカルプロジェクトMATを選択'); if isequal(name,0), return; end
            app.run(@()app.loadProjectFile(fullfile(folder,name)));
        end
        function progress(app,message)
            app.setStatus(message); drawnow;
        end
        function setStatus(app,message)
            if isfield(app.U,'Status') && isvalid(app.U.Status), app.U.Status.Text=message; end
        end
        function requestStop(app)
            app.StopRequested=true; app.setStatus('現在の世代の処理後に探索を中止します。');
        end
        function closeRequested(app)
            if app.Busy, app.requestStop(); app.setStatus('処理の終了後にウィンドウを閉じてください。');
            else, delete(app); end
        end
    end
end
