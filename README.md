# 成膜・DRY 多目的最適化

MATLAB R2021b以降を対象とするローカルアプリです。CVDの膜厚・面内ばらつき、DRYの加工Rate・ばらつき、Wafer歪みなど、複数応答の条件を同時に探索します。

実験計画 → 実測CSVまたは仮想測定 → 重回帰/GPR/GAM → 交差検証 → 多目的探索 → 真値・追加実験による効果確認 → 因子効果・満足度の可視化を、7つのタブで操作します。例の式・範囲はソフトウェア検証用の架空の値です。

## 起動

MATLABでこのプロジェクトの `matlab` フォルダを開いて実行します。

```matlab
addpath(pwd)
app = launchProcessOptimizer;
```

開発にはMATLABとStatistics and Machine Learning Toolboxが必要です。Windows配布ビルドにMATLAB Compilerを使います。Global Optimization Toolbox、ネット接続、環境変数、APIキーは不要です。

## 最初の操作

1. 「CVD（仮想例）」を読み込みます。各応答のGoalは `target` / `min` / `max`、Targetは目標、Scaleは損失の単位調整、Lower/Upperは許容上下限です。Scaleは正数にします。
2. 「実験計画・データ」でD-optimal・40実験の計画を生成します。
3. 「真の式から仮想測定」を押します。
4. 「モデル・交差検証」でPolynomial / quadraticを学習します。CV_RMSEと残差を確認します。
5. 「多目的最適化」で探索し、候補表の行を選びます。目的同士の両立が難しい場合も、単一の重み付き合計に潰さず候補を比較できます。
6. 「効果・真値検証」で独立検証します。元条件と選択候補の予測、真値、条件変動による標準偏差、損失差、Wafer分布を確認します。
7. 実測では元条件と候補条件で追加実験し、「追加実験で確認」からCSVを読み込んで損失差とモデル誤差を確認します。

DRY例では平均EtchRateの目標合わせとRateのCV、Warpを同時に扱います。因子・応答は追加・削除でき、名前と定義を変更できます。

## 機能の選び方

|機能|選択肢・扱い|
|---|---|
|実験計画|D最適/I最適の有限候補上の近似探索、DSD、ラテン方格、ラテン超方格|
|重回帰の項|主効果、主効果+交互作用、主効果+二乗、主効果+二乗+交互作用|
|他の回帰|GPR（10種のカーネル選択）、GAM（2因子相互作用の有無）|
|面内集約|平均、標本標準偏差、CV%、NU%、RMS、max−min|
|目的|目標からの絶対差の最小化、最小化、最大化を応答ごとに設定|
|条件変動|因子ごとの独立正規分布。平均損失+リスク重み×損失標準偏差|
|候補の制約|因子の範囲と、応答のLower/Upper。全変動シナリオで確認|
|検証|条件単位の交差検証、独立した真の関数でのモデル誤差・改善効果・制約適合|
|実測の効果確認|元条件・選択候補の追加実験による損失差、Wafer間標準偏差、予測との誤差|
|因子効果|応答ごとに他因子を固定した応答曲線、満足度曲線、因子範囲全体の予測変化幅|
|満足度マップ|選択した2因子平面の予測応答、応答別満足度、全応答の総合満足度|
|保存|プロジェクトMAT、計画/測定/候補/指標のCSV、結果の設定MAT|

CV = `100*std(value,0)/abs(mean(value))`。NU = `100*(max(value)-min(value))/(2*abs(mean(value)))`。平均がゼロ付近ならCV/NUは使わず、std/rangeなどを選びます。RMSはゼロからの大きさで、平均を差し引いた標準偏差とは異なります。測定点は等重みで集約し、面積補正を行いません。

## 真の式

`x1, x2, ...` は因子表の順・実単位です。`u,v` は半径1に正規化したWafer座標。Wafer内の格子点に式を適用し、応答のMetricで集約します。

