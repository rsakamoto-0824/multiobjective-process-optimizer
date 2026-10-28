classdef TestProcessOptimizer < matlab.unittest.TestCase
    methods (TestClassSetup)
        function addApplicationPath(test)
            root=fileparts(fileparts(mfilename('fullpath')));
            test.applyFixture(matlab.unittest.fixtures.PathFixture(root));
        end
    end
    methods (Test)
        function presetsAreValid(test)
            for name={'CVD','DRY'}
                cfg=processopt.validateConfig(processopt.defaultConfig(name{1}));
                test.verifyEqual(height(cfg.Factors),3);
            end
        end
        function arithmeticParserMatchesIndependentCalculation(test)
            X=[2,3;4,5]; u=[-1,0,1]; v=[0,0.5,0];
            actual=processopt.expression('-x1^2+2*x1*x2+sin(pi*u)+max(v,0.1)',X,u,v);
            expected=-X(:,1).^2+2*X(:,1).*X(:,2)+sin(pi*u)+max(v,0.1);
            test.verifyEqual(actual,expected,'AbsTol',1e-12);
            test.verifyEqual(processopt.expression('2^3^2',X,u,v),512*ones(2,3));
            test.verifyEqual(processopt.expression('-2^2',X,u,v),-4*ones(2,3));
        end
        function parserRejectsCodeAndNonfiniteValues(test)
            for source={'system(1)','x1;1','x99','sqrt(-1)','1/0','x1(1)','rand()','1+','x1..*2'}
                test.rejects(@()processopt.expression(source{1},[1,2],0,0));
            end
        end
        function aggregationDefinitions(test)
            test.verifyEqual(processopt.aggregate([1,2,3],'mean'),2);
            test.verifyEqual(processopt.aggregate([1,2,3],'std'),1);
            test.verifyEqual(processopt.aggregate([1,2,3],'cv'),50);
            test.verifyEqual(processopt.aggregate([1,2,3],'nu'),50);
            test.verifyEqual(processopt.aggregate([-1,-2,-3],'cv'),50);
            test.verifyEqual(processopt.aggregate([1,2,3],'rms'),sqrt(14/3),'AbsTol',1e-12);
            test.rejects(@()processopt.aggregate([-1,1],'cv'));
            test.rejects(@()processopt.aggregate(1,'std'));
        end
        function optimalDesignsAreEstimableBoundedAndRepeatable(test)
            cfg=processopt.defaultConfig(); cfg.Design.Restarts=1; cfg.Design.Passes=1;
            for method={'D-optimal','I-optimal'}
                cfg.Design.Method=method{1}; state=rng;
                plan=processopt.makeDesign(cfg); same=processopt.makeDesign(cfg);
                test.verifyEqual(rng,state); test.verifyEqual(plan.X,same.X);
                test.verifyEqual(plan.Rank,10); test.verifyEqual(size(plan.X),[40,3]);
                test.verifyTrue(all(all(plan.X>=cfg.Factors.Min' & plan.X<=cfg.Factors.Max')));
            end
        end
        function dsdHasOrthogonalMainEffectsAndNoSecondOrderAlias(test)
            cfg=processopt.defaultConfig(); cfg.Design.Method='DSD';
            plan=processopt.makeDesign(cfg); z=processopt.scale(plan.X,cfg,'code');
            F=processopt.basis(z,'quadratic'); second=F(:,5:end);
            test.verifyEqual(z'*z,10*eye(3),'AbsTol',1e-12);
            test.verifyEqual(z'*second,zeros(3,6),'AbsTol',1e-12);
            test.verifyEqual(sum(z,1),zeros(1,3)); test.verifyEqual(size(z,1),13);
            % Projecting a six-column design to three factors adds enough runs
            % for the full matrix, although CV subsets can still be deficient.
            test.verifyEqual(plan.Rank,plan.Terms);
        end
        function latinSquareIsBalanced(test)
            cfg=processopt.defaultConfig(); cfg.Design.Method='Latin square';
            plan=processopt.makeDesign(cfg); T=plan.Table;
            test.verifyEqual(height(T),16);
            for k=1:4
                test.verifyEqual(sort(T.Treatment(T.RowBlock==k)),(1:4)');
                test.verifyEqual(sort(T.Treatment(T.ColumnBlock==k)),(1:4)');
            end
        end
        function latinBlocksAreCategoricalAndFixedDuringSearch(test)
            cfg=processopt.defaultConfig(); cfg.Design.Method='Latin square'; cfg.Design.LatinLevels=5;
            cfg.Factors.JitterStd(:)=0; cfg.Model.Folds=3;
            cfg.Responses=cfg.Responses(1,:); cfg.Responses.Lower=-Inf; cfg.Responses.Upper=Inf;
            cfg.Responses.Goal={'min'}; cfg.Optimization.Population=12; cfg.Optimization.Generations=2;
            plan=processopt.makeDesign(cfg); z=processopt.scale(plan.X,cfg,'code');
            effectA=[4,1,0,3,2]; effectB=[1,4,0,2,3];
            idA=round((z(:,1)+1)*2)+1; idB=round((z(:,2)+1)*2)+1;
            y=effectA(idA)'+effectB(idB)'+(z(:,3)-0.2).^2;
            data=struct('X',plan.X,'Y',y,'DesignMethod','Latin square','LatinLevels',5);
            [bundle,d]=processopt.fitModels(cfg,data);
            test.verifyLessThan(d.Metrics.CV_RMSE,1e-10);
            result=processopt.optimize(cfg,bundle,data);
            test.verifyEqual(result.PopulationX(:,1:2),repmat(cfg.Factors.Current(1:2)',12,1),'AbsTol',1e-10);
            for method={'GPR','GAM'}
                cfg.Model.Method=method{1}; fitted=processopt.fitModels(cfg,data);
                predicted=processopt.predictModels(fitted,cfg.Factors.Current');
                test.verifyTrue(isfinite(predicted));
            end
        end
        function lhsUsesEveryStratumOnce(test)
            cfg=processopt.defaultConfig(); cfg.Design.Method='Latin hypercube';
            plan=processopt.makeDesign(cfg); z=(processopt.scale(plan.X,cfg,'code')+1)/2;
            test.verifyEqual(sort(floor(z*40),1),repmat((0:39)',1,3));
        end
        function sharedSignalAndRandomSeedAreConsistent(test)
            cfg=processopt.defaultConfig(); X=repmat(cfg.Factors.Current',3,1);
            state=rng; [Y,w]=processopt.simulate(cfg,X,true);
            test.verifyEqual(rng,state);
            test.verifyEqual(w.Values{1},w.Values{2});
            test.verifyEqual(Y(:,2),processopt.aggregate(w.Values{1},'nu'));
            test.verifyEqual(Y,processopt.simulate(cfg,X,true));
        end
        function compileTimeCustomTruthIsSupported(test)
            cfg=processopt.defaultConfig(); cfg.Responses=cfg.Responses(1,:);
            cfg.Responses.Formula={'custom'}; cfg.Responses.Signal={'CustomExample'};
            X=cfg.Factors.Current'; test.verifyEqual(processopt.simulate(cfg,X),X(1),'AbsTol',1e-10);
        end
        function longImportAggregatesSameWaferMeasurements(test)
            cfg=processopt.defaultConfig(); X=[cfg.Factors.Current';cfg.Factors.Min'];
            [Y,w]=processopt.simulate(cfg,X,true); sites=numel(w.U);
            T=array2table(kron(X,ones(sites,1)),'VariableNames',cfg.Factors.Name);
            T.RunID=kron((1:2)',ones(sites,1)); T.WaferX=repmat(w.U',2,1); T.WaferY=repmat(w.V',2,1);
            T.Thickness=reshape(w.Values{1}',[],1); T.Warp=reshape(w.Values{3}',[],1);
            data=processopt.importData(T,cfg,'long');
            test.verifyEqual(data.X,X); test.verifyEqual(data.Y,Y,'AbsTol',1e-12);
            test.rejects(@()processopt.importData([T;T(1,:)],cfg,'long'));
            T.Temperature(2)=T.Temperature(2)+1;
            test.rejects(@()processopt.importData(T,cfg,'long'));
        end
        function wideImportRejectsMissingAndOutOfRange(test)
            cfg=processopt.defaultConfig(); names=[cfg.Factors.Name;cfg.Responses.Name];
            X=repmat(cfg.Factors.Current',4,1); Y=processopt.simulate(cfg,X);
            T=array2table([X,Y],'VariableNames',names);
            data=processopt.importData(T,cfg,'wide'); test.verifyEqual(data.Y,Y);
            T.Thickness(1)=NaN; test.rejects(@()processopt.importData(T,cfg,'wide'));
            T.Thickness(1)=100; T.Temperature(1)=cfg.Factors.Max(1)+1;
            test.rejects(@()processopt.importData(T,cfg,'wide'));
        end
        function exactQuadraticAndGroupedValidation(test)
            cfg=processopt.defaultConfig(); cfg.Design.Method='Latin hypercube';
            plan=processopt.makeDesign(cfg); X=[plan.X;plan.X(1:5,:)];
            z=processopt.scale(X,cfg,'code'); F=processopt.basis(z,'quadratic');
            beta=reshape(1:30,10,3)/10; Y=F*beta;
            [bundle,d]=processopt.fitModels(cfg,struct('X',X,'Y',Y));
            test.verifyLessThan(max(d.Metrics.CV_RMSE),1e-10);
            test.verifyEqual(d.FoldID(1:5),d.FoldID(41:45));
            newX=cfg.Factors.Current'; expected=processopt.basis(processopt.scale(newX,cfg,'code'),'quadratic')*beta;
            test.verifyEqual(processopt.predictModels(bundle,newX),expected,'AbsTol',1e-10);
        end
        function underdeterminedPolynomialIsRejected(test)
            cfg=processopt.defaultConfig(); cfg.Design.Method='DSD'; plan=processopt.makeDesign(cfg);
            Y=processopt.simulate(cfg,plan.X);
            test.rejects(@()processopt.fitModels(cfg,struct('X',plan.X,'Y',Y)));
        end
        function gprAndGamTrainAndPredict(test)
            cfg=processopt.defaultConfig(); cfg.Design.Method='Latin hypercube'; cfg.Model.Folds=2;
            plan=processopt.makeDesign(cfg); Y=processopt.simulate(cfg,plan.X,true);
            for method={'GPR','GAM'}
                cfg.Model.Method=method{1};
                [bundle,d]=processopt.fitModels(cfg,struct('X',plan.X,'Y',Y));
                predicted=processopt.predictModels(bundle,plan.X(1:3,:));
                test.verifySize(predicted,[3,3]); test.verifyTrue(all(isfinite(predicted(:))));
                test.verifyTrue(all(isfinite(d.Metrics.CV_RMSE)));
            end
        end
        function kernelSelectionUsesAllSupportedKernels(test)
            cfg=processopt.defaultConfig(); cfg.Factors=cfg.Factors(1,:);
            cfg.Factors.Min=0; cfg.Factors.Max=1; cfg.Factors.Current=0.5;
            cfg.Responses=cfg.Responses(1,:); cfg.Model.Method='GPR'; cfg.Model.Folds=2;
            X=linspace(0,1,18)'; Y=sin(4*X)+0.05*cos(17*X);
            for kernel=processopt.gprKernels()
                cfg.Model.Kernel=kernel{1};
                [bundle,d]=processopt.fitModels(cfg,struct('X',X,'Y',Y));
                test.verifyEqual(lower(bundle.Models{1}.Fit.KernelInformation.Name),kernel{1});
                test.verifyEqual(d.Metrics.GPR_Kernel,string(kernel{1}));
                test.verifyTrue(all(isfinite(processopt.predictModels(bundle,[0.1;0.7]))));
            end
            legacy=cfg; legacy.Model=rmfield(legacy.Model,'Kernel');
            migrated=processopt.validateConfig(legacy); test.verifyEqual(migrated.Model.Kernel,'ardsquaredexponential');
            cfg.Model.Kernel='unknown'; test.rejects(@()processopt.validateConfig(cfg));
        end
        function satisfactionHasFixedAnchorsAndCorrectDirections(test)
            cfg=processopt.defaultConfig(); cfg.Responses.Goal={'target';'min';'max'};
            cfg.Responses.Lower(:)=0; cfg.Responses.Upper(:)=20; cfg.Responses.Target(1)=10;
            [D,total]=processopt.desirability(cfg,[10,0,20;5,10,10;10,20,20;-1,30,-1]);
            test.verifyEqual(D,[1,1,1;0.5,0.5,0.5;1,0,1;0,0,0]);
            test.verifyEqual(total,[1;0.5;0;0],'AbsTol',1e-12);
            cfg.Responses=cfg.Responses(1,:); cfg.Responses.Target=2; cfg.Responses.Upper=10;
            test.verifyEqual(processopt.desirability(cfg,[0;1;2;6;10]),[0;0.5;1;0.5;0]);
            cfg.Responses.Target=0; test.verifyEqual(processopt.desirability(cfg,[0;5;10]),[1;0.5;0]);
            cfg.Responses.Target=11; test.rejects(@()processopt.desirability(cfg,5));
            cfg.Responses.Upper=Inf; test.rejects(@()processopt.desirability(cfg,5));
        end
        function responsePlaneKeepsOtherFactorsFixedAndAxesOrdered(test)
            cfg=processopt.defaultConfig(); cfg.Factors.Min(:)=0; cfg.Factors.Max(:)=1; cfg.Factors.Current(:)=0.5;
            cfg.Responses=cfg.Responses(1,:); cfg.Responses.Goal={'max'};
            cfg.Responses.Lower=0; cfg.Responses.Upper=10;
            cfg.Design.Method='Latin hypercube'; plan=processopt.makeDesign(cfg); X=plan.X;
            Y=X(:,1)+2*X(:,2)+4*X(:,3)+3*X(:,1).*X(:,2);
            bundle=processopt.fitModels(cfg,struct('X',X,'Y',Y));
            anchor=[0.2,0.3,0.4]; view=processopt.responseLandscape(cfg,bundle,anchor,[2,1],11);
            [horizontal,vertical]=meshgrid(linspace(0,1,11));
            expected=vertical+2*horizontal+1.6+3*vertical.*horizontal;
            test.verifyEqual(view.Plane.Prediction,expected,'AbsTol',1e-10);
            test.verifyEqual(view.Plane.Satisfaction,expected/10,'AbsTol',1e-10);
            test.verifyEqual(view.Ranges,[1.9;2.6;4],'AbsTol',1e-10);
            test.verifyTrue(all(view.Plane.Feasible(:)));
            other=processopt.responseLandscape(cfg,bundle,[0.2,0.3,0.8],[2,1],11);
            test.verifyEqual(other.Plane.Prediction-view.Plane.Prediction,1.6*ones(11),'AbsTol',1e-10);
            test.rejects(@()processopt.responseLandscape(cfg,bundle,anchor,[1,1],11));
        end
        function scenarioSatisfactionIsAveragedAfterTransformation(test)
            cfg=processopt.defaultConfig(); cfg.Factors.Min(:)=0; cfg.Factors.Max(:)=1; cfg.Factors.Current(:)=0.5;
            cfg.Factors.JitterStd(1)=0.2; cfg.Responses=cfg.Responses(1,:);
            cfg.Responses.Target=0.5; cfg.Responses.Lower=0; cfg.Responses.Upper=1;
            cfg.Design.Method='Latin hypercube'; plan=processopt.makeDesign(cfg);
            bundle=processopt.fitModels(cfg,struct('X',plan.X,'Y',plan.X(:,1)));
            view=processopt.responseLandscape(cfg,bundle,[0.5,0.5,0.5],[1,2],11,'scenarios');
            offsets=processopt.scenarios(cfg); expected=mean(max(0,1-2*abs(offsets(:,1))));
            test.verifyEqual(view.Profiles{1}.Satisfaction(31),expected,'AbsTol',1e-10);
            fromMean=max(0,1-2*abs(mean(offsets(:,1))));
            test.verifyLessThan(view.Profiles{1}.Satisfaction(31),fromMean);
            test.verifyFalse(view.Plane.Feasible(1,1));
            cfg.Responses.Upper=Inf;
            unavailable=processopt.responseLandscape(cfg,bundle,[0.5,0.5,0.5],[1,2],11);
            test.verifyNotEmpty(unavailable.CalibrationNote);
            test.verifyTrue(all(isfinite(unavailable.Plane.Prediction(:))));
            test.verifyTrue(all(isnan(unavailable.Plane.Satisfaction(:))));
        end
        function objectiveDirectionsAndRiskAreCorrect(test)
            cfg=processopt.defaultConfig(); cfg.Responses.Goal={'target';'min';'max'};
            cfg.Responses.Target=[10;0;0]; cfg.Responses.Scale=[2;4;5];
            cfg.Responses.Lower(:)=-Inf; cfg.Responses.Upper(:)=Inf;
            X=cfg.Factors.Current'; ev=processopt.evaluate(cfg,X,@(~)[14,8,15],zeros(1,3));
            test.verifyEqual(ev.Objectives,[2,2,-3]); test.verifyTrue(ev.Feasible);
            cfg.Responses=cfg.Responses(1,:); cfg.Responses.Goal={'min'};
            cfg.Responses.Scale=1; cfg.Optimization.RiskWeight=2;
            off=[zeros(1,3);1,0,0;-1,0,0];
            ev=processopt.evaluate(cfg,X,@(a)a(:,1),off);
            test.verifyEqual(ev.Objectives,402,'AbsTol',1e-12);
            test.verifyEqual(ev.ResponseSD,1,'AbsTol',1e-12);
            ev=processopt.evaluate(cfg,cfg.Factors.Min',@(a)a(:,1),off);
            test.verifyFalse(ev.Feasible);
        end
        function feasibilityDominanceUsesEveryObjective(test)
            [rankValue,~]=processopt.rankPopulation([0,2;1,1;2,0;2,2;-100,-100],[0;0;0;0;1]);
            test.verifyEqual(rankValue(1:3),ones(3,1));
            test.verifyGreaterThan(rankValue(4),1); test.verifyGreaterThan(rankValue(5),rankValue(4));
        end
        function optimizerImprovesKnownQuadraticAndIndependentTruth(test)
            cfg=processopt.defaultConfig(); cfg.Responses=cfg.Responses(1,:);
            cfg.Responses.Formula={'(x1-390)^2+0.1*(x2-3)^2+0.01*(x3-100)^2'};
            cfg.Responses.Goal={'min'}; cfg.Responses.Lower=-Inf; cfg.Responses.Upper=Inf;
            cfg.Responses.NoiseStd=0; cfg.Optimization.Population=24; cfg.Optimization.Generations=20;
            cfg.Design.Method='Latin hypercube'; plan=processopt.makeDesign(cfg);
            data=struct('X',plan.X,'Y',processopt.simulate(cfg,plan.X));
            bundle=processopt.fitModels(cfg,data); result=processopt.optimize(cfg,bundle,data);
            test.verifyNotEmpty(result.X); test.verifyLessThan(min(result.Evaluation.Objectives),1);
            report=processopt.verify(cfg,bundle,result);
            test.verifyLessThan(max(report.Metrics.Truth_RMSE),1e-8);
            test.verifyGreaterThan(report.Comparison.LossImprovement,0);
            test.verifyTrue(report.Actual.Feasible(2));
        end
        function infeasibleResultsAreNotRecommended(test)
            cfg=processopt.defaultConfig(); cfg.Responses=cfg.Responses(1,:);
            cfg.Responses.Lower=1e8; cfg.Responses.Upper=Inf;
            cfg.Optimization.Population=12; cfg.Optimization.Generations=1;
            cfg.Design.Method='Latin hypercube'; plan=processopt.makeDesign(cfg);
            data=struct('X',plan.X,'Y',processopt.simulate(cfg,plan.X));
            bundle=processopt.fitModels(cfg,data); result=processopt.optimize(cfg,bundle,data);
            test.verifyEmpty(result.Compromise); test.verifyEmpty(result.X);
        end
        function measuredConfirmationUsesIndependentData(test)
            cfg=processopt.defaultConfig(); cfg.Responses=cfg.Responses(1,:);
            cfg.Responses.Formula={'(x1-390)^2'}; cfg.Responses.Goal={'min'};
            cfg.Responses.Lower=-Inf; cfg.Responses.Upper=Inf;
            cfg.Design.Method='Latin hypercube'; plan=processopt.makeDesign(cfg);
            data=struct('X',plan.X,'Y',processopt.simulate(cfg,plan.X)); bundle=processopt.fitModels(cfg,data);
            result=struct('X',[390,3,100]);
            X=[cfg.Factors.Current';cfg.Factors.Current';result.X;result.X];
            T=array2table([X,[102;98;2;4]],'VariableNames',[cfg.Factors.Name;cfg.Responses.Name]);
            T.Role={'baseline';'baseline';'candidate';'candidate'};
            report=processopt.confirmExperiment(cfg,bundle,result,1,T,'wide');
            test.verifyEqual(report.Comparison.LossImprovement,97/cfg.Responses.Scale,'AbsTol',1e-12);
            test.verifyEqual(report.Comparison.BaselineN,2);
            T.Temperature(3)=391;
            test.rejects(@()processopt.confirmExperiment(cfg,bundle,result,1,T,'wide'));
        end
        function uiWorkflowRunsWithoutDialogs(test)
            app=ProcessOptimizerApp('off'); cleanup=onCleanup(@()delete(app));
            cfg=processopt.defaultConfig(); cfg.Design.Method='Latin hypercube';
            cfg.Optimization.Population=12; cfg.Optimization.Generations=2;
            app.setConfig(cfg); app.generatePlan(); app.simulateData(); app.trainModels(); app.optimizeModels();
            test.verifyNotEmpty(app.Bundle); test.verifyNotEmpty(app.Result);
            if ~isempty(app.Selected), app.verifyTruth(); test.verifyNotEmpty(app.Verification); end
        end
        function projectRoundTripAndUIInvalidation(test)
            app=ProcessOptimizerApp('off'); cleanup=onCleanup(@()delete(app));
            cfg=processopt.defaultConfig(); cfg.Design.Method='Latin hypercube';
            cfg.Optimization.Population=12; cfg.Optimization.Generations=1;
            app.setConfig(cfg); app.generatePlan(); app.simulateData(); app.trainModels(); app.optimizeModels();
            original=app.Data;
            tables=findall(app.Figure,'Type','uitable');
            for k=1:numel(tables)
                T=tables(k).Data;
                if istable(T) && ismember('Current',T.Properties.VariableNames), factorTable=tables(k); end
                if istable(T) && ismember('Goal',T.Properties.VariableNames), responseTable=tables(k); end
            end
            column=find(strcmp(factorTable.Data.Properties.VariableNames,'Current'));
            test.verifyEqual(factorTable.Layout.Row,2);
            test.verifyEqual(responseTable.Layout.Row,4);
            factorTable.Data.Current(1)=390;
            factorTable.CellEditCallback(factorTable,struct('Indices',[1,column]));
            test.verifyNotEmpty(app.Bundle); test.verifyEqual(app.Data,original); test.verifyEmpty(app.Result);
            path=[tempname,'.mat']; app.saveProjectFile(path); fileCleanup=onCleanup(@()delete(path));
            app.setConfig(processopt.defaultConfig('DRY')); app.loadProjectFile(path);
            restored=app.getConfig(); test.verifyEqual(restored.Factors.Current(1),390);
            test.verifyEqual(app.Data,original); test.verifyEmpty(app.Bundle);
            column=find(strcmp(responseTable.Data.Properties.VariableNames,'Metric'));
            responseTable.Data.Metric{1}='std';
            responseTable.CellEditCallback(responseTable,struct('Indices',[1,column]));
            test.verifyEmpty(app.Data);
        end
        function kernelAndLandscapeControlsWorkInTheApp(test)
            app=ProcessOptimizerApp('off'); cleanup=onCleanup(@()delete(app));
            cfg=processopt.defaultConfig(); cfg.Design.Method='Latin hypercube';
            cfg.Model.Method='GPR'; cfg.Model.Folds=2; cfg.Model.Kernel='matern52';
            app.setConfig(cfg); app.generatePlan(); app.simulateData(); app.trainModels(); original=app.Data;
            kernel=findall(app.Figure,'Tag','GPRKernel'); kernel.Value='ardmatern32';
            kernel.ValueChangedFcn(kernel,[]);
            test.verifyEmpty(app.Bundle); test.verifyEqual(app.Data,original);
            app.trainModels(); app.drawResponseAnalysis();
            test.verifyEqual(app.Bundle.Config.Model.Kernel,'ardmatern32');
            test.verifySize(app.Landscape.Plane.Overall,[31,31]);
            mode=findall(app.Figure,'Tag','AnalysisMode'); mode.Value='scenarios'; mode.ValueChangedFcn(mode,[]);
            test.verifyEmpty(app.Landscape);
            app.drawResponseAnalysis(); test.verifyEqual(app.Landscape.Mode,'scenarios');
            path=[tempname,'.mat']; app.saveProjectFile(path); fileCleanup=onCleanup(@()delete(path));
            app.loadProjectFile(path); restored=app.getConfig();
            test.verifyEqual(restored.Model.Kernel,'ardmatern32');
        end
    end
    methods (Access=private)
        function rejects(test,action)
            rejected=false;
            try, action(); catch, rejected=true; end
            test.verifyTrue(rejected,'Invalid input was accepted.');
        end
    end
end