```text
100 + 0.1*(x1-400) + 2*(x2-3) + (2+0.002*(x1-395)^2)*(u^2+v^2)
```

使える演算は `+ - * / ^` と括弧、`sin cos tan tanh exp log sqrt abs min(a,b) max(a,b)`、定数 `pi`。演算は要素ごとに行います。式の文字数と入れ子に上限を設けています。専用パーサーのため、配布後も式を変更できます。

さらに一般のMATLAB関数が必要なら、`matlab/+processopt/customTruth.m` に関数を実装し、応答のFormulaを `custom`、Signalを実装した名前にして再ビルドします。`CustomExample` に実装例があります。この経路ではMATLAB Compilerで利用できる任意の関数を組み合わせられます。未知の外部.mファイルを配布後に動的に実行する方式ではありません。

同じ物理量から平均とばらつきを作るときは、複数応答に同じSignal / Formula / NoiseStdを指定します。測定ノイズの実現値も共有されます。NoiseStdは各Wafer測定点への独立な加法正規ノイズです。

## CSVの列

**集約済CSV**は1行が1実験です。因子のName列と応答のName列を用意します。

```csv
Temperature,Pressure,Flow,Thickness,ThicknessNU,Warp
400,3,100,101.0,1.2,3.7
390,2.5,95,99.5,1.0,3.3
```

**Wafer測定CSV**は1行が1測定点です。`RunID,WaferX,WaferY`、全因子のName列、物理量ごとのSignal列を用意します。例えば平均ThicknessとThicknessNUのSignalがともにThicknessなら、物理量のThickness列1本から両方を集約します。

```csv
RunID,WaferX,WaferY,Temperature,Pressure,Flow,Thickness,Warp
1,0,0,400,3,100,100,3.5
1,100,0,400,3,100,102,3.7
2,0,0,390,2.5,95,99,3.2
2,100,0,390,2.5,95,101,3.4
```

同じRunIDの因子は同一にします。繰返しWaferはRunIDを分けます。座標は実単位でも正規化座標でも読み込めますが、同一CSV内で単位を統一します。取込は欠測、無限値、範囲外条件、同じRunID内の重複位置を拒否します。異なる測定位置の集合や異なる点数で集約した指標の比較には注意が必要です。

上記は列の例であり、その行数だけで全2次回帰を学習できる例ではありません。

**追加実験CSV**は上記の集約済形式またはWafer測定形式に `Role` 列を加えます。`baseline` はCurrentの元条件、`candidate` は選択した候補と同じ因子条件にしてください。両方を含めます。Waferを繰り返し測定した場合はRunIDを分けます。追加実験CSVは学習データに追加せず、独立した検証にだけ使います。

```csv
Role,Temperature,Pressure,Flow,Thickness,ThicknessNU,Warp
baseline,400,3,100,101.0,1.2,3.7
candidate,390,2.5,95,99.5,1.0,3.3
```

候補の因子値はアプリの候補表から転記します。比較はWaferごとの損失を平均した差です。targetの応答では「平均値を目標に近づける」ことと「各Waferを目標に近づける」ことの違いを保ちます。Wafer間SDは1実験だけの場合NaNです。表示した差だけで統計的有意差を主張しません。

## モデルと最適化の読み方

- Polynomialの全2次式には `1 + 2p + p(p−1)/2` 個の係数があります。3因子なら10個です。交差検証の学習部分にも十分な実験数と独立性が必要です。
- DSDは少ない実験でのスクリーニング用です。全2次項を同時に推定できる計画ではありません。対応conference行列への射影を用いるため最小実験数とは限りません。
- ラテン方格は因子を3つにし、最初の2つを行・列のブロック、3つ目を数値の処理条件にします。行・列をカテゴリとして補正します。Polynomialではブロックの主効果と処理条件の最大2次式、GPR/GAMでは最初の2因子をカテゴリ予測子として扱います。探索時は行・列をCurrentの実水準に固定し、処理条件を探索します。計画生成時にCurrentを最寄り水準へ合わせます。行・列のJitterStdは0にします。任意のカテゴリ処理の最適化を意味しません。
- ラテン超方格は複数の連続因子の範囲を広く調べる方法で、ブロック補正を意味しません。
- CV_R2が負なら、検証点で平均予測より悪い場合があります。定数応答のR²、GAMの予測区間被覆率はNaNです。
- GAM_Interactionsは最終モデルに実際に採用された相互作用の数です。相互作用を指定しても、適合を改善できない場合などは `fitrgam` が採用しないことがあります。
- Scaleは損失を正規化する尺度です。優越関係に対する単位の影響を避け、制約違反量や候補初期選択にも使います。
- 多目的探索結果は近似Pareto集合です。全目的が同時に改善するとは限りません。候補ごとに制約・予測誤差・元条件との差を確認します。
- 真値検証は設定した仮想世界での確認です。実プロセスの効果は候補条件で追加実験して確認します。制約の有限乱数による適合は確率保証ではありません。
- 条件変動のSD、測定ノイズ、モデル推定の不確かさは別物です。初期版はモデル不確かさを目的関数へ加えません。

## このMacで起動する

MATLAB CompilerがないMacでは、インストール済みMATLABを使う `.app` ランチャーを作成できます。MATLABが不要な独立実行版ではありません。

```matlab
appPath = buildLocalMacLauncher;
```

`build/mac-local/ProcessOptimizer.app` をダブルクリックすると起動します。ランチャーにはアプリのソースをコピーし、ビルドした端末のMATLABを使用します。変更を反映する場合は再度ビルドしてください。ログは `~/Library/Logs/ProcessOptimizer/mac-local.log` に保存します（旧版ランチャーはlauncher.log）。

`buildLocalMacLauncher('mac-visualization')` のようにビルド名を指定すると別フォルダへ作成します。起動中の旧版を残しながら新版を検証できます。今回の可視化対応版は `build/mac-visualization/ProcessOptimizer.app`、ログは `~/Library/Logs/ProcessOptimizer/mac-visualization.log` です。

## GPRカーネルの選択

「3 モデル・交差検証」でGPRを選び、カーネルを選択して再学習します。二乗指数、指数、Matern 3/2、Matern 5/2、有理二次と、それぞれのARD版の計10種です。ARDでは因子ごとに異なる長さ尺度を推定します。学習したカーネルはGPR_Kernel列に表示し、保存プロジェクトにも残します。旧プロジェクトに選択項目がない場合は従来のARD二乗指数へ戻します。

カーネル選択は交差検証で比較してください。表示される曲線の滑らかさだけで精度を判断しません。

## 因子効果と満足度のヒートマップ

1. モデルを学習して「7 因子効果・満足度」を開きます。最適化前でも表示できます。
2. 応答、横軸・縦軸の説明変数を選びます。
3. 「Currentを固定値に」または「選択候補を固定値に」で基準を設定します。Fixed列は手入力でも変更できます。
4. 「名目条件」または「条件変動の平均」を選び、「描画・更新」を押します。

各因子のグラフは、他の因子をFixedへ固定したときの予測応答（実線・左軸）と応答の満足度（破線・右軸）です。下部の棒グラフは同じ断面の予測max−minであり、因果効果や全領域での重要度を意味しません。因子の探索範囲と固定値に依存し、制約外の予測も含みます。

平面の左図は選択応答の予測値、右図は選択応答または総合満足度です。軸以外の因子はFixedへ固定します。白いマーカーは固定値の位置、黒破線は制約境界、満足度図の灰色は全応答・因子範囲の制約を満たさない領域です。色の尺度は常に0〜1で、平面ごとのmin/maxによる再正規化はしません。

満足度 `d` は、既存のLower/UpperとGoalから次のように定義します。全応答のLower/Upperを有限値にしてください。

|Goal|満足度1|満足度0|範囲内の変化|
|---|---|---|---|
|target|Target|LowerとUpper|目標から左右の限界へ線形に低下|
|min|Lower|Upper|予測値の増加に従って線形に低下|
|max|Upper|Lower|予測値の増加に従って線形に上昇|

範囲外は0です。targetの目標値は上下限内にします。総合満足度は全応答を等重みとする幾何平均 `(d1*d2*...*dm)^(1/m)` で、1応答でも0なら0です。上下限が無限大などで満足度を定義できない場合も、応答曲線と予測応答面は表示し、満足度の設定案内を表示します。

「条件変動の平均」は、探索と共通のシナリオを使い、各シナリオの満足度・総合満足度を求めてから平均します。平均応答を満足度へ変換する計算とは異なります。灰色の判定は全シナリオでの制約適合です。表示用の満足度は、Pareto探索の正規化損失・リスク重みとは別の指標であり、探索方法を変更しません。1因子の場合は応答曲線のみ表示します。ラテン方格の行・列ブロックを軸に選んだ場合は実際の離散水準で評価します。

`runVisualizationDemo` はGPRのARD Matern 5/2を学習し、可視化と画面画像を `results/visualization/` に生成します。

## Windows配布

Windows上で、プロジェクトのmatlabフォルダから実行します。

```matlab
results = runTests;
buildResult = buildStandalone;
```

`build/` にWindows用の実行ファイルが作られます。配布先にビルド時と同じMATLABリリースに対応するMATLAB Runtimeをインストールします。ビルド関数はRuntimeの同梱インストーラーを自動作成しません。MATLABのApplication CompilerからRuntimeを含むパッケージを作る方法も利用できます。MacからWindows用exeを作ることはできません。

受入手順:

1. Windows 11 / MATLAB R2021bで `runTests` を実行する。
2. `buildStandalone` でビルドする。
3. MATLAB未導入・対応RuntimeのみのWindows 11端末で起動する。
4. CVD/DRY例、全計画法、3モデル、数式変更、CSV取込、保存再読込、探索中止を確認する。
5. 画面の文字切れを表示倍率100%・150%で確認する。

ソースの対象はR2021b以降ですが、実際に検証したリリースと未確認事項は `issues.md` に記録しています。今回の実行結果は `verification.md` に記録しています。Windows実行ファイルの作成・Runtime確認を完了してから配布します。

MATLABで `runDemo('CVD')` または `runDemo('DRY')` を実行すると、標準設定の一連の処理と結果CSV、画面画像を `results/` に生成できます。

## 構成と管理

`matlab/ProcessOptimizerApp.m` が画面、`matlab/+processopt/` が数値処理、`matlab/tests/` が検証です。`requirements.md` に要件、`design.md` に計算方式、`issues.md` に残課題を記載します。

実データ・保存プロジェクトは `data/`、結果は `results/`、ビルド成果物は `build/` に置くとGit対象外になります。他の場所に機密データを置いてコミットしないでください。計算処理は端末内で実行され、アプリに外部送信処理はありません。

## 実装の参照元

- [fitrgp: GPR](https://www.mathworks.com/help/stats/fitrgp.html)
- [fitrgam: GAM、R2021aから利用可能](https://www.mathworks.com/help/stats/fitrgam.html)
- [candexch: 有限候補に対するD最適計画](https://www.mathworks.com/help/stats/candexch.html)（本実装は独自の交換探索）
- [Xiao, Lin, Bai (2012), conference行列からのDSD構成](https://www.stat.purdue.edu/~dkjlin/documents/publications/2012/2012_JQT.pdf)
- [compiler.build.standaloneApplication](https://www.mathworks.com/help/compiler/compiler.build.standaloneapplication.html)
- [MATLAB Runtimeとリリースの対応](https://www.mathworks.com/help/compiler/matlab-runtime.html)
