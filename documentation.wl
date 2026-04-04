(* documentation.wl -- Documentation Authoring Package
   This file is encoded in UTF-8.
   Load via: Block[{$CharacterEncoding = "UTF-8"}, Get["documentation.wl"]]

   アウトラインプロセッサ拡張: アイデア → パラグラフ展開システム。

   規約:
   - セル内容へのアクセスはすべて NBAccess` の公開関数経由で行う。
   - LLM 呼び出しは NBAccess`NBCellTransformWithLLM 経由で行う。
     (プライバシーレベルに応じた LLM 自動選択はNBAccessが担当)
   - パレット UI のためのノートブック/セルインデックス解決のみ内部で行う。

   依存: NBAccess` (セルアクセス・LLM ルーティング), ClaudeCode` (LLM コールバック)
*)

BeginPackage["Documentation`"];

(* ---- 依存パッケージ ---- *)
Needs["NBAccess`"];
Needs["ClaudeCode`"];

(* ---- 公開API ---- *)

DocExpandIdea::usage =
  "DocExpandIdea[nb, cellIdx] は指定セルのアイデアテキストを\n" <>
  "LLM を使って文章品質のパラグラフに展開する。\n" <>
  "元のアイデアはセルの TaggingRules に保存される。\n" <>
  "既にパラグラフ表示中の場合は、プロンプト・指示・文脈に従い\n" <>
  "現在のパラグラフ文章を尊重しつつインプレース更新する。\n" <>
  "Options: Fallback -> False\n" <>
  "例: DocExpandIdea[EvaluationNotebook[], 3]";

DocToggleView::usage =
  "DocToggleView[nb, cellIdx] はセルのアイデアとパラグラフの表示を切り替える。\n" <>
  "現在表示中の内容（編集済みでも）を保存してから切り替える。\n" <>
  "例: DocToggleView[EvaluationNotebook[], 5]";


DocInsertNote::usage =
  "DocInsertNote[nb] は現在のカーソル位置に Note スタイルのセルを挿入する。\n" <>
  "既にスタイル \"Note\" が定義されている場合はそれを使い、\n" <>
  "なければカスタム定義のNoteセルを挿入する。";

DocInsertDictionary::usage =
  "DocInsertDictionary[nb] は現在のカーソル位置に Dictionary スタイルのセルを挿入する。\n" <>
  "翻訳時に用語の対応を指定するための辞書セル。\n" <>
  "形式: {{<<Japanese>>, <<English>>, <<Context>>}, {\"用語1\", \"term1\", \"文脈\"}, ...}\n" <>
  "1行目はヘッダー（<<>> で囲む）、2行目以降が Context における用語対応。";

DocInsertDirective::usage =
  "DocInsertDirective[nb] は現在のカーソル位置に Directive スタイルのセルを挿入する。\n" <>
  "展開・翻訳・同期の実行時に LLM が順守すべき指示を記載するセル。\n" <>
  "複数の Directive セルを配置可能。";

DocInsertBibliography::usage =
  "DocInsertBibliography[nb] は現在のカーソル位置に Bibliography スタイルのセルを挿入する。\n" <>
  "参考文献リストを管理する。\n" <>
  "形式: {{<<Key>>, <<Author>>, <<Year>>, <<Title>>}, {\"key\", \"author\", \"year\", \"title\"}, ...}\n" <>
  "本文中で <<cite:key>> と記述するとエクスポート時に自動変換される。";

DocEditFigureMeta::usage =
  "DocEditFigureMeta[nb, cellIdx] は画像セルの図メタデータを編集する。\n" <>
  "ラベル（参照用キー）とキャプションを設定するダイアログを表示する。\n" <>
  "本文中で <<fig:label>> と記述するとエクスポート時に自動変換される。";

DocEditRefSources::usage =
  "DocEditRefSources[nb, cellIdx] はセルの依存資料を編集する。\n" <>
  "アタッチされた PDF のうち、そのセルの内容生成に使われた資料と\n" <>
  "参照ページ番号を設定する。LaTeX+Math エクスポート時に\n" <>
  "該当ページのみを LLM に送付してトークン消費を削減する。";

DocAutoInsertCitations::usage =
  "DocAutoInsertCitations[nb] はノートブック内の全セルに自動引用を挿入する。\n" <>
  "依存資料（refSources）から文献リストを構築し、\n" <>
  "LLM が本文中の適切な位置に <<cite:key>> マーカーを挿入する。\n" <>
  "Bibliography セルが存在しなければ末尾に自動生成する。";

DocExportMarkdown::usage =
  "DocExportMarkdown[nb] はノートブックを Markdown 形式でエクスポートする。\n" <>
  "出力先: NotebookDirectory[] / <ノートブック名>_md/\n" <>
  "Note, Dictionary, Directive, Bibliography スタイルのセルは出力から除外される。\n" <>
  "画像: ラスター→PNG, ベクター/計算結果→PDF で保存。\n" <>
  "<<fig:label>> と <<cite:key>> は自動変換される。\n" <>
  "Input セルはコードブロック、数式は TeX に変換される。";

DocExportLaTeX::usage =
  "DocExportLaTeX[nb] はノートブックを LaTeX 形式でエクスポートする。\n" <>
  "出力先: NotebookDirectory[] / <ノートブック名>_LaTeX/\n" <>
  "Note, Dictionary, Directive, Bibliography スタイルのセルは出力から除外される。\n" <>
  "画像: ラスター→PNG, ベクター/計算結果→PDF で保存。\n" <>
  "<<fig:label>> は \\ref{fig:label} に、<<cite:key>> は \\cite{key} に変換される。\n" <>
  "Options: \"MathFormat\" -> False（True で LLM による数式自動フォーマット）";

DocExportWord::usage =
  "DocExportWord[nb] はノートブックを Word (.docx) 形式でエクスポートする。\n" <>
  "内部で DocExportMarkdown を実行し、Pandoc で .docx に変換する。\n" <>
  "出力先: NotebookDirectory[] / <ノートブック名>_md/<ノートブック名>.docx\n" <>
  "Pandoc がインストールされている必要がある。\n" <>
  "Options: \"ReferenceDoc\" -> None（テンプレート .docx ファイルのパス）";

ShowDocPalette::usage =
  "ShowDocPalette[] はドキュメント作成用パレットを表示する。";

DocSplitCell::usage =
  "DocSplitCell[nb, cellIdx] はカーソル位置でセルを前半・後半に分割する。\n" <>
  "パラグラフ/翻訳表示中: 表示テキストと保存データを対応位置で分割し、\n" <>
  "プロンプトがあれば LLM で前半・後半用に再生成する。\n" <>
  "普通のセル: テキストを単純に分割する。";

DocMergeCells::usage =
  "DocMergeCells[nb, cellIdxs] は複数セルを単一セルに合併する。\n" <>
  "テキスト・プロンプト・翻訳をそれぞれ結合し、最初のセルに統合する。\n" <>
  "モード・スタイルは最初のセルを維持する。";

$DocTranslationLanguage::usage =
  "$DocTranslationLanguage は翻訳先の言語名。\n" <>
  "デフォルト: $Language が英語以外なら \"English\"、英語なら \"Japanese\"。\n" <>
  "ユーザーが任意の言語名に変更可能。\n" <>
  "例: $DocTranslationLanguage = \"French\"";

(* ---- オプション宣言 ---- *)
Options[DocExpandIdea] = {Fallback -> False};
Options[DocTranslate] = {Fallback -> False};
Options[DocSync] = {Fallback -> False};
Options[DocExportMarkdown] = {"MathFormat" -> False};
Options[DocExportLaTeX] = {"MathFormat" -> False};
Options[DocExportWord] = {"ReferenceDoc" -> None, "MathFormat" -> False};
Options[DocCompute] = {Fallback -> False};

Begin["`Private`"];

(* ============================================================
   ローカリゼーション
   ============================================================ *)
iL[ja_String, en_String] := If[$Language === "Japanese", ja, en];

(* ============================================================
   定数: 視覚スタイル
   ============================================================ *)

(* 展開の視覚表現: 左側枠線のみ制御。
   Background と CellDingbat は機密システム (NBAccess) の管轄であり、
   documentation 側では一切触らない。これにより機密背景色が保持される。 *)

(* パラグラフ表示モード: 左側に緑の枠線 *)
$iDocParagraphCellOpts = {
  CellFrame      -> {{3, 0}, {0, 0}},
  CellFrameColor -> RGBColor[0.3, 0.6, 0.5]
};

(* アイデア表示モード: 左側に琥珀色の枠線 *)
$iDocIdeaCellOpts = {
  CellFrame      -> {{3, 0}, {0, 0}},
  CellFrameColor -> RGBColor[0.8, 0.65, 0.3]
};

(* 翻訳表示モード: 左側に青の枠線 *)
$iDocTranslationCellOpts = {
  CellFrame      -> {{3, 0}, {0, 0}},
  CellFrameColor -> RGBColor[0.3, 0.45, 0.75]
};

(* 翻訳付きセル（元テキスト表示中）: 左側に水色の枠線 *)
$iDocTranslatedCellOpts = {
  CellFrame      -> {{3, 0}, {0, 0}},
  CellFrameColor -> RGBColor[0.5, 0.75, 0.9]
};

(* ============================================================
   TaggingRules パス定数
   ============================================================ *)
$iDocTagRoot = "documentation";
$iDocTagAlternate = {$iDocTagRoot, "alternate"};
$iDocTagMode = {$iDocTagRoot, "mode"};
$iDocTagTranslation = {$iDocTagRoot, "translation"};
$iDocTagTranslationSrc = {$iDocTagRoot, "translationSrc"};
$iDocTagShowTranslation = {$iDocTagRoot, "showTranslation"};
$iDocTagExcludeExport = {$iDocTagRoot, "excludeExport"};
$iDocTagFigLabel = {$iDocTagRoot, "figLabel"};
$iDocTagFigCaption = {$iDocTagRoot, "figCaption"};
$iDocTagCleanText = {$iDocTagRoot, "cleanText"};
$iDocTagCleanMode = {$iDocTagRoot, "cleanMode"};
$iDocTagRefSources = {$iDocTagRoot, "refSources"};

(* ============================================================
   パレット状態
   ============================================================ *)
If[!ValueQ[$docPalette], $docPalette = None];
(* 直前の操作対象セル記憶: {nb, cellIdx}
   セル選択が解除されても、同じノートブック上なら直前のセルを再利用する。
   別セルの選択、別ノートブックへの切替でクリアされる。 *)
$iDocLastTarget = {None, 0};

(* ============================================================
   パレット用: ノートブック/セル解決 (UI メタデータのみ、内容非接触)
   ============================================================ *)

(* パレットから呼ばれても正しいユーザーノートブックを返す *)
iDocUserNotebook[] :=
  Module[{nb = Quiet[InputNotebook[]], nbs},
    If[Head[nb] === NotebookObject &&
       Quiet[CurrentValue[nb, WindowClickSelect]] =!= False,
      Return[nb]];
    nbs = Select[Notebooks[],
      Quiet[CurrentValue[#, WindowClickSelect]] =!= False &&
      !TrueQ[Quiet[CurrentValue[#, Saveable] === False &&
                    CurrentValue[#, WindowFloating]]] &];
    If[Length[nbs] > 0, First[nbs], nb]
  ];

(* 操作対象セルインデックスを1つ解決する。
   セルブラケット選択があればそれを使い記憶する。
   選択がない場合、同じノートブック上の直前操作セルを再利用する。
   ノートブックが変わったら記憶をクリアする。 *)
iDocResolveTargetCell[] :=
  Module[{nb, idxs},
    nb = iDocUserNotebook[];
    If[Head[nb] =!= NotebookObject, Return[{$Failed, 0}]];
    If[$iDocLastTarget[[1]] =!= None && $iDocLastTarget[[1]] =!= nb,
      $iDocLastTarget = {None, 0}];
    NBAccess`NBInvalidateCellsCache[nb];
    idxs = NBAccess`NBSelectedCellIndices[nb];
    If[Length[idxs] > 0,
      $iDocLastTarget = {nb, First[idxs]};
      {nb, First[idxs]},
      If[$iDocLastTarget[[1]] === nb && $iDocLastTarget[[2]] > 0,
        {nb, $iDocLastTarget[[2]]},
        {nb, 0}]
    ]
  ];

(* 操作対象セルインデックスを複数解決する（セルグループ選択対応）。
   複数選択: そのまま全インデックスを返す。
   単一選択 or カーソル位置: 1要素リストとして返す。
   選択なし: 直前操作セルを再利用。 *)
iDocResolveTargetCells[] :=
  Module[{nb, idxs},
    nb = iDocUserNotebook[];
    If[Head[nb] =!= NotebookObject, Return[{$Failed, {}}]];
    If[$iDocLastTarget[[1]] =!= None && $iDocLastTarget[[1]] =!= nb,
      $iDocLastTarget = {None, 0}];
    NBAccess`NBInvalidateCellsCache[nb];
    idxs = NBAccess`NBSelectedCellIndices[nb];
    If[Length[idxs] > 0,
      $iDocLastTarget = {nb, First[idxs]};
      {nb, idxs},
      If[$iDocLastTarget[[1]] === nb && $iDocLastTarget[[2]] > 0,
        {nb, {$iDocLastTarget[[2]]}},
        {nb, {}}]
    ]
  ];

(* ============================================================
   言語ヘルパー
   ============================================================ *)

(* $Language に基づく出力言語名。展開プロンプトで使用。 *)
iDocOutputLanguage[] := Module[{lang},
  lang = If[StringQ[$Language], $Language, "Japanese"];
  Switch[lang,
    "Japanese", "Japanese",
    "English", "English",
    "ChineseSimplified", "Simplified Chinese",
    "ChineseTraditional", "Traditional Chinese",
    "Korean", "Korean",
    "French", "French",
    "German", "German",
    "Spanish", "Spanish",
    _, lang]
];

(* 翻訳先言語の初期化: $Language が英語以外なら英語に、英語なら日本語に *)
If[!StringQ[$DocTranslationLanguage],
  $DocTranslationLanguage = If[StringQ[$Language] && $Language === "English",
    "Japanese", "English"]];

(* 翻訳先言語を返す（大域変数経由） *)
iDocTranslationTarget[] := $DocTranslationLanguage;

(* テキストの言語をヒューリスティックで検出する。
   ひらがな・カタカナ → "Japanese"
   ハングル → "Korean"
   CJK統合漢字のみ（かな無し）→ "Chinese"
   それ以外 → "English" （ラテン文字系を一括） *)
iDocDetectTextLanguage[text_String] := Module[{sample},
  sample = StringTake[text, Min[500, StringLength[text]]];
  Which[
    StringContainsQ[sample,
      RegularExpression["[\\x{3040}-\\x{309F}\\x{30A0}-\\x{30FF}]"]],
      "Japanese",
    StringContainsQ[sample,
      RegularExpression["[\\x{AC00}-\\x{D7AF}]"]],
      "Korean",
    StringContainsQ[sample,
      RegularExpression["[\\x{4E00}-\\x{9FFF}]"]],
      "Chinese",
    True,
      "English"
  ]
];

(* $Language を検出言語と比較可能な形式に変換 *)
iDocLangCategory[lang_String] := Switch[lang,
  "Japanese", "Japanese",
  "English", "English",
  "Korean", "Korean",
  "ChineseSimplified" | "ChineseTraditional", "Chinese",
  "French" | "German" | "Spanish" | "Italian" | "Portuguese", "European",
  _, "Other"
];

(* 普通のセル用: テキスト言語を検出して翻訳先を決定する。
   テキストの言語が $Language と異なる → $Language に翻訳
   テキストの言語が $Language と同じ → iDocTranslationTarget[] *)
iDocTranslationTargetForText[text_String] := Module[{detected, myLang},
  detected = iDocDetectTextLanguage[text];
  myLang = iDocLangCategory[If[StringQ[$Language], $Language, "Japanese"]];
  If[detected =!= myLang,
    (* テキストの言語が $Language と異なる → $Language に翻訳 *)
    iDocOutputLanguage[],
    (* 同じ → 別の言語に翻訳 *)
    iDocTranslationTarget[]]
];

(* ============================================================
   LLM プロンプト構築関数 (NBCellTransformWithLLM の promptFn として使う)
   ============================================================ *)

(* ノートブックのコンテキスト情報を収集する。
   対象セルの周辺セルテキストとアタッチメント情報を含む。
   LLM がアイデア中の略語・固有名詞を正しく解釈するために使う。 *)
iDocCollectContext[nb_NotebookObject, cellIdx_Integer] :=
  Module[{nCells, texts = {}, mode, text, style, atts, attNames, maxCells = 30},
    NBAccess`NBInvalidateCellsCache[nb];
    nCells = NBAccess`NBCellCount[nb];
    (* 周辺セルの要約を収集（自分自身を除く、最大 maxCells セル） *)
    Do[
      If[i =!= cellIdx,
        style = NBAccess`NBCellStyle[nb, i];
        If[MemberQ[{"Text", "Section", "Subsection", "Subsubsection", "Title",
                     "Subtitle", "Chapter"}, style],
          text = Quiet[NBAccess`NBCellGetText[nb, i]];
          If[StringQ[text] && StringLength[text] > 0,
            (* 長すぎるセルは先頭200文字に切り詰め *)
            text = If[StringLength[text] > 200,
              StringTake[text, 200] <> "...", text];
            mode = NBAccess`NBCellGetTaggingRule[nb, i, $iDocTagMode];
            AppendTo[texts,
              "[Cell " <> ToString[i] <>
              If[StringQ[mode], " (" <> mode <> ")", ""] <>
              "] " <> text]]]],
    {i, Max[1, cellIdx - maxCells], Min[nCells, cellIdx + maxCells]}];
    (* アタッチメント情報: NBAccess 公開 API 経由 *)
    atts = Quiet[NBAccess`NBHistoryGetAttachments[nb, "history"]];
    attNames = If[ListQ[atts] && Length[atts] > 0,
      "Attached files: " <> StringRiffle[FileNameTake /@ atts, ", "],
      ""];
    (* コンテキスト文字列を構築 *)
    If[Length[texts] === 0 && attNames === "", "",
      "=== Document context (use this to disambiguate terms) ===\n" <>
      If[attNames =!= "", attNames <> "\n", ""] <>
      If[Length[texts] > 0,
        "Surrounding cells:\n" <> StringRiffle[texts, "\n"] <> "\n", ""] <>
      "=== End context ===\n\n"]
  ];

(* ノートブック内の Dictionary セルから用語辞書を収集する。
   翻訳時に LLM が用語対応を遵守するために使う。 *)
iDocCollectDictionary[nb_NotebookObject] :=
  Module[{nCells, text, entries = {}},
    nCells = NBAccess`NBCellCount[nb];
    Do[
      If[iDocIsDictionaryCell[nb, i],
        text = Quiet[NBAccess`NBCellGetText[nb, i]];
        If[StringQ[text] && StringLength[text] > 0,
          AppendTo[entries, text]]],
    {i, nCells}];
    If[Length[entries] === 0, "",
      "=== Dictionary (MUST use these term mappings when translating) ===\n" <>
      StringRiffle[entries, "\n"] <>
      "\n=== End Dictionary ===\n\n"]
  ];

(* ノートブック内の Directive セルから指示を収集する。
   展開・翻訳・同期時に LLM が遵守すべき指示。 *)
iDocCollectDirectives[nb_NotebookObject] :=
  Module[{nCells, text, directives = {}},
    nCells = NBAccess`NBCellCount[nb];
    Do[
      If[iDocIsDirectiveCell[nb, i],
        text = Quiet[NBAccess`NBCellGetText[nb, i]];
        If[StringQ[text] && StringLength[text] > 0,
          AppendTo[directives, text]]],
    {i, nCells}];
    If[Length[directives] === 0, "",
      "=== Directives (MUST follow these instructions strictly) ===\n" <>
      StringRiffle[directives, "\n---\n"] <>
      "\n=== End Directives ===\n\n"]
  ];

(* Directive セルからエクスポート用のスタイル読み替え規則を解析する。
   {Subsection -> Section, Subsubsection -> Subsection} のような WL 式を検出。
   戻り値: Association<|"Subsection" -> "Section", ...|> *)
iDocParseStyleRemap[nb_NotebookObject] :=
  Module[{nCells, text, remap = <||>, matches, parsed},
    nCells = NBAccess`NBCellCount[nb];
    Do[
      If[iDocIsDirectiveCell[nb, i],
        text = Quiet[NBAccess`NBCellGetText[nb, i]];
        If[StringQ[text],
          (* {A -> B, C -> D} パターンを探す *)
          matches = StringCases[text,
            RegularExpression["\\{[^{}]*->\\s*[^{}]*\\}"]];
          Do[
            parsed = Quiet[ToExpression[m, InputForm, Hold]];
            parsed = parsed /. Hold[x_] :> x;
            If[ListQ[parsed],
              Do[
                If[Head[rule] === Rule,
                  Module[{k = rule[[1]], v = rule[[2]]},
                    (* シンボル名を文字列に変換 *)
                    If[!StringQ[k], k = ToString[k]];
                    If[!StringQ[v], v = ToString[v]];
                    remap[k] = v]],
              {rule, parsed}]],
          {m, matches}]]],
    {i, nCells}];
    remap
  ];

iDocExpandPromptFn[ideaText_String, context_String:""] :=
  context <>
  iL[
    "あなたは熟練したライターです。以下の短いアイデアやフレーズを、" <>
    "よく練られた段落に発展させてください。\n" <>
    "ルール:\n" <>
    "- 元の意味と意図を忠実に保つ\n" <>
    "- 深み、明確さ、プロフェッショナルな文章品質を加える\n" <>
    "- 出力言語: " <> iDocOutputLanguage[] <> "\n" <>
    "- 【最重要】段落の本文テキストのみを出力すること。" <>
    "「Let me」「まず」「では」等の前置き、思考過程、説明、メタコメントは絶対に含めない。" <>
    "出力の最初の文字から最後の文字まですべてが段落の本文でなければならない\n" <>
    "- マークダウン記法は使わない\n" <>
    "- ドキュメントコンテキストがある場合は、略語や固有名詞の意味を文脈から判断する\n" <>
    "- Directives（指示）が提供されている場合は、その内容を厳守して生成する\n" <>
    "- Dictionary（辞書）が提供されている場合は、翻訳時にその用語対応を必ず使用する\n" <>
    "- 前後の文脈を考慮して、文書全体の流れに合った段落を生成する\n" <>
    "- アタッチされた資料がコンテキストに含まれる場合は参照してよいが、" <>
    "資料を読む過程（「PDFを読みます」等）は絶対に出力に含めない\n" <>
    "- リクエストを実行できない場合（ファイル未検出・情報不足等）は、段落ではなく [ERROR]: に続けて理由を出力する\n\n" <>
    "アイデア:\n" <> ideaText,
    "You are a skilled writer. Develop the following brief idea or phrase " <>
    "into a well-crafted paragraph.\n" <>
    "Rules:\n" <>
    "- Maintain the original meaning and intent faithfully\n" <>
    "- Add depth, clarity, and professional quality prose\n" <>
    "- Output language: " <> iDocOutputLanguage[] <> "\n" <>
    "- CRITICAL: Output ONLY the paragraph body text. " <>
    "Do NOT include any preamble, thinking, meta-commentary, or explanation " <>
    "such as 'Let me...', 'I will...', 'Here is...', 'Based on...'. " <>
    "The very first character of your output must be the start of the paragraph itself\n" <>
    "- Do not use markdown formatting\n" <>
    "- If document context is provided, use it to disambiguate abbreviations and proper nouns\n" <>
    "- If Directives are provided, strictly follow their instructions\n" <>
    "- If a Dictionary is provided, always use the specified term mappings when translating\n" <>
    "- Consider the surrounding context to produce a paragraph that fits the overall document flow\n" <>
    "- If attached files are mentioned in context, use their content but NEVER output " <>
    "your reading process (e.g. 'Let me read the PDF')\n" <>
    "- If you cannot fulfill the request (file not found, insufficient info, etc.), output ONLY: [ERROR]: followed by the reason\n\n" <>
    "Idea:\n" <> ideaText
  ];

(* 再展開用プロンプト: 修正されたアイデアと以前のパラグラフの両方を渡す *)
iDocReExpandPromptFn[ideaText_String, prevParagraph_String, context_String:""] :=
  context <>
  iL[
    "あなたは熟練したライターです。以下の「修正されたアイデア」に基づいて、" <>
    "「以前の段落」を書き直してください。\n" <>
    "ルール:\n" <>
    "- 以前の段落の文体・構成・ユーザーの修正を可能な限り踏襲する\n" <>
    "- 修正されたアイデアの内容変更に従って必要箇所を書き換える\n" <>
    "- 出力言語: " <> iDocOutputLanguage[] <> "\n" <>
    "- 【最重要】段落の本文テキストのみを出力すること。" <>
    "「Let me」「まず」「では」等の前置き、思考過程、説明、メタコメントは絶対に含めない。" <>
    "出力の最初の文字から最後の文字まですべてが段落の本文でなければならない\n" <>
    "- マークダウン記法は使わない\n" <>
    "- ドキュメントコンテキストがある場合は、略語や固有名詞の意味を文脈から判断する\n" <>
    "- Directives（指示）が提供されている場合は、その内容を厳守して生成する\n" <>
    "- Dictionary（辞書）が提供されている場合は、翻訳時にその用語対応を必ず使用する\n" <>
    "- 前後の文脈を考慮して、文書全体の流れに合った段落を生成する\n" <>
    "- アタッチされた資料がコンテキストに含まれる場合は参照してよいが、" <>
    "資料を読む過程は絶対に出力に含めない\n" <>
    "- リクエストを実行できない場合（ファイル未検出・情報不足等）は、段落ではなく [ERROR]: に続けて理由を出力する\n\n" <>
    "修正されたアイデア:\n" <> ideaText <>
    "\n\n以前の段落:\n" <> prevParagraph,
    "You are a skilled writer. Revise the 'Previous paragraph' based on " <>
    "the 'Updated idea' below.\n" <>
    "Rules:\n" <>
    "- Preserve the style, structure, and user edits of the previous paragraph as much as possible\n" <>
    "- Update only the parts that need to change according to the updated idea\n" <>
    "- Output language: " <> iDocOutputLanguage[] <> "\n" <>
    "- CRITICAL: Output ONLY the paragraph body text. " <>
    "Do NOT include any preamble, thinking, meta-commentary, or explanation " <>
    "such as 'Let me...', 'I will...', 'Here is...', 'Based on...'. " <>
    "The very first character of your output must be the start of the paragraph itself\n" <>
    "- Do not use markdown formatting\n" <>
    "- If document context is provided, use it to disambiguate abbreviations and proper nouns\n" <>
    "- If Directives are provided, strictly follow their instructions\n" <>
    "- If a Dictionary is provided, always use the specified term mappings when translating\n" <>
    "- Consider the surrounding context to produce a paragraph that fits the overall document flow\n" <>
    "- If attached files are mentioned in context, use their content but NEVER output your reading process\n" <>
    "- If you cannot fulfill the request (file not found, insufficient info, etc.), output ONLY: [ERROR]: followed by the reason\n\n" <>
    "Updated idea:\n" <> ideaText <>
    "\n\nPrevious paragraph:\n" <> prevParagraph
  ];

(* パラグラフ更新プロンプト: パラグラフ表示中に展開ボタンを押した場合、
   現在のパラグラフを尊重しつつ、プロンプト・指示・文脈に従い更新する *)
iDocUpdateParagraphPromptFn[ideaText_String, currentParagraph_String, context_String:""] :=
  context <>
  iL[
    "あなたは熟練したライターです。以下の「現在の段落」を、" <>
    "「プロンプト（アイデア）」の指示に基づいて更新してください。\n" <>
    "ルール:\n" <>
    "- 現在の段落の文体・構成・ユーザーの修正を最大限尊重する\n" <>
    "- プロンプトの内容と、Directives（指示）の内容に従って必要箇所を更新する\n" <>
    "- ドキュメントコンテキストや文献情報がある場合は、それに基づいて内容の正確性を向上させる\n" <>
    "- 出力言語: " <> iDocOutputLanguage[] <> "\n" <>
    "- 【最重要】段落の本文テキストのみを出力すること。" <>
    "「Let me」「まず」「では」等の前置き、思考過程、説明、メタコメントは絶対に含めない。" <>
    "出力の最初の文字から最後の文字まですべてが段落の本文でなければならない\n" <>
    "- マークダウン記法は使わない\n" <>
    "- Directives（指示）が提供されている場合は、その内容を厳守して生成する\n" <>
    "- Dictionary（辞書）が提供されている場合は、翻訳時にその用語対応を必ず使用する\n" <>
    "- 前後の文脈を考慮して、文書全体の流れに合った段落を生成する\n" <>
    "- アタッチされた資料がコンテキストに含まれる場合は参照してよいが、" <>
    "資料を読む過程は絶対に出力に含めない\n" <>
    "- リクエストを実行できない場合は、段落ではなく [ERROR]: に続けて理由を出力する\n\n" <>
    "プロンプト（アイデア）:\n" <> ideaText <>
    "\n\n現在の段落:\n" <> currentParagraph,
    "You are a skilled writer. Update the 'Current paragraph' below based on " <>
    "the 'Prompt (idea)' and any provided Directives.\n" <>
    "Rules:\n" <>
    "- Preserve the style, structure, and user edits of the current paragraph as much as possible\n" <>
    "- Update content based on the prompt, Directives, and document context\n" <>
    "- If references or literature are available in context, use them to improve accuracy\n" <>
    "- Output language: " <> iDocOutputLanguage[] <> "\n" <>
    "- CRITICAL: Output ONLY the paragraph body text. " <>
    "Do NOT include any preamble, thinking, meta-commentary, or explanation " <>
    "such as 'Let me...', 'I will...', 'Here is...', 'Based on...'. " <>
    "The very first character of your output must be the start of the paragraph itself\n" <>
    "- Do not use markdown formatting\n" <>
    "- If Directives are provided, strictly follow their instructions\n" <>
    "- If a Dictionary is provided, always use the specified term mappings when translating\n" <>
    "- Consider the surrounding context to produce a paragraph that fits the overall document flow\n" <>
    "- If attached files are mentioned in context, use their content but NEVER output your reading process\n" <>
    "- If you cannot fulfill the request, output ONLY: [ERROR]: followed by the reason\n\n" <>
    "Prompt (idea):\n" <> ideaText <>
    "\n\nCurrent paragraph:\n" <> currentParagraph
  ];

(* 翻訳更新プロンプト: 翻訳表示中に翻訳ボタンを押した場合、
   現在の翻訳を尊重しつつ、パラグラフ・指示・文脈に従い更新する *)
iDocUpdateTranslationPromptFn[currentTranslation_String, targetLang_String,
    paragraph_String, ideaText_String, context_String:""] :=
  context <>
  iL[
    "以下の「現在の翻訳」を更新してください。\n" <>
    "「対応するパラグラフ」の内容に忠実に、翻訳の品質を向上させてください。\n" <>
    If[ideaText =!= "", "「プロンプト」は段落の背景情報として参照してください。\n", ""] <>
    "ルール:\n" <>
    "- 現在の翻訳の文体・ユーザーの修正を最大限尊重する\n" <>
    "- 対応するパラグラフの内容に基づいて、翻訳の正確性・流暢さを向上させる\n" <>
    "- Directives（指示）が提供されている場合は、翻訳に関する指示を厳守する\n" <>
    "- Dictionary（辞書）が提供されている場合は、その用語対応を必ず使用する\n" <>
    "- 出力言語: " <> targetLang <> "\n" <>
    "- 【最重要】翻訳テキストのみを出力すること。" <>
    "前置き、思考過程、説明、メタコメントは絶対に含めない\n" <>
    "- マークダウン記法は使わない\n" <>
    "- 前後の文脈を考慮して、文書全体の流れに合った翻訳を生成する\n" <>
    "- リクエストを実行できない場合は、翻訳ではなく [ERROR]: に続けて理由を出力する\n\n" <>
    If[ideaText =!= "", "プロンプト:\n" <> ideaText <> "\n\n", ""] <>
    "対応するパラグラフ:\n" <> paragraph <>
    "\n\n現在の翻訳:\n" <> currentTranslation,
    "Update the 'Current translation' below to improve its quality.\n" <>
    "Base the update on the 'Corresponding paragraph' content.\n" <>
    If[ideaText =!= "", "The 'Prompt' provides background context for the paragraph.\n", ""] <>
    "Rules:\n" <>
    "- Preserve the style and user edits in the current translation as much as possible\n" <>
    "- Improve accuracy and fluency based on the corresponding paragraph\n" <>
    "- If Directives are provided, strictly follow translation-related instructions\n" <>
    "- If a Dictionary is provided, ALWAYS use the specified term mappings\n" <>
    "- Target language: " <> targetLang <> "\n" <>
    "- CRITICAL: Output ONLY the updated translation. " <>
    "Do NOT include any preamble, thinking, or meta-commentary. " <>
    "The very first character must be the start of the translation itself\n" <>
    "- Do not use markdown formatting\n" <>
    "- Consider the surrounding context to produce a translation that fits the overall document flow\n" <>
    "- If you cannot fulfill the request, output ONLY: [ERROR]: followed by the reason\n\n" <>
    If[ideaText =!= "", "Prompt:\n" <> ideaText <> "\n\n", ""] <>
    "Corresponding paragraph:\n" <> paragraph <>
    "\n\nCurrent translation:\n" <> currentTranslation
  ];

(* ============================================================
   セル書き込みヘルパー: 編集追跡付き
   ============================================================ *)

(* テキストを書き込み、クリーンコピーを保存する。
   切替時に編集検出に使う。 *)
iDocWriteAndTrack[nb_NotebookObject, cellIdx_Integer, text_String] :=
  Module[{savedScroll},
    savedScroll = Quiet[AbsoluteCurrentValue[nb, NotebookAutoScroll]];
    Quiet[SetOptions[nb, NotebookAutoScroll -> False]];
    NBAccess`NBInvalidateCellsCache[nb];
    NBAccess`NBCellWriteText[nb, cellIdx, text];
    NBAccess`NBCellSetTaggingRule[nb, cellIdx, $iDocTagCleanText, text];
    NBAccess`NBCellSetTaggingRule[nb, cellIdx, $iDocTagCleanMode,
      ToString[NBAccess`NBCellGetTaggingRule[nb, cellIdx, $iDocTagMode]] <> ":" <>
      ToString[TrueQ[NBAccess`NBCellGetTaggingRule[nb, cellIdx, $iDocTagShowTranslation]]]];
    NBAccess`NBSelectCell[nb, cellIdx];
    Quiet[SetOptions[nb, NotebookAutoScroll -> savedScroll]]];
DocExpandIdea[nb_NotebookObject, cellIdx_Integer, opts:OptionsPattern[]] :=
  Module[{mode, prevParagraph, useFallback, promptFn, context, dictionary, directives,
          currentParagraph, ideaText, prompt, privLevel, savedScroll},
    useFallback = TrueQ[OptionValue[Fallback]];

    (* Note/Dictionary/Directive セルは対象外 *)
    If[iDocIsMetaCell[nb, cellIdx], Return[$Failed]];

    (* 自動スクロールを無効化: 非同期LLM呼び出しによるジャンプを防止 *)
    savedScroll = Quiet[AbsoluteCurrentValue[nb, NotebookAutoScroll]];
    Quiet[SetOptions[nb, NotebookAutoScroll -> False]];

    (* 現在のモード確認 (NBAccess 経由) *)
    mode = NBAccess`NBCellGetTaggingRule[nb, cellIdx, $iDocTagMode];

    (* パラグラフ表示中 → パラグラフをインプレース更新 *)
    If[mode === "paragraph",
      NBAccess`NBInvalidateCellsCache[nb];
      currentParagraph = NBAccess`NBCellGetText[nb, cellIdx];
      ideaText = NBAccess`NBCellGetTaggingRule[nb, cellIdx, $iDocTagAlternate];
      If[!StringQ[currentParagraph] || StringTrim[currentParagraph] === "",
        Quiet[SetOptions[nb, NotebookAutoScroll -> savedScroll]];
        Return[$Failed]];
      If[!StringQ[ideaText], ideaText = ""];
      (* コンテキスト収集 *)
      directives = iDocCollectDirectives[nb];
      dictionary = iDocCollectDictionary[nb];
      context = directives <> dictionary <> iDocCollectContext[nb, cellIdx];
      prompt = iDocUpdateParagraphPromptFn[ideaText, currentParagraph, context];
      privLevel = NBAccess`NBCellPrivacyLevel[nb, cellIdx];
      Quiet[CurrentValue[nb, WindowStatusArea] =
        iL["パラグラフ更新中...", "Updating paragraph..."]];
      iDocSetJobAnchorCell[nb, cellIdx];
      With[{nb2 = nb, ci = cellIdx, ss = savedScroll},
        NBAccess`$NBLLMQueryFunc[prompt,
          Function[response,
            If[StringQ[response] && !StringStartsQ[response, "Error"] &&
               !StringStartsQ[response, "[ERROR]"],
              NBAccess`NBInvalidateCellsCache[nb2];
              iDocWriteAndTrack[nb2, ci, StringTrim[response]];
              (* 翻訳があれば連鎖更新 *)
              Module[{trans, tl, oldTrans, idea2,
                      ctx2, dict2, dir2},
                trans = NBAccess`NBCellGetTaggingRule[nb2, ci, $iDocTagTranslation];
                If[StringQ[trans] && StringTrim[trans] =!= "",
                  tl = iDocTranslationTargetForText[StringTrim[response]];
                  oldTrans = trans;
                  idea2 = NBAccess`NBCellGetTaggingRule[nb2, ci, $iDocTagAlternate];
                  If[!StringQ[idea2], idea2 = ""];
                  dir2 = iDocCollectDirectives[nb2];
                  dict2 = iDocCollectDictionary[nb2];
                  ctx2 = dir2 <> dict2 <> iDocCollectContext[nb2, ci];
                  NBAccess`$NBLLMQueryFunc[
                    iDocReTranslatePromptFn[StringTrim[response], tl, oldTrans, idea2, ctx2],
                    Function[tResponse,
                      If[StringQ[tResponse] && !StringStartsQ[tResponse, "Error"] &&
                         !StringStartsQ[tResponse, "[ERROR]"],
                        NBAccess`NBCellSetTaggingRule[nb2, ci,
                          $iDocTagTranslation, StringTrim[tResponse]];
                        NBAccess`NBCellSetTaggingRule[nb2, ci,
                          $iDocTagTranslationSrc, StringTrim[response]]];
                      Quiet[CurrentValue[nb2, WindowStatusArea] =
                        iL["更新完了", "Update complete"]];
                      NBAccess`NBSelectCell[nb2, ci];
                      Quiet[SetOptions[nb2, NotebookAutoScroll -> ss]];
                      RunScheduledTask[With[{pNb = nb2},
                        Quiet[CurrentValue[pNb, WindowStatusArea] = ""]], {3}]],
                    nb2, PrivacyLevel -> NBAccess`NBCellPrivacyLevel[nb2, ci],
                    Fallback -> useFallback],
                  (* 翻訳なし: 完了 *)
                  Quiet[CurrentValue[nb2, WindowStatusArea] =
                    iL["更新完了", "Update complete"]];
                  Quiet[SetOptions[nb2, NotebookAutoScroll -> ss]];
                  RunScheduledTask[With[{pNb = nb2},
                    Quiet[CurrentValue[pNb, WindowStatusArea] = ""]], {3}]]],
              (* エラー *)
              Quiet[CurrentValue[nb2, WindowStatusArea] =
                iL["更新エラー", "Update error"]];
              NBAccess`NBSelectCell[nb2, ci];
              Quiet[SetOptions[nb2, NotebookAutoScroll -> ss]];
              RunScheduledTask[With[{pNb = nb2},
                Quiet[CurrentValue[pNb, WindowStatusArea] = ""]], {3}]]],
          nb, PrivacyLevel -> privLevel, Fallback -> useFallback]];
      (* 非同期呼び出し直後にセル選択を復元: カーソルジャンプ防止 *)
      NBAccess`NBSelectCell[nb, cellIdx];
      Return[]];

    (* ノートブックコンテキスト収集: 周辺セル + アタッチメント情報 + 辞書 + 指示 *)
    context = iDocCollectContext[nb, cellIdx];
    directives = iDocCollectDirectives[nb];
    dictionary = iDocCollectDictionary[nb];
    context = directives <> dictionary <> context;

    (* プロンプト構築関数の選択 *)
    prevParagraph = If[mode === "idea",
      NBAccess`NBCellGetTaggingRule[nb, cellIdx, $iDocTagAlternate],
      None];
    promptFn = If[StringQ[prevParagraph] && StringTrim[prevParagraph] =!= "",
      With[{prev = prevParagraph, ctx = context},
        Function[t, iDocReExpandPromptFn[t, prev, ctx]]],
      With[{ctx = context},
        Function[t, iDocExpandPromptFn[t, ctx]]]
    ];

    (* 非同期 LLM 変換: カーネルをブロックしない。 *)
    iDocSetJobAnchorCell[nb, cellIdx];
    With[{nb2 = nb, cellAtts = iDocGetCurrentAttachments[nb], ss = savedScroll},
      NBAccess`NBCellTransformWithLLM[nb, cellIdx,
        promptFn,
        (* completionFn: LLM 応答後に実行されるコールバック *)
        Function[result,
          If[AssociationQ[result],
            Module[{ci = result["CellIdx"]},
              NBAccess`NBCellSetTaggingRule[nb2, ci, $iDocTagAlternate,
                result["OriginalText"]];
              NBAccess`NBCellSetTaggingRule[nb2, ci, $iDocTagMode, "paragraph"];
              NBAccess`NBCellSetOptions[nb2, ci,
                Sequence @@ $iDocParagraphCellOpts];
              (* 編集追跡: 展開結果をクリーンテキストとして記録 *)
              NBAccess`NBCellSetTaggingRule[nb2, ci,
                $iDocTagCleanText, result["Response"]];
              (* 依存資料: 展開時のアタッチメントを記録（既存設定がなければ） *)
              If[Length[iDocGetRefSources[nb2, ci]] === 0 &&
                 Length[cellAtts] > 0,
                Module[{pdfAtts},
                  pdfAtts = Select[cellAtts,
                    StringEndsQ[#, ".pdf", IgnoreCase -> True] &];
                  If[Length[pdfAtts] > 0,
                    iDocSetRefSources[nb2, ci,
                      {#, All} & /@ pdfAtts]]]];
              (* セル選択位置を復元 *)
              NBAccess`NBSelectCell[nb2, ci];
              Quiet[SetOptions[nb2, NotebookAutoScroll -> ss]]],
            (* エラー *)
            Quiet[SetOptions[nb2, NotebookAutoScroll -> ss]];
            MessageDialog[iL[
              "エラー: LLM 応答を取得できませんでした。",
              "Error: Could not get LLM response."]]]],
        Fallback -> useFallback]
    ];
    (* 非同期呼び出し直後にセル選択を復元: カーソルジャンプ防止 *)
    NBAccess`NBSelectCell[nb, cellIdx];
  ];
DocToggleView[nb_NotebookObject, cellIdx_Integer] :=
  Module[{currentText, mode, alternate, newMode, showTrans, transSrc,
          storedTranslation, cleanText, wasEdited, prevMode, prevShowTrans},
    (* Note/Dictionary/Directive セルは対象外 *)
    If[iDocIsMetaCell[nb, cellIdx], Return[$Failed]];
    NBAccess`NBInvalidateCellsCache[nb];
    mode = NBAccess`NBCellGetTaggingRule[nb, cellIdx, $iDocTagMode];
    showTrans = NBAccess`NBCellGetTaggingRule[nb, cellIdx, $iDocTagShowTranslation];

    (* 編集検出: cleanText と現在テキストを比較。
       cleanMode が現在のモードと一致する場合のみ編集ありと判定する。
       モードが変わっていれば cleanText は前のモードの残留値なので無視する。 *)
    cleanText = NBAccess`NBCellGetTaggingRule[nb, cellIdx, $iDocTagCleanText];
    currentText = NBAccess`NBCellGetText[nb, cellIdx];
    Module[{cleanMode, currentMode},
      cleanMode = NBAccess`NBCellGetTaggingRule[nb, cellIdx, $iDocTagCleanMode];
      currentMode = ToString[mode] <> ":" <> ToString[TrueQ[showTrans]];
      wasEdited = StringQ[cleanText] && StringQ[currentText] &&
        StringQ[cleanMode] && cleanMode === currentMode &&
        currentText =!= cleanText];
    prevMode = If[StringQ[mode], mode, ""];
    prevShowTrans = TrueQ[showTrans];

    (* ========================================================
       翻訳付きセル (mode="translated"): 元テキスト ↔ 翻訳
       ======================================================== *)
    If[mode === "translated",
      If[TrueQ[showTrans],
        (* 翻訳表示中 → 元テキストに戻す（水色枠） *)
        transSrc = NBAccess`NBCellGetTaggingRule[nb, cellIdx, $iDocTagTranslationSrc];
        If[StringQ[transSrc],
          (* 編集済みなら翻訳を保存 *)
          If[wasEdited,
            NBAccess`NBCellSetTaggingRule[nb, cellIdx,
              $iDocTagTranslation, currentText],
            NBAccess`NBCellSetTaggingRule[nb, cellIdx,
              $iDocTagTranslation, NBAccess`NBCellGetText[nb, cellIdx]]];
          NBAccess`NBCellSetTaggingRule[nb, cellIdx, $iDocTagShowTranslation, False];
          NBAccess`NBCellSetOptions[nb, cellIdx,
            Sequence @@ $iDocTranslatedCellOpts];
          iDocWriteAndTrack[nb, cellIdx, transSrc];],
        (* 元テキスト表示中 → 翻訳を表示（青枠） *)
        storedTranslation = NBAccess`NBCellGetTaggingRule[nb, cellIdx, $iDocTagTranslation];
        If[StringQ[storedTranslation] && StringTrim[storedTranslation] =!= "",
          NBAccess`NBCellSetTaggingRule[nb, cellIdx,
            $iDocTagTranslationSrc, NBAccess`NBCellGetText[nb, cellIdx]];
          NBAccess`NBCellSetTaggingRule[nb, cellIdx, $iDocTagShowTranslation, True];
          NBAccess`NBCellSetOptions[nb, cellIdx,
            Sequence @@ $iDocTranslationCellOpts];
          iDocWriteAndTrack[nb, cellIdx, storedTranslation];]];
      (* 編集済みならバックグラウンド同期 *)
      If[wasEdited,
        iDocPostToggleSync[nb, cellIdx, "translated", prevShowTrans,
          ClaudeCode`GetPaletteFallback[]]];
      Return[]];

    (* ========================================================
       翻訳表示中 (paragraph モード): 翻訳 → アイデアに戻す
       ======================================================== *)
    If[TrueQ[showTrans],
      transSrc = NBAccess`NBCellGetTaggingRule[nb, cellIdx, $iDocTagTranslationSrc];
      If[StringQ[transSrc],
        (* 編集済みなら翻訳を保存 *)
        If[wasEdited,
          NBAccess`NBCellSetTaggingRule[nb, cellIdx,
            $iDocTagTranslation, currentText],
          NBAccess`NBCellSetTaggingRule[nb, cellIdx,
            $iDocTagTranslation, NBAccess`NBCellGetText[nb, cellIdx]]];
        NBAccess`NBCellSetTaggingRule[nb, cellIdx, $iDocTagShowTranslation, False]];
      alternate = NBAccess`NBCellGetTaggingRule[nb, cellIdx, $iDocTagAlternate];
      If[mode === "paragraph" && StringQ[alternate],
        NBAccess`NBCellSetTaggingRule[nb, cellIdx, $iDocTagAlternate,
          If[StringQ[transSrc], transSrc,
            NBAccess`NBCellGetText[nb, cellIdx]]];
        NBAccess`NBCellSetTaggingRule[nb, cellIdx, $iDocTagMode, "idea"];
        NBAccess`NBCellSetOptions[nb, cellIdx,
          Sequence @@ $iDocIdeaCellOpts];
        iDocWriteAndTrack[nb, cellIdx, alternate];
        (* 編集済みならバックグラウンド同期 *)
        If[wasEdited,
          iDocPostToggleSync[nb, cellIdx, prevMode, True,
            ClaudeCode`GetPaletteFallback[]]];
        Return[alternate]];
      (* fallback: 翻訳元を復元 *)
      If[StringQ[transSrc],
        NBAccess`NBCellSetOptions[nb, cellIdx,
          CellFrame -> Inherited, CellFrameColor -> Inherited];
        iDocWriteAndTrack[nb, cellIdx, transSrc];];
      If[wasEdited,
        iDocPostToggleSync[nb, cellIdx, prevMode, True,
          ClaudeCode`GetPaletteFallback[]]];
      Return[]];

    (* ========================================================
       計算モード: compute ↔ computePrompt
       ======================================================== *)
    If[mode === "compute" || mode === "computePrompt",
      currentText = NBAccess`NBCellGetText[nb, cellIdx];
      alternate = NBAccess`NBCellGetTaggingRule[nb, cellIdx, $iDocTagAlternate];
      If[!StringQ[alternate], Return[$Failed]];

      If[mode === "compute",
        (* コード表示 → プロンプト表示 *)
        (* 編集済みならコードを更新保存 *)
        If[wasEdited,
          NBAccess`NBCellSetTaggingRule[nb, cellIdx, $iDocTagComputeCode, currentText]];
        NBAccess`NBCellSetTaggingRule[nb, cellIdx, $iDocTagMode, "computePrompt"];
        NBAccess`NBCellSetOptions[nb, cellIdx, Sequence @@ $iDocIdeaCellOpts];
        NBAccess`NBCellSetStyle[nb, cellIdx, "Text"];
        iDocWriteAndTrack[nb, cellIdx, alternate],
        (* プロンプト表示 → コード表示 *)
        Module[{code},
          (* 編集済みならプロンプトを更新保存 *)
          If[wasEdited,
            NBAccess`NBCellSetTaggingRule[nb, cellIdx, $iDocTagAlternate, currentText]];
          code = NBAccess`NBCellGetTaggingRule[nb, cellIdx, $iDocTagComputeCode];
          If[!StringQ[code], Return[$Failed]];
          NBAccess`NBCellSetTaggingRule[nb, cellIdx, $iDocTagMode, "compute"];
          NBAccess`NBCellSetOptions[nb, cellIdx, Sequence @@ $iDocComputeCellOpts];
          iDocWriteCodeAndTrack[nb, cellIdx, code]]];
      Return[]];

    (* ========================================================
       通常フロー: idea ↔ paragraph (→ 翻訳があれば翻訳)
       ======================================================== *)
    currentText = NBAccess`NBCellGetText[nb, cellIdx];
    alternate = NBAccess`NBCellGetTaggingRule[nb, cellIdx, $iDocTagAlternate];

    If[!StringQ[alternate],
      MessageDialog[iL[
        "このセルにはトグル可能なコンテンツがありません。\n先に「展開」を実行してください。",
        "No toggleable content in this cell.\nRun 'Expand' first."]];
      Return[$Failed]];

    (* パラグラフ表示中 → 翻訳があれば翻訳へ、なければアイデアへ *)
    If[mode === "paragraph",
      storedTranslation = NBAccess`NBCellGetTaggingRule[nb, cellIdx, $iDocTagTranslation];
      If[StringQ[storedTranslation] && StringTrim[storedTranslation] =!= "",
        NBAccess`NBCellSetTaggingRule[nb, cellIdx,
          $iDocTagTranslationSrc, currentText];
        NBAccess`NBCellSetTaggingRule[nb, cellIdx, $iDocTagShowTranslation, True];
        NBAccess`NBCellSetOptions[nb, cellIdx,
          Sequence @@ $iDocTranslationCellOpts];
        iDocWriteAndTrack[nb, cellIdx, storedTranslation];
        If[wasEdited,
          iDocPostToggleSync[nb, cellIdx, "paragraph", False,
            ClaudeCode`GetPaletteFallback[]]];
        Return[storedTranslation]]];

    (* idea ↔ paragraph の2段階トグル *)
    NBAccess`NBCellSetTaggingRule[nb, cellIdx, $iDocTagAlternate,
      If[StringQ[currentText], currentText, ""]];
    newMode = If[mode === "paragraph", "idea", "paragraph"];
    NBAccess`NBCellSetTaggingRule[nb, cellIdx, $iDocTagMode, newMode];
    NBAccess`NBCellSetOptions[nb, cellIdx,
      Sequence @@ If[newMode === "paragraph",
        $iDocParagraphCellOpts, $iDocIdeaCellOpts]];
    iDocWriteAndTrack[nb, cellIdx, alternate];

    (* 編集済みならバックグラウンド同期 *)
    If[wasEdited,
      iDocPostToggleSync[nb, cellIdx, prevMode, False,
        ClaudeCode`GetPaletteFallback[]]];

    alternate
  ];

(* ============================================================
   コア関数: 翻訳
   $Language が英語以外→英語に、英語→日本語に翻訳。
   翻訳結果は TaggingRules に保持し、切替可能。
   
   翻訳可能: パラグラフモード、普通のセル（モード未設定）
   翻訳不可: プロンプト（アイデア）モード、翻訳表示中
   
   再翻訳時は、プロンプト（あれば）を参照しつつ、
   ユーザーが修正した既存翻訳を踏襲して更新する。
   ============================================================ *)

(* 初回翻訳プロンプト: 普通のセル用（言語自動検出）
   テキストが primaryLang なら alternateLang に、それ以外なら primaryLang に翻訳する *)
iDocTranslateAutoPromptFn[text_String, primaryLang_String, alternateLang_String, context_String:""] :=
  context <>
  "Detect the language of the following text, then translate it.\n" <>
  "- If the text is in " <> primaryLang <> ", translate it into " <> alternateLang <> ".\n" <>
  "- If the text is in any other language, translate it into " <> primaryLang <> ".\n" <>
  "Rules:\n" <>
  "- Produce a natural, fluent translation\n" <>
  "- Preserve the original structure and meaning faithfully\n" <>
  "- CRITICAL: Output ONLY the translated text. " <>
  "Do NOT include any preamble, thinking, or meta-commentary " <>
  "such as 'Let me...', 'Here is...', 'The text is in...'. " <>
  "The very first character must be the start of the translation itself\n" <>
  "- Do not use markdown formatting\n" <>
  "- If Directives are provided above, strictly follow their instructions\n" <>
  "- If a Dictionary is provided above, ALWAYS use the specified term mappings for translation\n" <>
  "- Consider the surrounding context to produce a translation that fits the overall document flow\n" <>
  "- If you cannot fulfill the request, output ONLY: [ERROR]: followed by the reason\n\n" <>
  "Text to translate:\n" <> text;

(* パラグラフ用翻訳プロンプト: 固定ターゲット言語 *)
iDocTranslatePromptFn[text_String, targetLang_String, context_String:""] :=
  context <>
  "Translate the following text into " <> targetLang <> ".\n" <>
  "Rules:\n" <>
  "- Produce a natural, fluent translation\n" <>
  "- Preserve the original structure and meaning faithfully\n" <>
  "- CRITICAL: Output ONLY the translated text. " <>
  "Do NOT include any preamble, thinking, or meta-commentary. " <>
  "The very first character must be the start of the translation itself\n" <>
  "- Do not use markdown formatting\n" <>
  "- If Directives are provided above, strictly follow their instructions\n" <>
  "- If a Dictionary is provided above, ALWAYS use the specified term mappings for translation\n" <>
  "- Consider the surrounding context to produce a translation that fits the overall document flow\n" <>
  "- If you cannot fulfill the request, output ONLY: [ERROR]: followed by the reason\n\n" <>
  "Text to translate:\n" <> text;

(* 初回翻訳プロンプト（プロンプト参照付き） *)
iDocTranslateWithContextPromptFn[text_String, targetLang_String, ideaText_String, context_String:""] :=
  context <>
  "Translate the following paragraph into " <> targetLang <> ".\n" <>
  "The paragraph was written based on the 'Original prompt' below. " <>
  "Use it as context to improve translation accuracy.\n" <>
  "Rules:\n" <>
  "- Produce a natural, fluent translation\n" <>
  "- Preserve the original structure and meaning faithfully\n" <>
  "- CRITICAL: Output ONLY the translated text. " <>
  "Do NOT include any preamble, thinking, or meta-commentary. " <>
  "The very first character must be the start of the translation itself\n" <>
  "- Do not use markdown formatting\n" <>
  "- If Directives are provided above, strictly follow their instructions\n" <>
  "- If a Dictionary is provided above, ALWAYS use the specified term mappings for translation\n" <>
  "- Consider the surrounding context to produce a translation that fits the overall document flow\n" <>
  "- If you cannot fulfill the request, output ONLY: [ERROR]: followed by the reason\n\n" <>
  "Original prompt:\n" <> ideaText <>
  "\n\nParagraph to translate:\n" <> text;

(* 再翻訳プロンプト: 既存翻訳のユーザー修正を踏襲しつつ更新 *)
iDocReTranslatePromptFn[text_String, targetLang_String,
    prevTranslation_String, ideaText_String, context_String:""] :=
  context <>
  "The paragraph below has been updated. Revise the 'Previous translation' accordingly.\n" <>
  If[ideaText =!= "",
    "The 'Original prompt' provides context for what the paragraph is about.\n", ""] <>
  "Rules:\n" <>
  "- Preserve user edits in the previous translation as much as possible\n" <>
  "- Update only the parts that correspond to changes in the paragraph\n" <>
  "- Produce a natural, fluent " <> targetLang <> " translation\n" <>
  "- Output ONLY the revised translation, nothing else\n" <>
  "- CRITICAL: Do NOT include any preamble, thinking, or meta-commentary. " <>
  "The very first character must be the start of the revised translation itself\n" <>
  "- Do not use markdown formatting\n" <>
  "- If Directives are provided above, strictly follow their instructions\n" <>
  "- If a Dictionary is provided above, ALWAYS use the specified term mappings for translation\n" <>
  "- Consider the surrounding context to produce a translation that fits the overall document flow\n" <>
  "- If you cannot fulfill the request, output ONLY: [ERROR]: followed by the reason\n\n" <>
  If[ideaText =!= "",
    "Original prompt:\n" <> ideaText <> "\n\n", ""] <>
  "Updated paragraph:\n" <> text <>
  "\n\nPrevious translation:\n" <> prevTranslation;

DocTranslate[nb_NotebookObject, cellIdx_Integer, opts:OptionsPattern[]] :=
  Module[{currentText, storedTranslation, storedSrc, showTrans,
          mode, targetLang, useFallback, ideaText, promptFn,
          dictionary, directives, metaContext, privLevel, prompt, paragraph,
          savedScroll},
    useFallback = TrueQ[OptionValue[Fallback]];
    (* Note/Dictionary/Directive セルは対象外 *)
    If[iDocIsMetaCell[nb, cellIdx], Return[$Failed]];

    (* 自動スクロールを無効化: 非同期LLM呼び出しによるジャンプを防止 *)
    savedScroll = Quiet[AbsoluteCurrentValue[nb, NotebookAutoScroll]];
    Quiet[SetOptions[nb, NotebookAutoScroll -> False]];

    NBAccess`NBInvalidateCellsCache[nb];

    mode = NBAccess`NBCellGetTaggingRule[nb, cellIdx, $iDocTagMode];
    showTrans = NBAccess`NBCellGetTaggingRule[nb, cellIdx, $iDocTagShowTranslation];

    (* 翻訳不可: プロンプト（アイデア）モード *)
    If[mode === "idea",
      Quiet[SetOptions[nb, NotebookAutoScroll -> savedScroll]];
      MessageDialog[iL[
        "プロンプトモードでは翻訳できません。\n" <>
        "パラグラフに展開してから翻訳してください。",
        "Cannot translate in idea/prompt mode.\n" <>
        "Expand to paragraph first, then translate."]];
      Return[$Failed]];

    (* 翻訳表示中 → 翻訳をインプレース更新 *)
    If[TrueQ[showTrans],
      currentText = NBAccess`NBCellGetText[nb, cellIdx];
      If[!StringQ[currentText] || StringTrim[currentText] === "",
        Quiet[SetOptions[nb, NotebookAutoScroll -> savedScroll]];
        Return[$Failed]];
      paragraph = NBAccess`NBCellGetTaggingRule[nb, cellIdx, $iDocTagTranslationSrc];
      If[!StringQ[paragraph] || StringTrim[paragraph] === "",
        paragraph = ""];
      ideaText = NBAccess`NBCellGetTaggingRule[nb, cellIdx, $iDocTagAlternate];
      If[!StringQ[ideaText], ideaText = ""];
      (* 翻訳先言語: ソーステキストの言語に基づいて決定
         ソースが $Language と異なる言語 → $Language に翻訳
         ソースが $Language と同じ → $DocTranslationLanguage に翻訳 *)
      targetLang = If[StringQ[paragraph] && StringTrim[paragraph] =!= "",
        iDocTranslationTargetForText[paragraph],
        iDocTranslationTarget[]];
      (* コンテキスト収集 *)
      directives = iDocCollectDirectives[nb];
      dictionary = iDocCollectDictionary[nb];
      metaContext = directives <> dictionary <> iDocCollectContext[nb, cellIdx];
      prompt = iDocUpdateTranslationPromptFn[currentText, targetLang,
        paragraph, ideaText, metaContext];
      privLevel = NBAccess`NBCellPrivacyLevel[nb, cellIdx];
      Quiet[CurrentValue[nb, WindowStatusArea] =
        iL["翻訳更新中...", "Updating translation..."]];
      iDocSetJobAnchorCell[nb, cellIdx];
      With[{nb2 = nb, ci = cellIdx, srcPara = paragraph, ss = savedScroll},
        NBAccess`$NBLLMQueryFunc[prompt,
          Function[response,
            If[StringQ[response] && !StringStartsQ[response, "Error"] &&
               !StringStartsQ[response, "[ERROR]"],
              NBAccess`NBInvalidateCellsCache[nb2];
              NBAccess`NBCellSetTaggingRule[nb2, ci,
                $iDocTagTranslation, StringTrim[response]];
              If[srcPara =!= "",
                NBAccess`NBCellSetTaggingRule[nb2, ci,
                  $iDocTagTranslationSrc, srcPara]];
              iDocWriteAndTrack[nb2, ci, StringTrim[response]];
              Quiet[CurrentValue[nb2, WindowStatusArea] =
                iL["翻訳更新完了", "Translation update complete"]],
              (* エラー *)
              Quiet[CurrentValue[nb2, WindowStatusArea] =
                iL["翻訳更新エラー", "Translation update error"]];
              NBAccess`NBSelectCell[nb2, ci]];
            Quiet[SetOptions[nb2, NotebookAutoScroll -> ss]];
            RunScheduledTask[With[{pNb = nb2},
              Quiet[CurrentValue[pNb, WindowStatusArea] = ""]], {3}]],
          nb, PrivacyLevel -> privLevel, Fallback -> useFallback]];
      (* 非同期呼び出し直後にセル選択を復元: カーソルジャンプ防止 *)
      NBAccess`NBSelectCell[nb, cellIdx];
      Return[]];

    currentText = NBAccess`NBCellGetText[nb, cellIdx];
    If[!StringQ[currentText] || StringTrim[currentText] === "",
      Quiet[SetOptions[nb, NotebookAutoScroll -> savedScroll]];
      Return[$Failed]];

    storedTranslation = NBAccess`NBCellGetTaggingRule[nb, cellIdx, $iDocTagTranslation];
    storedSrc = NBAccess`NBCellGetTaggingRule[nb, cellIdx, $iDocTagTranslationSrc];
    (* 翻訳先言語: テキストの言語に基づいて決定
       テキストが $Language と異なる言語 → $Language に翻訳
       テキストが $Language と同じ → $DocTranslationLanguage に翻訳 *)
    targetLang = iDocTranslationTargetForText[currentText];

    (* プロンプト（アイデア）テキストを参照用に取得 *)
    ideaText = If[mode === "paragraph",
      NBAccess`NBCellGetTaggingRule[nb, cellIdx, $iDocTagAlternate],
      None];
    If[!StringQ[ideaText], ideaText = ""];

    (* 保存済み翻訳がありソースが一致 → 即表示（LLM不要） *)
    If[StringQ[storedTranslation] && StringTrim[storedTranslation] =!= "" &&
       StringQ[storedSrc] && storedSrc === currentText,
      (* 普通セルなら翻訳付きモードを設定 *)
      If[!StringQ[mode] || mode === "translated",
        NBAccess`NBCellSetTaggingRule[nb, cellIdx, $iDocTagMode, "translated"]];
      NBAccess`NBCellSetTaggingRule[nb, cellIdx,
        $iDocTagTranslationSrc, currentText];
      NBAccess`NBCellSetTaggingRule[nb, cellIdx, $iDocTagShowTranslation, True];
      NBAccess`NBCellSetOptions[nb, cellIdx,
        Sequence @@ $iDocTranslationCellOpts];
      NBAccess`NBInvalidateCellsCache[nb];
      NBAccess`NBCellWriteText[nb, cellIdx, storedTranslation];
      NBAccess`NBCellSetTaggingRule[nb, cellIdx, $iDocTagCleanText, storedTranslation];
      NBAccess`NBSelectCell[nb, cellIdx];
      Quiet[SetOptions[nb, NotebookAutoScroll -> savedScroll]];
      Return[]];

    (* Dictionary/Directives/Context 収集 *)
    directives = iDocCollectDirectives[nb];
    dictionary = iDocCollectDictionary[nb];
    metaContext = directives <> dictionary <> iDocCollectContext[nb, cellIdx];

    (* プロンプト構築: 既存翻訳の有無で分岐 *)
    promptFn = Which[
      (* 再翻訳: ソースが変わった + 既存翻訳あり → ユーザー修正を踏襲 *)
      StringQ[storedTranslation] && StringTrim[storedTranslation] =!= "",
        With[{prev = storedTranslation, idea = ideaText, tl = targetLang, ctx = metaContext},
          Function[t, iDocReTranslatePromptFn[t, tl, prev, idea, ctx]]],
      (* 初回翻訳: プロンプト参照付き（パラグラフモードの場合） *)
      ideaText =!= "",
        With[{idea = ideaText, tl = targetLang, ctx = metaContext},
          Function[t, iDocTranslateWithContextPromptFn[t, tl, idea, ctx]]],
      (* 初回翻訳: 普通のセル → 言語自動検出 *)
      True,
        With[{pl = iDocOutputLanguage[], al = iDocTranslationTarget[], ctx = metaContext},
          Function[t, iDocTranslateAutoPromptFn[t, pl, al, ctx]]]
    ];

    (* 非同期翻訳 *)
    iDocSetJobAnchorCell[nb, cellIdx];
    With[{nb2 = nb, srcText = currentText,
          isPlain = (!StringQ[mode] || mode === "translated"),
          ss = savedScroll},
      NBAccess`NBCellTransformWithLLM[nb, cellIdx,
        promptFn,
        (* completionFn *)
        Function[result,
          If[AssociationQ[result],
            Module[{ci = result["CellIdx"]},
              If[isPlain,
                NBAccess`NBCellSetTaggingRule[nb2, ci, $iDocTagMode, "translated"]];
              NBAccess`NBCellSetTaggingRule[nb2, ci,
                $iDocTagTranslationSrc, srcText];
              NBAccess`NBCellSetTaggingRule[nb2, ci,
                $iDocTagTranslation, result["Response"]];
              NBAccess`NBCellSetTaggingRule[nb2, ci,
                $iDocTagShowTranslation, True];
              NBAccess`NBCellSetOptions[nb2, ci,
                Sequence @@ $iDocTranslationCellOpts];
              (* 編集追跡: 翻訳結果をクリーンテキストとして記録 *)
              NBAccess`NBCellSetTaggingRule[nb2, ci,
                $iDocTagCleanText, result["Response"]];
              (* セル選択位置を復元 *)
              NBAccess`NBSelectCell[nb2, ci];
              Quiet[SetOptions[nb2, NotebookAutoScroll -> ss]]]];],
        Fallback -> useFallback]
    ];
    (* 非同期呼び出し直後にセル選択を復元: カーソルジャンプ防止 *)
    NBAccess`NBSelectCell[nb, cellIdx];
  ];
iDocFindSyncTag[nb_NotebookObject, tag_String] :=
  Module[{nCells, val},
    nCells = NBAccess`NBCellCount[nb];
    Do[
      val = NBAccess`NBCellGetTaggingRule[nb, i, {$iDocTagRoot, "syncTag"}];
      If[val === tag, Return[i, Module]],
    {i, nCells}];
    0
  ];


DocSync[nb_NotebookObject, cellIdx_Integer, opts:OptionsPattern[]] :=
  Module[{mode, showTrans, currentText, useFallback, ideaText, paragraph,
          translation, targetLang, prompt, context, syncTag,
          dictionary, directives},
    useFallback = TrueQ[OptionValue[Fallback]];
    (* Note/Dictionary/Directive セルは対象外 *)
    If[iDocIsMetaCell[nb, cellIdx], Return[$Failed]];
    NBAccess`NBInvalidateCellsCache[nb];
    mode = NBAccess`NBCellGetTaggingRule[nb, cellIdx, $iDocTagMode];
    showTrans = NBAccess`NBCellGetTaggingRule[nb, cellIdx, $iDocTagShowTranslation];
    currentText = NBAccess`NBCellGetText[nb, cellIdx];
    If[!StringQ[currentText] || StringTrim[currentText] === "",
      Return[$Failed]];

    directives = iDocCollectDirectives[nb];
    dictionary = iDocCollectDictionary[nb];
    context = directives <> dictionary <> iDocCollectContext[nb, cellIdx];

    (* セルにタグを付与: Job の進捗セル挿入でインデックスがずれても再発見可能にする *)
    syncTag = "doc-sync-" <> ToString[UnixTime[]] <> "-" <> ToString[RandomInteger[99999]];
    NBAccess`NBCellSetTaggingRule[nb, cellIdx, {$iDocTagRoot, "syncTag"}, syncTag];

    Which[
      (* === Case 1: プロンプト表示中 → パラグラフ再生成 (+翻訳連鎖) === *)
      mode === "idea",
        ideaText = currentText;
        paragraph = NBAccess`NBCellGetTaggingRule[nb, cellIdx, $iDocTagAlternate];
        translation = NBAccess`NBCellGetTaggingRule[nb, cellIdx, $iDocTagTranslation];
        (* 翻訳先: 既存パラグラフの言語から決定（再生成後も同じ言語のため） *)
        targetLang = If[StringQ[paragraph] && StringTrim[paragraph] =!= "",
          iDocTranslationTargetForText[paragraph],
          iDocTranslationTarget[]];
        prompt = If[StringQ[paragraph] && StringTrim[paragraph] =!= "",
          iDocReExpandPromptFn[ideaText, paragraph, context],
          iDocExpandPromptFn[ideaText, context]];
        Quiet[CurrentValue[nb, WindowStatusArea] =
          iL["同期中: パラグラフ生成...", "Syncing: generating paragraph..."]];
        iDocSetJobAnchorCell[nb, cellIdx];
        With[{nb2 = nb, origIdx = cellIdx, tl = targetLang, fb = useFallback,
              hasTranslation = StringQ[translation] && StringTrim[translation] =!= "",
              oldTranslation = If[StringQ[translation], translation, ""],
              idea = ideaText, stag = syncTag, ctx = context},
          NBAccess`$NBLLMQueryFunc[prompt,
            Function[response,
              Module[{idx},
              NBAccess`NBInvalidateCellsCache[nb2];
              idx = iDocFindSyncTag[nb2, stag];
              If[idx === 0, idx = origIdx];
              If[StringQ[response] && !StringStartsQ[response, "Error"] &&
                 !StringStartsQ[response, "[ERROR]"],
                Module[{newPara = StringTrim[response]},
                  NBAccess`NBCellSetTaggingRule[nb2, idx,
                    $iDocTagAlternate, newPara];
                  If[hasTranslation,
                    Quiet[CurrentValue[nb2, WindowStatusArea] =
                      iL["同期中: 翻訳更新...", "Syncing: updating translation..."]];
                    Module[{tPrompt = iDocReTranslatePromptFn[
                        newPara, tl, oldTranslation, idea, ctx]},
                      NBAccess`$NBLLMQueryFunc[tPrompt,
                        Function[tResponse,
                          Module[{idx2},
                          NBAccess`NBInvalidateCellsCache[nb2];
                          idx2 = iDocFindSyncTag[nb2, stag];
                          If[idx2 === 0, idx2 = origIdx];
                          If[StringQ[tResponse] && !StringStartsQ[tResponse, "Error"] &&
                             !StringStartsQ[tResponse, "[ERROR]"],
                            NBAccess`NBCellSetTaggingRule[nb2, idx2,
                              $iDocTagTranslation, StringTrim[tResponse]];
                            NBAccess`NBCellSetTaggingRule[nb2, idx2,
                              $iDocTagTranslationSrc, newPara]];
                          NBAccess`NBCellSetTaggingRule[nb2, idx2,
                            {$iDocTagRoot, "syncTag"}, Inherited];
                          Quiet[CurrentValue[nb2, WindowStatusArea] =
                            iL["同期完了", "Sync complete"]];
                          RunScheduledTask[With[{pNb = nb2},
                            Quiet[CurrentValue[pNb, WindowStatusArea] = ""]], {3}]]],
                        nb2, PrivacyLevel -> NBAccess`NBCellPrivacyLevel[nb2, idx],
                        Fallback -> fb]],
                    NBAccess`NBCellSetTaggingRule[nb2, idx,
                      {$iDocTagRoot, "syncTag"}, Inherited];
                    Quiet[CurrentValue[nb2, WindowStatusArea] =
                      iL["同期完了", "Sync complete"]];
                    RunScheduledTask[With[{pNb = nb2},
                      Quiet[CurrentValue[pNb, WindowStatusArea] = ""]], {3}]]],
                NBAccess`NBCellSetTaggingRule[nb2, idx,
                  {$iDocTagRoot, "syncTag"}, Inherited];
                Quiet[CurrentValue[nb2, WindowStatusArea] =
                  iL["同期エラー", "Sync error"]];
                RunScheduledTask[With[{pNb = nb2},
                  Quiet[CurrentValue[pNb, WindowStatusArea] = ""]], {3}]]]],
            nb, PrivacyLevel -> NBAccess`NBCellPrivacyLevel[nb, cellIdx],
            Fallback -> useFallback]],

      (* === Case 2: パラグラフ表示中 → 翻訳を再生成 === *)
      mode === "paragraph",
        paragraph = currentText;
        translation = NBAccess`NBCellGetTaggingRule[nb, cellIdx, $iDocTagTranslation];
        ideaText = NBAccess`NBCellGetTaggingRule[nb, cellIdx, $iDocTagAlternate];
        If[!StringQ[ideaText], ideaText = ""];
        (* 翻訳先: パラグラフの言語から決定 *)
        targetLang = iDocTranslationTargetForText[paragraph];
        If[!StringQ[translation] || StringTrim[translation] === "",
          NBAccess`NBCellSetTaggingRule[nb, cellIdx,
            {$iDocTagRoot, "syncTag"}, Inherited];
          MessageDialog[iL[
            "翻訳がありません。先に翻訳ボタンで翻訳を生成してください。",
            "No translation exists. Use the Translate button first."]];
          Return[$Failed]];
        prompt = iDocReTranslatePromptFn[paragraph, targetLang, translation, ideaText, context];
        Quiet[CurrentValue[nb, WindowStatusArea] =
          iL["同期中: 翻訳更新...", "Syncing: updating translation..."]];
        iDocSetJobAnchorCell[nb, cellIdx];
        With[{nb2 = nb, origIdx = cellIdx, srcPara = paragraph, stag = syncTag},
          NBAccess`$NBLLMQueryFunc[prompt,
            Function[response,
              Module[{idx},
              NBAccess`NBInvalidateCellsCache[nb2];
              idx = iDocFindSyncTag[nb2, stag];
              If[idx === 0, idx = origIdx];
              If[StringQ[response] && !StringStartsQ[response, "Error"] &&
                 !StringStartsQ[response, "[ERROR]"],
                NBAccess`NBCellSetTaggingRule[nb2, idx,
                  $iDocTagTranslation, StringTrim[response]];
                NBAccess`NBCellSetTaggingRule[nb2, idx,
                  $iDocTagTranslationSrc, srcPara]];
              NBAccess`NBCellSetTaggingRule[nb2, idx,
                {$iDocTagRoot, "syncTag"}, Inherited];
              Quiet[CurrentValue[nb2, WindowStatusArea] =
                iL["同期完了", "Sync complete"]];
              RunScheduledTask[With[{pNb = nb2},
                Quiet[CurrentValue[pNb, WindowStatusArea] = ""]], {3}]]],
            nb, PrivacyLevel -> NBAccess`NBCellPrivacyLevel[nb, cellIdx],
            Fallback -> useFallback]],

      (* === Case 3: 翻訳表示中 → パラグラフを逆更新 === *)
      TrueQ[showTrans],
        translation = currentText;
        paragraph = NBAccess`NBCellGetTaggingRule[nb, cellIdx, $iDocTagTranslationSrc];
        If[!StringQ[paragraph] || StringTrim[paragraph] === "",
          NBAccess`NBCellSetTaggingRule[nb, cellIdx,
            {$iDocTagRoot, "syncTag"}, Inherited];
          Return[$Failed]];
        ideaText = NBAccess`NBCellGetTaggingRule[nb, cellIdx, $iDocTagAlternate];
        If[!StringQ[ideaText], ideaText = ""];
        prompt = iDocReverseSyncPromptFn[translation, paragraph,
          ideaText, iDocOutputLanguage[], context];
        Quiet[CurrentValue[nb, WindowStatusArea] =
          iL["同期中: パラグラフ更新...", "Syncing: updating paragraph..."]];
        iDocSetJobAnchorCell[nb, cellIdx];
        With[{nb2 = nb, origIdx = cellIdx, m = mode, stag = syncTag},
          NBAccess`$NBLLMQueryFunc[prompt,
            Function[response,
              Module[{idx},
              NBAccess`NBInvalidateCellsCache[nb2];
              idx = iDocFindSyncTag[nb2, stag];
              If[idx === 0, idx = origIdx];
              If[StringQ[response] && !StringStartsQ[response, "Error"] &&
                 !StringStartsQ[response, "[ERROR]"],
                Module[{newPara = StringTrim[response]},
                  NBAccess`NBCellSetTaggingRule[nb2, idx,
                    $iDocTagTranslationSrc, newPara]]];
              NBAccess`NBCellSetTaggingRule[nb2, idx,
                {$iDocTagRoot, "syncTag"}, Inherited];
              Quiet[CurrentValue[nb2, WindowStatusArea] =
                iL["同期完了", "Sync complete"]];
              RunScheduledTask[With[{pNb = nb2},
                Quiet[CurrentValue[pNb, WindowStatusArea] = ""]], {3}]]],
            nb, PrivacyLevel -> NBAccess`NBCellPrivacyLevel[nb, cellIdx],
            Fallback -> useFallback]],

      (* === それ以外: 同期対象なし === *)
      True,
        NBAccess`NBCellSetTaggingRule[nb, cellIdx,
          {$iDocTagRoot, "syncTag"}, Inherited];
        MessageDialog[iL[
          "このセルには同期可能なコンテンツがありません。",
          "No syncable content in this cell."]]
    ];
  ];

(* ============================================================
   一括表示切替
   展開済みセル（idea/paragraph/translated モード）の表示を一括で切り替える。
   ============================================================ *)

iDocShowAllAs[targetView_String] :=
  Module[{nb = iDocUserNotebook[], nCells, mode, showTrans, alternate,
          storedTranslation, transSrc, currentText, count = 0,
          (* 2パス: まず変更計画を収集し、次に一括適用する。
             1パスでは NBCellWriteText と NBCellGetText の交互実行で
             キャッシュ不整合が発生しセルが破損する。 *)
          plan = {}},
    If[Head[nb] =!= NotebookObject, Return[]];
    NBAccess`NBInvalidateCellsCache[nb];
    nCells = NBAccess`NBCellCount[nb];

    (* === Pass 1: 変更計画の収集 === *)
    Do[
      NBAccess`NBInvalidateCellsCache[nb];
      mode = NBAccess`NBCellGetTaggingRule[nb, i, $iDocTagMode];
      showTrans = NBAccess`NBCellGetTaggingRule[nb, i, $iDocTagShowTranslation];
      If[StringQ[mode],
        Which[
          (* === 全プロンプト === *)
          targetView === "idea" && mode === "paragraph" && !TrueQ[showTrans],
            alternate = NBAccess`NBCellGetTaggingRule[nb, i, $iDocTagAlternate];
            currentText = NBAccess`NBCellGetText[nb, i];
            If[StringQ[alternate] && StringTrim[alternate] =!= "",
              AppendTo[plan, <|"idx" -> i, "action" -> "para->idea",
                "writeText" -> alternate,
                "storeAlt" -> If[StringQ[currentText], currentText, ""]|>]],

          targetView === "idea" && TrueQ[showTrans] && mode === "paragraph",
            transSrc = NBAccess`NBCellGetTaggingRule[nb, i, $iDocTagTranslationSrc];
            alternate = NBAccess`NBCellGetTaggingRule[nb, i, $iDocTagAlternate];
            currentText = NBAccess`NBCellGetText[nb, i];
            If[StringQ[transSrc] && StringQ[alternate] &&
               StringTrim[alternate] =!= "",
              AppendTo[plan, <|"idx" -> i, "action" -> "trans->idea",
                "writeText" -> alternate, "storeAlt" -> transSrc,
                "saveTrans" -> currentText|>]],

          (* === 全パラグラフ === *)
          targetView === "paragraph" && mode === "idea",
            alternate = NBAccess`NBCellGetTaggingRule[nb, i, $iDocTagAlternate];
            currentText = NBAccess`NBCellGetText[nb, i];
            If[StringQ[alternate] && StringTrim[alternate] =!= "",
              AppendTo[plan, <|"idx" -> i, "action" -> "idea->para",
                "writeText" -> alternate,
                "storeAlt" -> If[StringQ[currentText], currentText, ""]|>]],

          targetView === "paragraph" && TrueQ[showTrans] && mode === "paragraph",
            transSrc = NBAccess`NBCellGetTaggingRule[nb, i, $iDocTagTranslationSrc];
            currentText = NBAccess`NBCellGetText[nb, i];
            If[StringQ[transSrc] && StringTrim[transSrc] =!= "",
              AppendTo[plan, <|"idx" -> i, "action" -> "trans->para",
                "writeText" -> transSrc, "saveTrans" -> currentText|>]],

          (* === 全翻訳 === *)
          targetView === "translation" && !TrueQ[showTrans] && mode === "idea",
            (* idea → translation: まず paragraph に戻してから翻訳表示 *)
            storedTranslation = NBAccess`NBCellGetTaggingRule[nb, i, $iDocTagTranslation];
            alternate = NBAccess`NBCellGetTaggingRule[nb, i, $iDocTagAlternate];
            currentText = NBAccess`NBCellGetText[nb, i];
            If[StringQ[storedTranslation] && StringTrim[storedTranslation] =!= "" &&
               StringQ[alternate] && StringTrim[alternate] =!= "",
              AppendTo[plan, <|"idx" -> i, "action" -> "idea->trans",
                "writeText" -> storedTranslation,
                "storeAlt" -> If[StringQ[currentText], currentText, ""],
                "paragraph" -> alternate|>]],

          targetView === "translation" && !TrueQ[showTrans] && mode =!= "idea",
            storedTranslation = NBAccess`NBCellGetTaggingRule[nb, i, $iDocTagTranslation];
            currentText = NBAccess`NBCellGetText[nb, i];
            If[StringQ[storedTranslation] && StringTrim[storedTranslation] =!= "",
              AppendTo[plan, <|"idx" -> i, "action" -> "show-trans",
                "writeText" -> storedTranslation,
                "saveTransSrc" -> If[StringQ[currentText], currentText, ""]|>]]
        ]];
      (* translated モード *)
      If[mode === "translated",
        Which[
          targetView === "translation" && !TrueQ[showTrans],
            storedTranslation = NBAccess`NBCellGetTaggingRule[nb, i, $iDocTagTranslation];
            currentText = NBAccess`NBCellGetText[nb, i];
            If[StringQ[storedTranslation] && StringTrim[storedTranslation] =!= "",
              AppendTo[plan, <|"idx" -> i, "action" -> "translated-show",
                "writeText" -> storedTranslation,
                "saveTransSrc" -> If[StringQ[currentText], currentText, ""]|>]],
          (targetView === "idea" || targetView === "paragraph") && TrueQ[showTrans],
            transSrc = NBAccess`NBCellGetTaggingRule[nb, i, $iDocTagTranslationSrc];
            currentText = NBAccess`NBCellGetText[nb, i];
            If[StringQ[transSrc] && StringTrim[transSrc] =!= "",
              AppendTo[plan, <|"idx" -> i, "action" -> "translated-revert",
                "writeText" -> transSrc, "saveTrans" -> currentText|>]]
        ]],
    {i, nCells}];

    (* === Pass 2: 一括適用 === *)
    Do[
      Module[{idx = p["idx"], act = p["action"]},
        NBAccess`NBInvalidateCellsCache[nb];
        Which[
          act === "para->idea",
            NBAccess`NBCellSetTaggingRule[nb, idx, $iDocTagAlternate, p["storeAlt"]];
            NBAccess`NBCellSetTaggingRule[nb, idx, $iDocTagMode, "idea"];
            NBAccess`NBCellSetOptions[nb, idx, Sequence @@ $iDocIdeaCellOpts];
            NBAccess`NBInvalidateCellsCache[nb];
            NBAccess`NBCellWriteText[nb, idx, p["writeText"]];
            NBAccess`NBCellSetTaggingRule[nb, idx, $iDocTagCleanText, p["writeText"]],

          act === "trans->idea",
            NBAccess`NBCellSetTaggingRule[nb, idx,
              $iDocTagTranslation, p["saveTrans"]];
            NBAccess`NBCellSetTaggingRule[nb, idx, $iDocTagShowTranslation, False];
            NBAccess`NBCellSetTaggingRule[nb, idx, $iDocTagAlternate, p["storeAlt"]];
            NBAccess`NBCellSetTaggingRule[nb, idx, $iDocTagMode, "idea"];
            NBAccess`NBCellSetOptions[nb, idx, Sequence @@ $iDocIdeaCellOpts];
            NBAccess`NBInvalidateCellsCache[nb];
            NBAccess`NBCellWriteText[nb, idx, p["writeText"]];
            NBAccess`NBCellSetTaggingRule[nb, idx, $iDocTagCleanText, p["writeText"]],

          act === "idea->para",
            NBAccess`NBCellSetTaggingRule[nb, idx, $iDocTagAlternate, p["storeAlt"]];
            NBAccess`NBCellSetTaggingRule[nb, idx, $iDocTagMode, "paragraph"];
            NBAccess`NBCellSetOptions[nb, idx, Sequence @@ $iDocParagraphCellOpts];
            NBAccess`NBInvalidateCellsCache[nb];
            NBAccess`NBCellWriteText[nb, idx, p["writeText"]];
            NBAccess`NBCellSetTaggingRule[nb, idx, $iDocTagCleanText, p["writeText"]],

          act === "trans->para",
            NBAccess`NBCellSetTaggingRule[nb, idx,
              $iDocTagTranslation, p["saveTrans"]];
            NBAccess`NBCellSetTaggingRule[nb, idx, $iDocTagShowTranslation, False];
            NBAccess`NBCellSetOptions[nb, idx, Sequence @@ $iDocParagraphCellOpts];
            NBAccess`NBInvalidateCellsCache[nb];
            NBAccess`NBCellWriteText[nb, idx, p["writeText"]];
            NBAccess`NBCellSetTaggingRule[nb, idx, $iDocTagCleanText, p["writeText"]],

          act === "show-trans",
            NBAccess`NBCellSetTaggingRule[nb, idx,
              $iDocTagTranslationSrc, p["saveTransSrc"]];
            NBAccess`NBCellSetTaggingRule[nb, idx, $iDocTagShowTranslation, True];
            NBAccess`NBCellSetOptions[nb, idx, Sequence @@ $iDocTranslationCellOpts];
            NBAccess`NBInvalidateCellsCache[nb];
            NBAccess`NBCellWriteText[nb, idx, p["writeText"]];
            NBAccess`NBCellSetTaggingRule[nb, idx, $iDocTagCleanText, p["writeText"]],

          act === "idea->trans",
            (* idea → paragraph → translation を一括で実行 *)
            NBAccess`NBCellSetTaggingRule[nb, idx, $iDocTagAlternate, p["storeAlt"]];
            NBAccess`NBCellSetTaggingRule[nb, idx, $iDocTagMode, "paragraph"];
            NBAccess`NBCellSetTaggingRule[nb, idx,
              $iDocTagTranslationSrc, p["paragraph"]];
            NBAccess`NBCellSetTaggingRule[nb, idx, $iDocTagShowTranslation, True];
            NBAccess`NBCellSetOptions[nb, idx, Sequence @@ $iDocTranslationCellOpts];
            NBAccess`NBInvalidateCellsCache[nb];
            NBAccess`NBCellWriteText[nb, idx, p["writeText"]];
            NBAccess`NBCellSetTaggingRule[nb, idx, $iDocTagCleanText, p["writeText"]],

          act === "translated-show",
            NBAccess`NBCellSetTaggingRule[nb, idx,
              $iDocTagTranslationSrc, p["saveTransSrc"]];
            NBAccess`NBCellSetTaggingRule[nb, idx, $iDocTagShowTranslation, True];
            NBAccess`NBCellSetOptions[nb, idx, Sequence @@ $iDocTranslationCellOpts];
            NBAccess`NBInvalidateCellsCache[nb];
            NBAccess`NBCellWriteText[nb, idx, p["writeText"]];
            NBAccess`NBCellSetTaggingRule[nb, idx, $iDocTagCleanText, p["writeText"]],

          act === "translated-revert",
            NBAccess`NBCellSetTaggingRule[nb, idx,
              $iDocTagTranslation, p["saveTrans"]];
            NBAccess`NBCellSetTaggingRule[nb, idx, $iDocTagShowTranslation, False];
            NBAccess`NBCellSetOptions[nb, idx, Sequence @@ $iDocTranslatedCellOpts];
            NBAccess`NBInvalidateCellsCache[nb];
            NBAccess`NBCellWriteText[nb, idx, p["writeText"]];
            NBAccess`NBCellSetTaggingRule[nb, idx, $iDocTagCleanText, p["writeText"]]
        ];
        count++],
    {p, plan}];

    If[count > 0,
      Quiet[CurrentValue[nb, WindowStatusArea] =
        iL[ToString[count] <> " セルを切り替えました。",
           ToString[count] <> " cells switched."]];
      RunScheduledTask[With[{pNb = nb},
        Quiet[CurrentValue[pNb, WindowStatusArea] = ""]], {3}]];
  ];

(* ============================================================
   全翻訳: 未翻訳セルを翻訳してから全セルを翻訳表示に切り替える
   ============================================================ *)

iDocTranslateAllAndShow[] :=
  Module[{nb = iDocUserNotebook[], nCells, needTranslation = {},
          mode, showTrans, storedTranslation, text, fb},
    If[Head[nb] =!= NotebookObject, Return[]];
    fb = ClaudeCode`GetPaletteFallback[];
    NBAccess`NBInvalidateCellsCache[nb];
    nCells = NBAccess`NBCellCount[nb];

    (* 翻訳が必要なセルを収集:
       - paragraph モードで翻訳なし
       - translated モードで翻訳なし
       - idea モードはスキップ（パラグラフに展開してから翻訳）
       - メタセルはスキップ *)
    Do[
      If[!iDocIsMetaCell[nb, i] &&
         !TrueQ[NBAccess`NBCellGetTaggingRule[nb, i, $iDocTagExcludeExport]],
        mode = NBAccess`NBCellGetTaggingRule[nb, i, $iDocTagMode];
        showTrans = NBAccess`NBCellGetTaggingRule[nb, i, $iDocTagShowTranslation];
        storedTranslation = NBAccess`NBCellGetTaggingRule[nb, i, $iDocTagTranslation];
        text = NBAccess`NBCellGetText[nb, i];
        (* 画像セルはスキップ *)
        If[NBAccess`NBCellHasImage[NBAccess`NBCellRead[nb, i]], Continue[]];
        (* 翻訳が必要: documentation モードを持つセル + 翻訳なし + テキストあり *)
        If[StringQ[mode] && mode =!= "idea" &&
           (!StringQ[storedTranslation] || StringTrim[storedTranslation] === "") &&
           !TrueQ[showTrans] &&
           StringQ[text] && StringLength[text] > 10,
          AppendTo[needTranslation, i]]],
    {i, nCells}];

    If[Length[needTranslation] === 0,
      (* 全セル翻訳済み → 即座に翻訳表示に切り替え *)
      iDocShowAllAs["translation"];
      Return[]];

    (* 未翻訳セルを非同期チェーンで翻訳し、完了後に全翻訳表示 *)
    Quiet[CurrentValue[nb, WindowStatusArea] =
      iL["全翻訳中: 0/" <> ToString[Length[needTranslation]],
         "Translating all: 0/" <> ToString[Length[needTranslation]]]];
    iDocTranslateAllChain[nb, needTranslation, 1, fb,
      Length[needTranslation]]
  ];

(* 非同期チェーン: 1セルずつ翻訳し、完了後に全翻訳表示 *)
iDocTranslateAllChain[nb_, idxs_, pos_, fb_, total_] :=
  If[pos > Length[idxs],
    (* 全翻訳完了 → 全セルを翻訳表示に切り替え *)
    Quiet[CurrentValue[nb, WindowStatusArea] =
      iL[ToString[total] <> " セルの翻訳完了。表示を切替中...",
         ToString[total] <> " cells translated. Switching view..."]];
    RunScheduledTask[
      (NBAccess`NBInvalidateCellsCache[nb];
       iDocShowAllAs["translation"];
       Quiet[CurrentValue[nb, WindowStatusArea] =
         iL["全翻訳表示完了", "All translations displayed"]];
       RunScheduledTask[With[{pNb = nb},
         Quiet[CurrentValue[pNb, WindowStatusArea] = ""]], {3}]),
      {1}],
    Module[{cellIdx = idxs[[pos]], mode},
      Quiet[CurrentValue[nb, WindowStatusArea] =
        iL["全翻訳中: ", "Translating all: "] <>
          ToString[pos] <> "/" <> ToString[total]];
      mode = NBAccess`NBCellGetTaggingRule[nb, cellIdx, $iDocTagMode];
      If[mode === "idea" || iDocIsMetaCell[nb, cellIdx],
        (* スキップ *)
        iDocTranslateAllChain[nb, idxs, pos + 1, fb, total],
        (* 翻訳実行 *)
        DocTranslate[nb, cellIdx, Fallback -> fb];
        (* DocTranslate は非同期なので、遅延で次へ進む *)
        RunScheduledTask[
          With[{pNb = nb, is = idxs, p = pos, f = fb, t = total},
            iDocTranslateAllChain[pNb, is, p + 1, f, t]], {2}]]]
  ];

(* ============================================================
   パレットボタンアクション
   ============================================================ *)

SetAttributes[iDocButton, HoldRest];
iDocButton[label_String, color_, action_] :=
  Button[
    Style[label, Bold, 9, White],
    CompoundExpression[action,
      With[{inb = InputNotebook[]},
        If[Head[inb] === NotebookObject,
          SetSelectedNotebook[inb]]]],
    Appearance -> "Frameless",
    Background -> color,
    ImageSize -> {100, 18},
    FrameMargins -> {{4, 4}, {1, 1}},
    Method -> "Queued"
  ];

(* 2列配置用: 幅48のボタンを横に2つ並べる *)
SetAttributes[iDocButton2, HoldRest];
iDocButton2[label_String, color_, action_] :=
  Button[
    Style[label, Bold, 7, White],
    CompoundExpression[action,
      With[{inb = InputNotebook[]},
        If[Head[inb] === NotebookObject,
          SetSelectedNotebook[inb]]]],
    Appearance -> "Frameless",
    Background -> color,
    ImageSize -> {49, 18},
    FrameMargins -> {{1, 1}, {1, 1}},
    Method -> "Queued"
  ];

iDocButtonRow[b1_, b2_] :=
  Grid[{{b1, b2}}, Spacings -> 0.1, ItemSize -> {Automatic, Automatic}];

iDocExpandSelected[] :=
  Module[{nb, cellIdxs},
    {nb, cellIdxs} = iDocResolveTargetCells[];
    If[Length[cellIdxs] === 0,
      MessageDialog[iL["セルを選択してください。", "Please select a cell."]];
      Return[$Failed]];
    If[Length[cellIdxs] === 1,
      DocExpandIdea[nb, First[cellIdxs], Fallback -> ClaudeCode`GetPaletteFallback[]];
      NBAccess`NBSelectCell[nb, First[cellIdxs]],
      (* 複数セル: 非同期チェーンで逐次展開 *)
      iDocExpandSelectedChain[nb, cellIdxs, 1, ClaudeCode`GetPaletteFallback[]]]
  ];

iDocExpandSelectedChain[nb_, idxs_, pos_, fb_] :=
  If[pos > Length[idxs],
    Quiet[CurrentValue[nb, WindowStatusArea] =
      iL[ToString[Length[idxs]] <> " セルを展開しました。",
         ToString[Length[idxs]] <> " cells expanded."]];
    RunScheduledTask[With[{pNb = nb},
      Quiet[CurrentValue[pNb, WindowStatusArea] = ""]], {3}],
    Quiet[CurrentValue[nb, WindowStatusArea] =
      iL["展開中: ", "Expanding: "] <> ToString[pos] <> "/" <> ToString[Length[idxs]]];
    Module[{cellIdx = idxs[[pos]]},
      If[iDocIsMetaCell[nb, cellIdx],
        (* Note/Dictionary/Directive セルはスキップ *)
        iDocExpandSelectedChain[nb, idxs, pos + 1, fb],
        (* 展開: completionFn 内で次へ進む。
           DocExpandIdea は内部で NBCellTransformWithLLM を使い、
           completionFn でメタデータを設定する。ここでは追加の完了処理として
           チェーンの次ステップを呼ぶ。 *)
        DocExpandIdea[nb, cellIdx, Fallback -> fb];
        (* DocExpandIdea は非同期なので即座に次へ進めない。
           代わに ScheduledTask で遅延実行して次のセルへ。 *)
        RunScheduledTask[
          With[{pNb = nb, is = idxs, p = pos, f = fb},
            iDocExpandSelectedChain[pNb, is, p + 1, f]], {2}]]]
  ];

iDocToggleSelected[] :=
  Module[{nb, cellIdx},
    {nb, cellIdx} = iDocResolveTargetCell[];
    If[cellIdx === 0,
      MessageDialog[iL["セルを選択してください。", "Please select a cell."]];
      Return[$Failed]];
    DocToggleView[nb, cellIdx]
  ];

iDocTranslateSelected[] :=
  Module[{nb, cellIdxs},
    {nb, cellIdxs} = iDocResolveTargetCells[];
    If[Length[cellIdxs] === 0,
      MessageDialog[iL["セルを選択してください。", "Please select a cell."]];
      Return[$Failed]];
    If[Length[cellIdxs] === 1,
      DocTranslate[nb, First[cellIdxs], Fallback -> ClaudeCode`GetPaletteFallback[]];
      NBAccess`NBSelectCell[nb, First[cellIdxs]],
      (* 複数セル: 非同期チェーンで逐次翻訳 *)
      iDocTranslateSelectedChain[nb, cellIdxs, 1, ClaudeCode`GetPaletteFallback[]]]
  ];

iDocTranslateSelectedChain[nb_, idxs_, pos_, fb_] :=
  If[pos > Length[idxs],
    Quiet[CurrentValue[nb, WindowStatusArea] =
      iL[ToString[Length[idxs]] <> " セルを翻訳しました。",
         ToString[Length[idxs]] <> " cells translated."]];
    RunScheduledTask[With[{pNb = nb},
      Quiet[CurrentValue[pNb, WindowStatusArea] = ""]], {3}],
    Quiet[CurrentValue[nb, WindowStatusArea] =
      iL["翻訳中: ", "Translating: "] <> ToString[pos] <> "/" <> ToString[Length[idxs]]];
    Module[{cellIdx = idxs[[pos]], mode},
      mode = NBAccess`NBCellGetTaggingRule[nb, cellIdx, $iDocTagMode];
      If[mode === "idea" || iDocIsMetaCell[nb, cellIdx],
        (* プロンプトモード / Note セルはスキップ *)
        iDocTranslateSelectedChain[nb, idxs, pos + 1, fb],
        DocTranslate[nb, cellIdx, Fallback -> fb];
        RunScheduledTask[
          With[{pNb = nb, is = idxs, p = pos, f = fb},
            iDocTranslateSelectedChain[pNb, is, p + 1, f]], {2}]]]
  ];

iDocSyncSelected[] :=
  Module[{nb, cellIdx},
    {nb, cellIdx} = iDocResolveTargetCell[];
    If[cellIdx === 0,
      MessageDialog[iL["セルを選択してください。", "Please select a cell."]];
      Return[$Failed]];
    DocSync[nb, cellIdx, Fallback -> ClaudeCode`GetPaletteFallback[]]
  ];

(* 選択セルから展開データを削除する *)
iDocDeleteExpandSelected[] :=
  Module[{nb, cellIdxs},
    {nb, cellIdxs} = iDocResolveTargetCells[];
    If[Length[cellIdxs] === 0,
      MessageDialog[iL["セルを選択してください。", "Please select a cell."]];
      Return[$Failed]];
    If[ChoiceDialog[
        iL["選択セルの展開データを削除しますか？\nこの操作は元に戻せません。",
           "Delete expand data from selected cell(s)?\nThis cannot be undone."],
        {iL["削除", "Delete"] -> True, iL["キャンセル", "Cancel"] -> False},
        WindowTitle -> iL["確認", "Confirm"]],
      Do[
        Module[{mode},
          mode = NBAccess`NBCellGetTaggingRule[nb, idx, $iDocTagMode];
          If[mode === "paragraph" || mode === "idea",
            (* パラグラフ表示中ならアイデアに戻す *)
            If[mode === "paragraph",
              Module[{ideaText},
                ideaText = NBAccess`NBCellGetTaggingRule[nb, idx, $iDocTagAlternate];
                If[StringQ[ideaText] && StringTrim[ideaText] =!= "",
                  NBAccess`NBInvalidateCellsCache[nb];
                  NBAccess`NBCellWriteText[nb, idx, ideaText]]]];
            (* タグをクリア *)
            NBAccess`NBCellSetTaggingRule[nb, idx, $iDocTagAlternate, None];
            NBAccess`NBCellSetTaggingRule[nb, idx, $iDocTagMode, None];
            (* 枠線をリセット *)
            NBAccess`NBCellSetOptions[nb, idx,
              CellFrame -> 0, CellFrameColor -> None]]],
      {idx, cellIdxs}]]
  ];

(* 選択セルから翻訳データを削除する *)
iDocDeleteTranslateSelected[] :=
  Module[{nb, cellIdxs},
    {nb, cellIdxs} = iDocResolveTargetCells[];
    If[Length[cellIdxs] === 0,
      MessageDialog[iL["セルを選択してください。", "Please select a cell."]];
      Return[$Failed]];
    If[ChoiceDialog[
        iL["選択セルの翻訳データを削除しますか？\nこの操作は元に戻せません。",
           "Delete translation data from selected cell(s)?\nThis cannot be undone."],
        {iL["削除", "Delete"] -> True, iL["キャンセル", "Cancel"] -> False},
        WindowTitle -> iL["確認", "Confirm"]],
      Do[
        Module[{showTrans, mode, srcText},
          showTrans = NBAccess`NBCellGetTaggingRule[nb, idx, $iDocTagShowTranslation];
          mode = NBAccess`NBCellGetTaggingRule[nb, idx, $iDocTagMode];
          (* 翻訳表示中なら元テキストに戻す *)
          If[TrueQ[showTrans],
            srcText = NBAccess`NBCellGetTaggingRule[nb, idx, $iDocTagTranslationSrc];
            If[StringQ[srcText] && StringTrim[srcText] =!= "",
              NBAccess`NBInvalidateCellsCache[nb];
              NBAccess`NBCellWriteText[nb, idx, srcText]]];
          (* 翻訳タグをクリア *)
          NBAccess`NBCellSetTaggingRule[nb, idx, $iDocTagTranslation, None];
          NBAccess`NBCellSetTaggingRule[nb, idx, $iDocTagTranslationSrc, None];
          NBAccess`NBCellSetTaggingRule[nb, idx, $iDocTagShowTranslation, None];
          (* mode が "translated" なら mode もクリア *)
          If[mode === "translated",
            NBAccess`NBCellSetTaggingRule[nb, idx, $iDocTagMode, None]];
          (* 枠線を展開状態に応じて再設定 *)
          Module[{curMode},
            curMode = NBAccess`NBCellGetTaggingRule[nb, idx, $iDocTagMode];
            Which[
              curMode === "paragraph",
                NBAccess`NBCellSetOptions[nb, idx,
                  Sequence @@ $iDocParagraphCellOpts],
              curMode === "idea",
                NBAccess`NBCellSetOptions[nb, idx,
                  Sequence @@ $iDocIdeaCellOpts],
              True,
                NBAccess`NBCellSetOptions[nb, idx,
                  CellFrame -> 0, CellFrameColor -> None]]]],
      {idx, cellIdxs}]]
  ];

(* ============================================================
   Export 除外トグル
   セルの export 除外フラグをトグルする。
   除外セルは右側に赤い点線枠を付けて視覚的に示す。
   ============================================================ *)

iDocToggleExportExclude[] :=
  Module[{nb, cellIdxs, idx, isExcluded, count = 0},
    {nb, cellIdxs} = iDocResolveTargetCells[];
    If[Length[cellIdxs] === 0,
      MessageDialog[iL["セルを選択してください。", "Please select a cell."]];
      Return[$Failed]];
    Do[
      NBAccess`NBInvalidateCellsCache[nb];
      isExcluded = TrueQ[
        NBAccess`NBCellGetTaggingRule[nb, idx, $iDocTagExcludeExport]];
      If[isExcluded,
        (* 除外解除: タグをクリアし、マーカーを消す *)
        NBAccess`NBCellSetTaggingRule[nb, idx, $iDocTagExcludeExport, None];
        NBAccess`NBCellSetOptions[nb, idx,
          CellFrameLabels -> Inherited],
        (* 除外設定: タグを付けて右側に赤マーカーを表示 *)
        NBAccess`NBCellSetTaggingRule[nb, idx, $iDocTagExcludeExport, True];
        NBAccess`NBCellSetOptions[nb, idx,
          CellFrameLabels -> {{None,
            Cell["\[Times]", FontColor -> RGBColor[0.7, 0.3, 0.3], FontSize -> 9]},
            {None, None}}]];
      count++,
    {idx, cellIdxs}];
    If[count > 0,
      Quiet[CurrentValue[nb, WindowStatusArea] =
        iL[ToString[count] <> " セルの除外設定を切替。",
           ToString[count] <> " cell(s) export toggle."]];
      RunScheduledTask[With[{pNb = nb},
        Quiet[CurrentValue[pNb, WindowStatusArea] = ""]], {3}]];
  ];

(* ============================================================
   セル分割・合併
   ============================================================ *)

(* 選択内容/Box表現をプレーンテキストに変換 *)
iDocExprToText[s_String] := s;
iDocExprToText[TextData[elems_List]] := StringJoin[iDocExprToText /@ elems];
iDocExprToText[TextData[s_]] := iDocExprToText[s];
iDocExprToText[Cell[content_, ___]] := iDocExprToText[content];
iDocExprToText[StyleBox[s_, ___]] := iDocExprToText[s];
iDocExprToText[ButtonBox[s_, ___]] := iDocExprToText[s];
iDocExprToText[BoxData[s_]] := iDocExprToText[s];
iDocExprToText[RowBox[elems_List]] := StringJoin[iDocExprToText /@ elems];
iDocExprToText[{}] := "";
iDocExprToText[list_List] := StringJoin[iDocExprToText /@ list];
iDocExprToText[_] := "";

(* テキストを比率で分割（文の区切りを優先的に探す） *)
iDocProportionalSplit[text_String, ratio_?NumberQ] :=
  Module[{len, pos, candidates, range, filtered, bestPos},
    len = StringLength[text];
    If[len === 0, Return[{"", ""}]];
    pos = Max[1, Min[len, Round[len * ratio]]];
    candidates = StringPosition[text,
      RegularExpression["[\:3002\:ff0e.!?\:ff01\:ff1f\\n]"]];
    If[Length[candidates] > 0,
      range = Max[10, Round[len * 0.1]];
      filtered = Select[candidates, Abs[#[[1]] - pos] <= range &];
      If[Length[filtered] > 0,
        bestPos = First[SortBy[filtered, Abs[#[[1]] - pos] &]][[1]];
        Return[{StringTake[text, bestPos], StringTrim[StringDrop[text, bestPos]]}]]];
    {StringTake[text, pos], StringTrim[StringDrop[text, pos]]}
  ];

(* カーソルがあるセルのインデックスを解決する *)
iDocResolveCursorCell[] :=
  Module[{nb, selCells, allCells, pos},
    nb = iDocUserNotebook[];
    If[Head[nb] =!= NotebookObject, Return[{$Failed, 0}]];
    NBAccess`NBInvalidateCellsCache[nb];
    selCells = Quiet[SelectedCells[nb]];
    If[!ListQ[selCells] || Length[selCells] === 0,
      Return[iDocResolveTargetCell[]]];
    allCells = Cells[nb];
    pos = Flatten[Position[allCells, First[selCells]]];
    If[Length[pos] > 0, {nb, First[pos]}, iDocResolveTargetCell[]]
  ];

(* プロンプト分割用LLMプロンプト *)
iDocSplitPromptFn[originalPrompt_String, frontPara_String, backPara_String] :=
  "A paragraph was generated from the 'Original prompt' below, " <>
  "then split into two halves.\n" <>
  "Generate two brief idea/prompt phrases — one for each half.\n" <>
  "Rules:\n" <>
  "- Respect the style and intent of the original prompt\n" <>
  "- Each prompt should capture what its half discusses\n" <>
  "- CRITICAL: Output ONLY in this exact format, nothing else:\n" <>
  "[FRONT]\n<prompt for front half>\n[BACK]\n<prompt for back half>\n\n" <>
  "Original prompt:\n" <> originalPrompt <>
  "\n\nFront half:\n" <> frontPara <>
  "\n\nBack half:\n" <> backPara;

(* セルの視覚スタイルをモードに応じて設定する *)
iDocApplyModeStyle[nb_, cellIdx_, mode_, showTrans_] :=
  Which[
    TrueQ[showTrans],
      NBAccess`NBCellSetOptions[nb, cellIdx,
        Sequence @@ $iDocTranslationCellOpts],
    mode === "paragraph",
      NBAccess`NBCellSetOptions[nb, cellIdx,
        Sequence @@ $iDocParagraphCellOpts],
    mode === "idea",
      NBAccess`NBCellSetOptions[nb, cellIdx,
        Sequence @@ $iDocIdeaCellOpts],
    mode === "translated",
      NBAccess`NBCellSetOptions[nb, cellIdx,
        Sequence @@ $iDocTranslatedCellOpts],
    mode === "compute",
      NBAccess`NBCellSetOptions[nb, cellIdx,
        Sequence @@ $iDocComputeCellOpts];
      NBAccess`NBCellSetStyle[nb, cellIdx, "Input"],
    mode === "computePrompt",
      NBAccess`NBCellSetOptions[nb, cellIdx,
        Sequence @@ $iDocIdeaCellOpts];
      NBAccess`NBCellSetStyle[nb, cellIdx, "Text"],
    True, Null];
iDocSplitCell[] :=
  Module[{nb, cellIdx},
    {nb, cellIdx} = iDocResolveCursorCell[];
    If[cellIdx === 0,
      MessageDialog[iL["セル内にカーソルを置いてください。",
        "Place cursor inside a cell."]];
      Return[$Failed]];
    DocSplitCell[nb, cellIdx]
  ];

DocSplitCell[nb_NotebookObject, cellIdx_Integer] :=
  Module[{mode, showTrans, style, fullText, backText, frontText,
          splitRatio, allCells, alternate, translation, translationSrc,
          frontAlt, backAlt, frontTrans, backTrans, frontTransSrc, backTransSrc,
          newCellIdx, privLevel, useFallback,
          marker, markedText, markerPos},

    If[iDocIsMetaCell[nb, cellIdx], Return[$Failed]];
    NBAccess`NBInvalidateCellsCache[nb];

    mode = NBAccess`NBCellGetTaggingRule[nb, cellIdx, $iDocTagMode];
    showTrans = NBAccess`NBCellGetTaggingRule[nb, cellIdx, $iDocTagShowTranslation];
    style = NBAccess`NBCellStyle[nb, cellIdx];
    fullText = NBAccess`NBCellGetText[nb, cellIdx];

    If[!StringQ[fullText] || StringLength[fullText] < 2,
      MessageDialog[iL["テキストが短すぎます。", "Text too short to split."]];
      Return[$Failed]];

    (* カーソル位置の検出: マーカー挿入 → テキスト読取 → 位置特定 → Undo *)
    marker = "<<DOCSPLIT-" <> ToString[RandomInteger[{100000, 999999}]] <> ">>";
    NotebookWrite[nb, marker];
    NBAccess`NBInvalidateCellsCache[nb];
    markedText = NBAccess`NBCellGetText[nb, cellIdx];
    FrontEndTokenExecute[nb, "Undo"];
    NBAccess`NBInvalidateCellsCache[nb];

    markerPos = StringPosition[markedText, marker];
    If[Length[markerPos] === 0,
      MessageDialog[iL["カーソルをセル内の分割位置に置いてください。",
        "Place cursor at the split position."]];
      Return[$Failed]];

    frontText = StringTake[markedText, markerPos[[1, 1]] - 1];
    backText = StringDrop[markedText, markerPos[[1, 2]]];

    If[StringLength[frontText] === 0 || StringLength[backText] === 0,
      MessageDialog[iL["セルの先頭・末尾ではなく途中にカーソルを置いてください。",
        "Place cursor in the middle of the cell, not at the start or end."]];
      Return[$Failed]];

    splitRatio = N[StringLength[frontText] / StringLength[fullText]];

    (* 保存データ取得 *)
    alternate = NBAccess`NBCellGetTaggingRule[nb, cellIdx, $iDocTagAlternate];
    translation = NBAccess`NBCellGetTaggingRule[nb, cellIdx, $iDocTagTranslation];
    translationSrc = NBAccess`NBCellGetTaggingRule[nb, cellIdx,
      $iDocTagTranslationSrc];
    privLevel = NBAccess`NBCellPrivacyLevel[nb, cellIdx];
    useFallback = ClaudeCode`GetPaletteFallback[];

    (* 保存データを比率で分割 *)
    {frontAlt, backAlt} = If[StringQ[alternate] && StringLength[alternate] > 0,
      iDocProportionalSplit[alternate, splitRatio], {"", ""}];
    {frontTrans, backTrans} = If[StringQ[translation] &&
        StringLength[translation] > 0,
      iDocProportionalSplit[translation, splitRatio], {"", ""}];
    {frontTransSrc, backTransSrc} = If[StringQ[translationSrc] &&
        StringLength[translationSrc] > 0,
      iDocProportionalSplit[translationSrc, splitRatio], {"", ""}];

    (* --- 前半セル (現在のセル) を更新 --- *)
    NBAccess`NBInvalidateCellsCache[nb];
    NBAccess`NBCellWriteText[nb, cellIdx, frontText];
    If[frontTrans =!= "",
      NBAccess`NBCellSetTaggingRule[nb, cellIdx,
        $iDocTagTranslation, frontTrans]];
    If[frontTransSrc =!= "",
      NBAccess`NBCellSetTaggingRule[nb, cellIdx,
        $iDocTagTranslationSrc, frontTransSrc]];

    (* --- 後半セルを挿入 --- *)
    NBAccess`NBInvalidateCellsCache[nb];
    allCells = Cells[nb];
    SelectionMove[allCells[[cellIdx]], After, Cell];
    NotebookWrite[nb, Cell[backText,
      If[MemberQ[{"Text", "Section", "Subsection", "Subsubsection",
                   "Title", "Subtitle", "Chapter"}, style], style, "Text"]]];
    NBAccess`NBInvalidateCellsCache[nb];
    newCellIdx = cellIdx + 1;

    (* 後半セルにモードとスタイルを設定 *)
    If[StringQ[mode],
      NBAccess`NBCellSetTaggingRule[nb, newCellIdx, $iDocTagMode, mode];
      iDocApplyModeStyle[nb, newCellIdx, mode, showTrans];
      If[backTrans =!= "",
        NBAccess`NBCellSetTaggingRule[nb, newCellIdx,
          $iDocTagTranslation, backTrans]];
      If[backTransSrc =!= "",
        NBAccess`NBCellSetTaggingRule[nb, newCellIdx,
          $iDocTagTranslationSrc, backTransSrc]];
      If[TrueQ[showTrans],
        NBAccess`NBCellSetTaggingRule[nb, newCellIdx,
          $iDocTagShowTranslation, True]]];

    (* --- プロンプト処理 --- *)
    (* まず比率分割のプロンプトを即座に設定（LLM完了前のトグル安全性確保） *)
    If[frontAlt =!= "",
      NBAccess`NBCellSetTaggingRule[nb, cellIdx,
        $iDocTagAlternate, frontAlt]];
    If[backAlt =!= "",
      NBAccess`NBCellSetTaggingRule[nb, newCellIdx,
        $iDocTagAlternate, backAlt]];

    Which[
      (* パラグラフ or 翻訳表示中 + プロンプトあり → LLMで分割（非同期で上書き） *)
      (mode === "paragraph" || TrueQ[showTrans]) &&
          StringQ[alternate] && StringLength[alternate] > 0,
        Module[{displayedFront = frontText, displayedBack = backText,
                prompt},
          (* 翻訳表示中なら翻訳元パラグラフを使う *)
          If[TrueQ[showTrans] && StringQ[translationSrc],
            displayedFront = frontTransSrc;
            displayedBack = backTransSrc];
          prompt = iDocSplitPromptFn[alternate, displayedFront, displayedBack];
          iDocSetJobAnchorCell[nb, cellIdx];
          With[{nb2 = nb, ci1 = cellIdx, ci2 = newCellIdx,
                fAlt = frontAlt, bAlt = backAlt},
            NBAccess`$NBLLMQueryFunc[prompt,
              Function[response,
                Module[{parts, fp, bp, curMode1, curMode2},
                  NBAccess`NBInvalidateCellsCache[nb2];
                  If[StringQ[response] && StringContainsQ[response, "[FRONT]"] &&
                     StringContainsQ[response, "[BACK]"],
                    parts = StringSplit[response, {"[FRONT]", "[BACK]"}];
                    parts = StringTrim /@ Select[parts, StringLength[#] > 0 &];
                    If[Length[parts] >= 2,
                      fp = parts[[1]]; bp = parts[[2]],
                      fp = fAlt; bp = bAlt],
                    fp = fAlt; bp = bAlt];
                  (* モードに応じて適切な場所に保存 *)
                  curMode1 = NBAccess`NBCellGetTaggingRule[nb2, ci1, $iDocTagMode];
                  If[curMode1 === "paragraph" || curMode1 === "translated",
                    (* パラグラフ表示中: alternate がプロンプト格納場所 *)
                    NBAccess`NBCellSetTaggingRule[nb2, ci1,
                      $iDocTagAlternate, fp],
                    If[curMode1 === "idea",
                      (* プロンプト表示中: テキストがプロンプト、alternate がパラグラフ *)
                      NBAccess`NBInvalidateCellsCache[nb2];
                      NBAccess`NBCellWriteText[nb2, ci1, fp]]];
                  curMode2 = NBAccess`NBCellGetTaggingRule[nb2, ci2, $iDocTagMode];
                  If[curMode2 === "paragraph" || curMode2 === "translated",
                    NBAccess`NBCellSetTaggingRule[nb2, ci2,
                      $iDocTagAlternate, bp],
                    If[curMode2 === "idea",
                      NBAccess`NBInvalidateCellsCache[nb2];
                      NBAccess`NBCellWriteText[nb2, ci2, bp]]];
                  Quiet[CurrentValue[nb2, WindowStatusArea] =
                    iL["プロンプト分割完了", "Prompt split done"]];
                  RunScheduledTask[With[{pNb = nb2},
                    Quiet[CurrentValue[pNb, WindowStatusArea] = ""]], {3}]]],
              nb, PrivacyLevel -> privLevel, Fallback -> useFallback]]],

      True, Null];

    Quiet[CurrentValue[nb, WindowStatusArea] =
      iL["セルを分割しました。", "Cell split."]];
    RunScheduledTask[With[{pNb = nb},
      Quiet[CurrentValue[pNb, WindowStatusArea] = ""]], {3}];
  ];

(* --- セル合併 --- *)
iDocMergeCells[] :=
  Module[{nb, cellIdxs},
    {nb, cellIdxs} = iDocResolveTargetCells[];
    If[Length[cellIdxs] < 2,
      MessageDialog[iL["2つ以上のセルを選択してください。",
        "Select 2 or more cells."]];
      Return[$Failed]];
    DocMergeCells[nb, cellIdxs]
  ];

DocMergeCells[nb_NotebookObject, cellIdxs_List] :=
  Module[{first, mode1, showTrans1, style1,
          ideas = {}, paragraphs = {}, transs = {}, transSrcs = {},
          mergedIdea, mergedPara, mergedTrans, mergedTransSrc,
          deletedCount = 0, hasIdea, hasPara, hasTrans,
          curMode, curText, curAlt, curTrans, curTransSrc, curShowTrans,
          finalMode},
    If[Length[cellIdxs] < 2, Return[$Failed]];
    first = First[cellIdxs];
    NBAccess`NBInvalidateCellsCache[nb];

    mode1 = NBAccess`NBCellGetTaggingRule[nb, first, $iDocTagMode];
    showTrans1 = NBAccess`NBCellGetTaggingRule[nb, first, $iDocTagShowTranslation];
    style1 = NBAccess`NBCellStyle[nb, first];

    (* 全セルから各レイヤーのデータを復元して収集 *)
    Do[
      curMode = NBAccess`NBCellGetTaggingRule[nb, idx, $iDocTagMode];
      curShowTrans = NBAccess`NBCellGetTaggingRule[nb, idx, $iDocTagShowTranslation];
      curText = NBAccess`NBCellGetText[nb, idx];
      curAlt = NBAccess`NBCellGetTaggingRule[nb, idx, $iDocTagAlternate];
      curTrans = NBAccess`NBCellGetTaggingRule[nb, idx, $iDocTagTranslation];
      curTransSrc = NBAccess`NBCellGetTaggingRule[nb, idx, $iDocTagTranslationSrc];

      (* 表示モードに応じてプロンプト/パラグラフを正しく振り分ける *)
      Which[
        (* 翻訳表示中: 表示=翻訳, translationSrc=パラグラフ, alternate=プロンプト *)
        TrueQ[curShowTrans] && curMode === "paragraph",
          AppendTo[ideas, curAlt];
          AppendTo[paragraphs, curTransSrc];
          AppendTo[transs, curText];
          AppendTo[transSrcs, curTransSrc],
        (* 翻訳表示中 (translated モード): 表示=翻訳, translationSrc=元テキスト *)
        TrueQ[curShowTrans],
          AppendTo[ideas, None];
          AppendTo[paragraphs, curTransSrc];
          AppendTo[transs, curText];
          AppendTo[transSrcs, curTransSrc],
        (* アイデア表示中: 表示=プロンプト, alternate=パラグラフ *)
        curMode === "idea",
          AppendTo[ideas, curText];
          AppendTo[paragraphs, curAlt];
          AppendTo[transs, curTrans];
          AppendTo[transSrcs, curTransSrc],
        (* パラグラフ表示中: 表示=パラグラフ, alternate=プロンプト *)
        curMode === "paragraph",
          AppendTo[ideas, curAlt];
          AppendTo[paragraphs, curText];
          AppendTo[transs, curTrans];
          AppendTo[transSrcs, curTransSrc],
        (* translated モード(元テキスト表示中): 表示=元テキスト *)
        curMode === "translated",
          AppendTo[ideas, None];
          AppendTo[paragraphs, curText];
          AppendTo[transs, curTrans];
          AppendTo[transSrcs, curTransSrc],
        (* 普通のセル: プロンプトもパラグラフもない *)
        True,
          AppendTo[ideas, None];
          AppendTo[paragraphs, curText];
          AppendTo[transs, curTrans];
          AppendTo[transSrcs, curTransSrc]
      ],
    {idx, cellIdxs}];

    (* 各レイヤーを結合（有効な文字列のみ） *)
    mergedIdea = StringRiffle[
      Select[ideas, StringQ[#] && StringTrim[#] =!= "" &], " "];
    mergedPara = StringRiffle[
      Select[paragraphs, StringQ[#] && StringTrim[#] =!= "" &], " "];
    mergedTrans = StringRiffle[
      Select[transs, StringQ[#] && StringTrim[#] =!= "" &], " "];
    mergedTransSrc = StringRiffle[
      Select[transSrcs, StringQ[#] && StringTrim[#] =!= "" &], " "];

    hasIdea = StringLength[mergedIdea] > 0;
    hasPara = StringLength[mergedPara] > 0;
    hasTrans = StringLength[mergedTrans] > 0;

    (* 後ろのセルから削除（インデックスがずれないように） *)
    Do[
      NBAccess`NBInvalidateCellsCache[nb];
      Module[{cells = Cells[nb]},
        If[idx <= Length[cells],
          NotebookDelete[cells[[idx]]];
          deletedCount++]],
    {idx, Reverse[Rest[cellIdxs]]}];

    (* 最初のセルの表示モードを決定 *)
    finalMode = Which[
      (* 元々のモードを尊重 *)
      mode1 === "idea" && hasIdea, "idea",
      mode1 === "paragraph" && hasPara, "paragraph",
      mode1 === "translated", "translated",
      (* パラグラフがあればパラグラフモード *)
      hasPara && hasIdea, "paragraph",
      hasPara, "paragraph",
      hasIdea, "idea",
      True, None];

    (* 最初のセルに結合結果を書き込み *)
    NBAccess`NBInvalidateCellsCache[nb];

    Which[
      (* 翻訳表示中だった場合: 翻訳を表示、パラグラフを translationSrc に *)
      TrueQ[showTrans1] && hasTrans,
        NBAccess`NBCellWriteText[nb, first, mergedTrans];
        If[hasIdea,
          NBAccess`NBCellSetTaggingRule[nb, first, $iDocTagAlternate, mergedIdea]];
        NBAccess`NBCellSetTaggingRule[nb, first, $iDocTagTranslation, mergedTrans];
        If[StringLength[mergedTransSrc] > 0,
          NBAccess`NBCellSetTaggingRule[nb, first, $iDocTagTranslationSrc, mergedTransSrc],
          If[hasPara, NBAccess`NBCellSetTaggingRule[nb, first, $iDocTagTranslationSrc, mergedPara]]];
        NBAccess`NBCellSetTaggingRule[nb, first, $iDocTagShowTranslation, True];
        If[StringQ[finalMode],
          NBAccess`NBCellSetTaggingRule[nb, first, $iDocTagMode, finalMode]],

      (* アイデアモード: プロンプトを表示、パラグラフを alternate に *)
      finalMode === "idea",
        NBAccess`NBCellWriteText[nb, first, mergedIdea];
        If[hasPara,
          NBAccess`NBCellSetTaggingRule[nb, first, $iDocTagAlternate, mergedPara]];
        NBAccess`NBCellSetTaggingRule[nb, first, $iDocTagMode, "idea"];
        If[hasTrans,
          NBAccess`NBCellSetTaggingRule[nb, first, $iDocTagTranslation, mergedTrans]];
        If[StringLength[mergedTransSrc] > 0,
          NBAccess`NBCellSetTaggingRule[nb, first, $iDocTagTranslationSrc, mergedTransSrc]];
        NBAccess`NBCellSetTaggingRule[nb, first, $iDocTagShowTranslation, False],

      (* パラグラフモード: パラグラフを表示、プロンプトを alternate に *)
      finalMode === "paragraph",
        NBAccess`NBCellWriteText[nb, first, mergedPara];
        If[hasIdea,
          NBAccess`NBCellSetTaggingRule[nb, first, $iDocTagAlternate, mergedIdea]];
        NBAccess`NBCellSetTaggingRule[nb, first, $iDocTagMode, "paragraph"];
        If[hasTrans,
          NBAccess`NBCellSetTaggingRule[nb, first, $iDocTagTranslation, mergedTrans]];
        If[StringLength[mergedTransSrc] > 0,
          NBAccess`NBCellSetTaggingRule[nb, first, $iDocTagTranslationSrc, mergedTransSrc]];
        NBAccess`NBCellSetTaggingRule[nb, first, $iDocTagShowTranslation, False],

      (* 普通のセル *)
      True,
        NBAccess`NBCellWriteText[nb, first, mergedPara];
        If[hasTrans,
          NBAccess`NBCellSetTaggingRule[nb, first, $iDocTagMode, "translated"];
          NBAccess`NBCellSetTaggingRule[nb, first, $iDocTagTranslation, mergedTrans];
          NBAccess`NBCellSetTaggingRule[nb, first, $iDocTagTranslationSrc, mergedPara]]
    ];

    (* 視覚スタイル更新 *)
    iDocApplyModeStyle[nb, first,
      NBAccess`NBCellGetTaggingRule[nb, first, $iDocTagMode],
      NBAccess`NBCellGetTaggingRule[nb, first, $iDocTagShowTranslation]];

    Quiet[CurrentValue[nb, WindowStatusArea] =
      iL[ToString[deletedCount + 1] <> " セルを合併しました。",
         ToString[deletedCount + 1] <> " cells merged."]];
    RunScheduledTask[With[{pNb = nb},
      Quiet[CurrentValue[pNb, WindowStatusArea] = ""]], {3}];
  ];

(* ============================================================
   Note セル挿入
   ============================================================ *)

(* Note スタイルのセル定義: 薄い黄色背景、小さめフォント、インデント付き *)
$iDocNoteCellOpts = {
  CellFrame -> {{2, 0}, {0, 0}},
  CellFrameColor -> RGBColor[0.85, 0.78, 0.5],
  Background -> RGBColor[1, 0.98, 0.9],
  FontSize -> 11,
  FontColor -> GrayLevel[0.35],
  CellMargins -> {{66, 20}, {4, 4}},
  CellDingbat -> StyleBox["\[FilledSmallSquare]", FontColor -> RGBColor[0.85, 0.78, 0.5]]
};

(* Dictionary スタイルのセル定義: 薄い青緑背景、用語辞書用 *)
$iDocDictionaryCellOpts = {
  CellFrame -> {{2, 0}, {0, 0}},
  CellFrameColor -> RGBColor[0.35, 0.65, 0.65],
  Background -> RGBColor[0.92, 0.97, 0.97],
  FontSize -> 11,
  FontColor -> GrayLevel[0.3],
  CellMargins -> {{66, 20}, {4, 4}},
  CellDingbat -> StyleBox["\[FilledSmallSquare]", FontColor -> RGBColor[0.35, 0.65, 0.65]]
};

(* Directive スタイルのセル定義: 薄い赤紫背景、LLM指示用 *)
$iDocDirectiveCellOpts = {
  CellFrame -> {{2, 0}, {0, 0}},
  CellFrameColor -> RGBColor[0.65, 0.35, 0.5],
  Background -> RGBColor[0.97, 0.92, 0.95],
  FontSize -> 11,
  FontColor -> GrayLevel[0.3],
  CellMargins -> {{66, 20}, {4, 4}},
  CellDingbat -> StyleBox["\[FilledSmallSquare]", FontColor -> RGBColor[0.65, 0.35, 0.5]]
};

(* Bibliography スタイルのセル定義: 薄い灰青背景、参考文献管理用 *)
$iDocBibliographyCellOpts = {
  CellFrame -> {{2, 0}, {0, 0}},
  CellFrameColor -> RGBColor[0.4, 0.45, 0.6],
  Background -> RGBColor[0.93, 0.94, 0.97],
  FontSize -> 11,
  FontColor -> GrayLevel[0.3],
  CellMargins -> {{66, 20}, {4, 4}},
  CellDingbat -> StyleBox["\[FilledSmallSquare]", FontColor -> RGBColor[0.4, 0.45, 0.6]]
};

DocInsertNote[nb_NotebookObject] :=
  Module[{noteCell, hasNoteStyle},
    (* ノートブックにスタイル "Note" が定義されているか確認 *)
    hasNoteStyle = Quiet[
      MemberQ[
        Cases[
          Quiet[Options[nb, StyleDefinitions]],
          Cell[StyleData["Note"], ___], Infinity],
        _Cell]];
    If[TrueQ[hasNoteStyle],
      (* 既存の Note スタイルを使用 *)
      NotebookWrite[nb,
        Cell[iL["ここへはメモなどを書く...", "Write notes here..."], "Note"]],
      (* Note スタイル未定義: セルスタイルを "Note" にしつつ
         セルレベルオプションで見た目を設定 *)
      noteCell = Cell[
        iL["ここへはメモなどを書く...", "Write notes here..."],
        "Note",
        Sequence @@ $iDocNoteCellOpts
      ];
      NotebookWrite[nb, noteCell]
    ];
  ];

(* ============================================================
   Dictionary セル挿入
   ============================================================ *)

DocInsertDictionary[nb_NotebookObject] :=
  Module[{dictCell, hasDictStyle, defaultContent},
    defaultContent = "{{<<Japanese>>, <<English>>, <<Context>>}, " <>
      "{\"状相\", \"configuration\", \"セルオートマトン\"}, " <>
      "{\"universality\", \"万能性\", \"計算モデル\"}}";
    hasDictStyle = Quiet[
      MemberQ[
        Cases[
          Quiet[Options[nb, StyleDefinitions]],
          Cell[StyleData["Dictionary"], ___], Infinity],
        _Cell]];
    If[TrueQ[hasDictStyle],
      NotebookWrite[nb, Cell[defaultContent, "Dictionary"]],
      dictCell = Cell[
        defaultContent,
        "Dictionary",
        Sequence @@ $iDocDictionaryCellOpts
      ];
      NotebookWrite[nb, dictCell]
    ];
  ];

(* ============================================================
   Directive セル挿入
   ============================================================ *)

DocInsertDirective[nb_NotebookObject] :=
  Module[{dirCell, hasDirStyle},
    hasDirStyle = Quiet[
      MemberQ[
        Cases[
          Quiet[Options[nb, StyleDefinitions]],
          Cell[StyleData["Directive"], ___], Infinity],
        _Cell]];
    If[TrueQ[hasDirStyle],
      NotebookWrite[nb,
        Cell[iL["ここに LLM への指示を記載...", "Write LLM directives here..."],
          "Directive"]],
      dirCell = Cell[
        iL["ここに LLM への指示を記載...", "Write LLM directives here..."],
        "Directive",
        Sequence @@ $iDocDirectiveCellOpts
      ];
      NotebookWrite[nb, dirCell]
    ];
  ];

(* ============================================================
   Bibliography セル挿入
   ============================================================ *)

DocInsertBibliography[nb_NotebookObject] :=
  Module[{bibCell, hasBibStyle, defaultContent},
    defaultContent = "{{<<Key>>, <<Author>>, <<Year>>, <<Title>>}, " <>
      "{\"morita1996\", \"K. Morita\", \"1996\", \"Universality of a reversible two-counter machine\"}}";
    hasBibStyle = Quiet[
      MemberQ[
        Cases[
          Quiet[Options[nb, StyleDefinitions]],
          Cell[StyleData["Bibliography"], ___], Infinity],
        _Cell]];
    If[TrueQ[hasBibStyle],
      NotebookWrite[nb, Cell[defaultContent, "Bibliography"]],
      bibCell = Cell[
        defaultContent,
        "Bibliography",
        Sequence @@ $iDocBibliographyCellOpts
      ];
      NotebookWrite[nb, bibCell]
    ];
  ];

(* ============================================================
   図メタデータ編集
   ============================================================ *)

DocEditFigureMeta[nb_NotebookObject, cellIdx_Integer] :=
  Module[{cellExpr, label, caption},
    cellExpr = NBAccess`NBCellRead[nb, cellIdx];
    If[!NBAccess`NBCellHasImage[cellExpr],
      MessageDialog[iL["このセルには画像がありません。",
        "This cell does not contain an image."]];
      Return[$Failed]];
    label = NBAccess`NBCellGetTaggingRule[nb, cellIdx, $iDocTagFigLabel];
    caption = NBAccess`NBCellGetTaggingRule[nb, cellIdx, $iDocTagFigCaption];
    If[!StringQ[label], label = ""];
    If[!StringQ[caption], caption = ""];
    Module[{dlgLabel = label, dlgCaption = caption},
      DialogInput[
        Column[{
          Style[iL["図メタデータ", "Figure Metadata"], Bold, 12],
          Spacer[5],
          Row[{Style[iL["ラベル: ", "Label: "], Bold, 10],
            InputField[Dynamic[dlgLabel], String, FieldSize -> 25]}],
          Style[iL["例: ca-rule110", "e.g. ca-rule110"], 8, GrayLevel[0.5]],
          Spacer[3],
          Row[{Style[iL["キャプション: ", "Caption: "], Bold, 10],
            InputField[Dynamic[dlgCaption], String, FieldSize -> 25]}],
          Spacer[5],
          Row[{
            DefaultButton[
              (NBAccess`NBCellSetTaggingRule[nb, cellIdx,
                $iDocTagFigLabel, dlgLabel];
               NBAccess`NBCellSetTaggingRule[nb, cellIdx,
                $iDocTagFigCaption, dlgCaption];
               DialogReturn[])],
            Button[iL["参照コピー", "Copy Ref"],
              (CopyToClipboard["<<fig:" <> dlgLabel <> ">>"];
               NBAccess`NBCellSetTaggingRule[nb, cellIdx,
                $iDocTagFigLabel, dlgLabel];
               NBAccess`NBCellSetTaggingRule[nb, cellIdx,
                $iDocTagFigCaption, dlgCaption];
               DialogReturn[])],
            CancelButton[DialogReturn[]]
          }, Spacer[10]]
        }, Alignment -> Left],
        WindowTitle -> iL["図メタデータ", "Figure Metadata"]]]
  ];

iDocEditFigureMetaAction[] :=
  Module[{nb, cellIdx},
    {nb, cellIdx} = iDocResolveTargetCell[];
    If[cellIdx === 0,
      MessageDialog[iL["セルを選択してください。", "Please select a cell."]];
      Return[$Failed]];
    DocEditFigureMeta[nb, cellIdx]
  ];

iDocInsertBibliographyAction[] :=
  Module[{nb = iDocUserNotebook[]},
    If[Head[nb] =!= NotebookObject,
      MessageDialog[iL["ノートブックが見つかりません。", "No notebook found."]];
      Return[$Failed]];
    DocInsertBibliography[nb]
  ];

(* ============================================================
   参照挿入ダイアログ
   ノートブック内の図・文献を一覧表示し、クリックでカーソル位置に挿入。
   ============================================================ *)

iDocInsertReferenceAction[] :=
  Module[{nb, figTable, bibTable, figItems, bibItems, allItems},
    nb = iDocUserNotebook[];
    If[Head[nb] =!= NotebookObject,
      MessageDialog[iL["ノートブックが見つかりません。", "No notebook found."]];
      Return[$Failed]];
    NBAccess`NBInvalidateCellsCache[nb];
    figTable = iDocBuildFigureTable[nb];
    bibTable = iDocCollectBibliography[nb];

    If[Length[figTable] === 0 && Length[bibTable] === 0,
      MessageDialog[iL[
        "図メタデータや参考文献がありません。\n" <>
        "「図メタ」で図にラベルを設定するか、「文献」で参考文献セルを追加してください。",
        "No figure metadata or bibliography found.\n" <>
        "Use 'Fig Meta' to label figures or 'Bib' to add a bibliography cell."]];
      Return[$Failed]];

    (* 図の一覧: ボタン化 *)
    figItems = KeyValueMap[
      Function[{label, entry},
        Button[
          Tooltip[
            Row[{
              Style["Fig " <> ToString[entry["Number"]], Bold, 10],
              Style[" " <> If[entry["Caption"] =!= "", entry["Caption"],
                label], 9, GrayLevel[0.4]]
            }],
            "<<fig:" <> label <> ">>"],
          (NotebookWrite[nb, "<<fig:" <> label <> ">>"];
           DialogReturn[]),
          Appearance -> "Frameless",
          ImageSize -> {260, Automatic}]],
      figTable];

    (* 文献の一覧: ボタン化 *)
    bibItems = KeyValueMap[
      Function[{key, entry},
        Button[
          Tooltip[
            Row[{
              Style[key, Bold, 10],
              Style[" " <> entry["Author"] <> " " <> entry["Year"],
                9, GrayLevel[0.4]]
            }],
            "<<cite:" <> key <> ">>"],
          (NotebookWrite[nb, "<<cite:" <> key <> ">>"];
           DialogReturn[]),
          Appearance -> "Frameless",
          ImageSize -> {260, Automatic}]],
      bibTable];

    DialogInput[
      Column[Flatten[{
        Style[iL["参照を挿入", "Insert Reference"], Bold, 12],
        Spacer[3],
        If[Length[figItems] > 0,
          {Style[iL[" 図", " Figures"], Bold, 9, GrayLevel[0.3]],
           Sequence @@ figItems, Spacer[3]},
          {}],
        If[Length[bibItems] > 0,
          {Style[iL[" 文献", " Citations"], Bold, 9, GrayLevel[0.3]],
           Sequence @@ bibItems},
          {}],
        Spacer[5],
        CancelButton[DialogReturn[]]
      }], Alignment -> Left],
      WindowTitle -> iL["参照挿入", "Insert Reference"],
      WindowSize -> {280, Automatic}]
  ];

(* セルが Note スタイルかどうかを判定する *)
iDocIsNoteCell[nb_NotebookObject, cellIdx_Integer] :=
  NBAccess`NBCellStyle[nb, cellIdx] === "Note";

(* セルが Dictionary スタイルかどうかを判定する *)
iDocIsDictionaryCell[nb_NotebookObject, cellIdx_Integer] :=
  NBAccess`NBCellStyle[nb, cellIdx] === "Dictionary";

(* セルが Directive スタイルかどうかを判定する *)
iDocIsDirectiveCell[nb_NotebookObject, cellIdx_Integer] :=
  NBAccess`NBCellStyle[nb, cellIdx] === "Directive";

(* セルが Note/Dictionary/Directive/Bibliography のいずれか（メタセル）かどうかを判定する *)
iDocIsMetaCell[nb_NotebookObject, cellIdx_Integer] :=
  MemberQ[{"Note", "Dictionary", "Directive", "Bibliography"},
    NBAccess`NBCellStyle[nb, cellIdx]];

(* ============================================================
   エクスポート: 図テーブル・参考文献・参照解決
   ============================================================ *)

(* ノートブック内の画像セルを走査して図テーブルを構築する。
   戻り値: <|"label" -> <|"Number" -> n, "Caption" -> "...", "CellIdx" -> i|>, ...|> *)
iDocBuildFigureTable[nb_NotebookObject] :=
  Module[{nCells, table = <||>, figNum = 0, cellExpr, label, caption},
    nCells = NBAccess`NBCellCount[nb];
    Do[
      If[!iDocIsMetaCell[nb, i] &&
         !TrueQ[NBAccess`NBCellGetTaggingRule[nb, i, $iDocTagExcludeExport]],
        cellExpr = NBAccess`NBCellRead[nb, i];
        If[NBAccess`NBCellHasImage[cellExpr],
          figNum++;
          label = NBAccess`NBCellGetTaggingRule[nb, i, $iDocTagFigLabel];
          caption = NBAccess`NBCellGetTaggingRule[nb, i, $iDocTagFigCaption];
          If[!StringQ[label] || StringTrim[label] === "",
            label = "fig" <> ToString[figNum]];
          If[!StringQ[caption], caption = ""];
          table[label] = <|"Number" -> figNum, "Caption" -> caption,
            "CellIdx" -> i|>]],
    {i, nCells}];
    table
  ];

(* ノートブック内の Bibliography セルから参考文献を収集する。
   戻り値: <|"key" -> <|"Author" -> "...", "Year" -> "...", "Title" -> "..."|>, ...|> *)
iDocCollectBibliography[nb_NotebookObject] :=
  Module[{nCells, text, bib = <||>, parsed, cleanText},
    nCells = NBAccess`NBCellCount[nb];
    Do[
      If[NBAccess`NBCellStyle[nb, i] === "Bibliography",
        text = Quiet[NBAccess`NBCellGetText[nb, i]];
        If[StringQ[text] && StringLength[text] > 0,
          (* <<Key>> 等のプレースホルダーを含むヘッダー行を除去してからパース。
             <<...>> は Mathematica の Get 演算子として解釈されるため
             ToExpression が失敗する。 *)
          cleanText = StringReplace[text,
            RegularExpression["\\{<<[^>]*>>(,\\s*<<[^>]*>>)*\\},?\\s*"] -> ""];
          (* 外側の {} が消えている可能性があるので補完 *)
          If[!StringStartsQ[StringTrim[cleanText], "{"],
            cleanText = "{" <> cleanText <> "}"];
          parsed = Quiet[ToExpression[cleanText]];
          If[ListQ[parsed],
            Do[
              If[ListQ[entry] && Length[entry] >= 4,
                bib[entry[[1]]] = <|"Author" -> entry[[2]],
                  "Year" -> entry[[3]], "Title" -> entry[[4]]|>],
            {entry, parsed}]]]],
    {i, nCells}];
    bib
  ];

(* テキスト内の <<fig:label>> と <<cite:key>> を解決する *)
iDocResolveReferences[text_String, figTable_Association, bibTable_Association,
    format_String] :=
  Module[{result = text},
    (* <<fig:label>> → 図参照 *)
    result = StringReplace[result,
      RegularExpression["<<fig:([^>]+)>>"] :>
        iDocResolveFigRef["$1", figTable, format]];
    (* <<cite:key>> → 引用 *)
    result = StringReplace[result,
      RegularExpression["<<cite:([^>]+)>>"] :>
        iDocResolveCiteRef["$1", bibTable, format]];
    result
  ];

iDocResolveFigRef[lbl_String, figTable_Association, format_String] :=
  Module[{entry = Lookup[figTable, lbl, None]},
    If[AssociationQ[entry],
      If[format === "markdown",
        "[Figure " <> ToString[entry["Number"]] <> "](#fig-" <> lbl <> ")",
        "\\figurename~\\ref{fig:" <> lbl <> "}"],
      If[format === "markdown",
        "[Figure ??]",
        "\\figurename~\\ref{fig:" <> lbl <> "}"]]
  ];

iDocResolveCiteRef[key_String, bibTable_Association, format_String] :=
  Module[{entry = Lookup[bibTable, key, None]},
    If[AssociationQ[entry],
      If[format === "markdown",
        "[" <> entry["Author"] <> ", " <> entry["Year"] <> "]" <>
          "(#ref-" <> key <> ")",
        "\\cite{" <> key <> "}"],
      If[format === "markdown",
        "[??]",
        "\\cite{" <> key <> "}"]]
  ];

(* ============================================================
   エクスポート: 言語検出・翻訳ヘルパー
   ============================================================ *)

(* テキストに日本語（CJK）文字が含まれるかを判定 *)
iDocContainsJapanese[text_String] :=
  StringContainsQ[text, RegularExpression["[\\x{3000}-\\x{9FFF}\\x{F900}-\\x{FAFF}]"]];

(* ノートブックのエクスポート時の表示言語を検出する。
   翻訳表示中のセルが多数なら翻訳モード、そうでなければ原文モード。 *)
iDocDetectExportLanguage[nb_NotebookObject] :=
  Module[{nCells, transCount = 0, totalCount = 0, mode, showTrans},
    nCells = NBAccess`NBCellCount[nb];
    Do[
      If[!iDocIsMetaCell[nb, i],
        mode = NBAccess`NBCellGetTaggingRule[nb, i, $iDocTagMode];
        showTrans = NBAccess`NBCellGetTaggingRule[nb, i, $iDocTagShowTranslation];
        If[StringQ[mode],
          totalCount++;
          If[TrueQ[showTrans], transCount++]]],
    {i, nCells}];
    If[totalCount > 0 && transCount > totalCount / 2,
      iDocTranslationTarget[],  (* 翻訳ターゲット言語 *)
      "source"]  (* 原文のまま *)
  ];

(* 文献タイトルを翻訳する（日本語→英語）。PDF コンテキストを参照して正確な英語タイトルを取得。 *)
iDocTranslateBibTitle[entry_Association, targetLang_String] :=
  Module[{title, pdfText, prompt, result},
    title = Lookup[entry, "Title", ""];
    If[!iDocContainsJapanese[title], Return[entry]];
    If[targetLang === "source", Return[entry]];

    (* PDF から英語タイトルを探す *)
    pdfText = If[StringQ[Lookup[entry, "FilePath", ""]] &&
      FileExistsQ[entry["FilePath"]],
      Quiet[Check[
        StringTake[Import[entry["FilePath"], "Plaintext"],
          Min[2000, StringLength[Import[entry["FilePath"], "Plaintext"]]]],
        ""]], ""];

    prompt = "Translate the following bibliographic reference title to English.\n" <>
      "If the reference is a thesis or dissertation, translate the title and add the type " <>
      "(e.g., 'Master's thesis' or 'PhD dissertation').\n" <>
      "If PDF text is provided, look for the English title in the text and use it exactly.\n\n" <>
      If[StringLength[pdfText] > 0,
        "PDF text (first pages, may contain the English title):\n" <>
        pdfText <> "\n\n", ""] <>
      "Author: " <> Lookup[entry, "Author", ""] <> "\n" <>
      "Japanese title: " <> title <> "\n\n" <>
      "CRITICAL: Output ONLY the English title, nothing else.";

    result = Quiet[Check[
      LLMSynthesize[prompt,
        LLMEvaluator -> <|"Model" -> "claude-sonnet-4-20250514"|>],
      $Failed]];
    If[StringQ[result] && StringLength[result] > 5 &&
       !iDocContainsJapanese[result],
      Join[entry, <|"Title" -> StringTrim[result]|>],
      entry]
  ];

(* 図キャプションをターゲット言語に翻訳する *)
iDocTranslateFigCaption[caption_String, targetLang_String] :=
  Module[{prompt, result},
    If[StringLength[caption] < 2, Return[caption]];
    (* 翻訳不要: ターゲットと同じ言語 *)
    If[targetLang === "source", Return[caption]];
    If[targetLang === "English" && !iDocContainsJapanese[caption], Return[caption]];
    If[targetLang =!= "English" && iDocContainsJapanese[caption], Return[caption]];

    prompt = "Translate the following figure caption to " <> targetLang <> ".\n" <>
      "Output ONLY the translated caption, nothing else.\n\n" <>
      "Caption: " <> caption;
    result = Quiet[Check[
      LLMSynthesize[prompt,
        LLMEvaluator -> <|"Model" -> "claude-sonnet-4-20250514"|>],
      $Failed]];
    If[StringQ[result] && StringLength[result] > 0,
      StringTrim[result], caption]
  ];

(* ============================================================
   エクスポート: 共通ヘルパー
   ============================================================ *)

(* ノートブック名（拡張子なし）を取得 *)
iDocNotebookBaseName[nb_NotebookObject] :=
  Module[{name},
    name = Quiet[NotebookFileName[nb]];
    If[StringQ[name],
      FileBaseName[name],
      "Untitled"]
  ];

(* 出力ディレクトリを作成して返す *)
iDocEnsureExportDir[nb_NotebookObject, suffix_String] :=
  Module[{dir, nbDir, baseName},
    nbDir = Quiet[NotebookDirectory[nb]];
    If[!StringQ[nbDir], Return[$Failed]];
    baseName = iDocNotebookBaseName[nb];
    dir = FileNameJoin[{nbDir, baseName <> "_" <> suffix}];
    If[!DirectoryQ[dir], CreateDirectory[dir]];
    dir
  ];

(* BoxData/TextData 内のインライン数式ボックスを TeX に変換する *)
(* FormBox は中身を取り出して変換する *)
iDocBoxToTeX[FormBox[content_, _]] := iDocBoxToTeX[content];

iDocBoxToTeX[box_] :=
  Quiet[Check[
    Module[{expr},
      expr = ToExpression[box, TraditionalForm, HoldForm];
      If[Head[expr] === HoldForm,
        ToString[TeXForm[ReleaseHold[expr]]],
        ToString[TeXForm[expr]]]],
    (* フォールバック: MakeBoxes → TeXForm が失敗する場合 *)
    With[{s = Quiet[ToString[box, InputForm]]},
      If[StringQ[s], s, "?"]]
  ]];

(* FormBox を TeX 文字列に変換 *)
iDocFormBoxToTeX[FormBox[content_, TraditionalForm]] :=
  iDocBoxToTeX[content];
iDocFormBoxToTeX[FormBox[content_, _]] :=
  iDocBoxToTeX[content];
iDocFormBoxToTeX[other_] := iDocBoxToTeX[other];

(* 単一の Box 要素 → TeX *)
iDocSingleBoxToTeX[s_String] := s;
iDocSingleBoxToTeX[FormBox[content_, _]] := iDocFormBoxToTeX[FormBox[content, TraditionalForm]];
iDocSingleBoxToTeX[Cell[BoxData[content_], "InlineFormula", ___]] := iDocBoxToTeX[content];
iDocSingleBoxToTeX[Cell[BoxData[content_], ___]] := iDocBoxToTeX[content];
iDocSingleBoxToTeX[StyleBox[content_, ___]] := iDocSingleBoxToTeX[content];
iDocSingleBoxToTeX[ButtonBox[content_, ___]] := iDocSingleBoxToTeX[content];
iDocSingleBoxToTeX[box_] := iDocBoxToTeX[box];

(* TextData 内の要素を走査して文字列 + TeX に変換 *)
iDocTextDataToString[text_String, format_String] := text;

iDocTextDataToString[TextData[elems_List], format_String] :=
  StringJoin[iDocElementToString[#, format] & /@ elems];

iDocTextDataToString[TextData[elem_], format_String] :=
  iDocElementToString[elem, format];

iDocTextDataToString[other_, _] :=
  If[StringQ[other], other, ToString[other, InputForm]];

(* 個別要素の変換 *)
iDocElementToString[s_String, _] := s;

(* インライン数式: FormBox *)
iDocElementToString[Cell[BoxData[FormBox[content_, TraditionalForm]], "InlineMath"|"InlineFormula", ___], format_String] :=
  Module[{tex = iDocFormBoxToTeX[FormBox[content, TraditionalForm]]},
    If[format === "markdown", "$" <> tex <> "$", "\\(" <> tex <> "\\)"]
  ];

iDocElementToString[Cell[BoxData[content_], "InlineMath"|"InlineFormula", ___], format_String] :=
  Module[{tex = iDocBoxToTeX[content]},
    If[format === "markdown", "$" <> tex <> "$", "\\(" <> tex <> "\\)"]
  ];

(* 一般的な InlineCell *)
iDocElementToString[Cell[BoxData[content_], opts___], format_String] :=
  Module[{tex = iDocBoxToTeX[content]},
    If[format === "markdown", "$" <> tex <> "$", "\\(" <> tex <> "\\)"]
  ];

(* StyleBox: ボールド、イタリック等 *)
iDocElementToString[StyleBox[content_, opts___], format_String] :=
  Module[{text = iDocSingleBoxToTeX[content], isBold, isItalic},
    isBold = MemberQ[{opts}, FontWeight -> "Bold" | Bold];
    isItalic = MemberQ[{opts}, FontSlant -> "Italic" | Italic];
    If[format === "markdown",
      If[isBold && isItalic, "***" <> text <> "***",
        If[isBold, "**" <> text <> "**",
          If[isItalic, "*" <> text <> "*", text]]],
      If[isBold, "\\textbf{" <> text <> "}",
        If[isItalic, "\\textit{" <> text <> "}", text]]]
  ];

(* FormBox（直接出現） *)
iDocElementToString[FormBox[content_, form_], format_String] :=
  Module[{tex = iDocFormBoxToTeX[FormBox[content, form]]},
    If[format === "markdown", "$" <> tex <> "$", "\\(" <> tex <> "\\)"]
  ];

(* ButtonBox (ハイパーリンク等) *)
iDocElementToString[ButtonBox[label_, ___, ButtonData -> {URL[url_], ___}, ___], format_String] :=
  If[format === "markdown",
    "[" <> iDocSingleBoxToTeX[label] <> "](" <> url <> ")",
    "\\href{" <> url <> "}{" <> iDocSingleBoxToTeX[label] <> "}"];

iDocElementToString[other_, format_String] :=
  Module[{tex = iDocSingleBoxToTeX[other]},
    If[StringQ[tex], tex, ""]
  ];

(* ============================================================
   エクスポート: 画像処理
   ============================================================ *)

(* セル内の画像種別を判定: "raster", "vector", "none" *)
iDocImageType[cellExpr_] :=
  Which[
    Length[Cases[cellExpr, _RasterBox, Infinity]] > 0, "raster",
    Length[Cases[cellExpr, _GraphicsBox | _Graphics3DBox, Infinity]] > 0, "vector",
    True, "none"
  ];

(* セルの画像をファイルにエクスポートする。
   戻り値: エクスポートされたファイルパス、または $Failed *)
iDocExportCellImage[nb_NotebookObject, cellIdx_Integer, outDir_String,
    baseName_String] :=
  Module[{cellExpr, imgType, filePath, cell},
    cellExpr = NBAccess`NBCellRead[nb, cellIdx];
    imgType = iDocImageType[cellExpr];
    Which[
      imgType === "raster",
        (* ラスター画像: PNG で出力（印刷品質 300 DPI） *)
        filePath = FileNameJoin[{outDir, baseName <> ".png"}];
        NBAccess`NBCellRasterize[nb, cellIdx, filePath,
          ImageResolution -> 300];
        If[FileExistsQ[filePath], filePath, $Failed],
      imgType === "vector",
        (* ベクター画像: PDF で出力 (ベクター品質維持) *)
        filePath = FileNameJoin[{outDir, baseName <> ".pdf"}];
        cell = Module[{c = iResolveExportCell[nb, cellIdx]},
          If[c === $Failed, Return[$Failed]]; c];
        (* まず NotebookRead の結果から Graphics 式を抽出して PDF Export を試みる *)
        Module[{graphics},
          graphics = Cases[cellExpr, g_Graphics | g_Graphics3D, Infinity];
          If[Length[graphics] > 0,
            Quiet[Export[filePath, First[graphics], "PDF"]],
            (* Graphics 式が直接取れない場合は FrontEnd 経由で PDF 化 *)
            Quiet[FrontEndExecute[
              FrontEnd`ExportPacket[cell, "PDF",
                GraphicsOutput -> "PDF",
                ImageResolution -> 300]]] /;
              False; (* FrontEnd`ExportPacket は戻り値処理が複雑なため、
                        代替として Rasterize → PDF を使う *)
            Quiet[Export[filePath, Rasterize[cell, ImageResolution -> 300], "PDF"]]]];
        (* フォールバック: PDF 出力に失敗した場合は PNG *)
        If[!FileExistsQ[filePath],
          filePath = FileNameJoin[{outDir, baseName <> ".png"}];
          Quiet[Export[filePath, Rasterize[cell, ImageResolution -> 300], "PNG"]]];
        If[FileExistsQ[filePath], filePath, $Failed],
      True,
        $Failed
    ]
  ];

(* セルオブジェクトを解決 (NBAccess`NBResolveCell へ委譲) *)
iResolveExportCell[nb_NotebookObject, cellIdx_Integer] :=
  NBAccess`NBResolveCell[nb, cellIdx];

(* ============================================================
   エクスポート: Input セル → コードブロック
   ============================================================ *)

iDocInputCellToCode[nb_NotebookObject, cellIdx_Integer, format_String] :=
  Module[{text},
    text = NBAccess`NBCellGetText[nb, cellIdx];
    If[!StringQ[text], text = NBAccess`NBCellReadInputText[nb, cellIdx]];
    If[!StringQ[text], Return[""]];
    If[format === "markdown",
      "```mathematica\n" <> text <> "\n```",
      "\\begin{lstlisting}[language=Mathematica]\n" <> text <> "\n\\end{lstlisting}"]
  ];

(* ============================================================
   エクスポート: Output セル処理
   ============================================================ *)

iDocOutputCellToExport[nb_NotebookObject, cellIdx_Integer, outDir_String,
    imgCounter_Integer, format_String, figTable_Association:<||>] :=
  Module[{cellExpr, hasImage, text, imgFile, imgName, figLabel, figCaption, figEntry},
    cellExpr = NBAccess`NBCellRead[nb, cellIdx];
    hasImage = NBAccess`NBCellHasImage[cellExpr];
    If[hasImage,
      (* 図メタデータ取得 *)
      figLabel = NBAccess`NBCellGetTaggingRule[nb, cellIdx, $iDocTagFigLabel];
      figCaption = NBAccess`NBCellGetTaggingRule[nb, cellIdx, $iDocTagFigCaption];
      If[!StringQ[figLabel] || StringTrim[figLabel] === "",
        figLabel = "fig" <> ToString[imgCounter]];
      If[!StringQ[figCaption], figCaption = ""];
      figEntry = Lookup[figTable, figLabel, None];

      (* 画像をエクスポート (ラベルをファイル名に使用) *)
      imgFile = iDocExportCellImage[nb, cellIdx, outDir, figLabel];
      If[StringQ[imgFile],
        Module[{relPath = FileNameTake[imgFile], figNumStr},
          figNumStr = ToString[If[AssociationQ[figEntry],
            figEntry["Number"], imgCounter]];
          If[format === "markdown",
            "![" <>
              If[figCaption =!= "",
                "Figure " <> figNumStr <> ": " <> figCaption,
                "Figure " <> figNumStr] <>
              "](" <> relPath <> ")" <>
              "{#fig-" <> figLabel <> " width=100%}",
            (* LaTeX: figure 環境 *)
            "\\begin{figure}[h]\n" <>
            "\\centerline{\\includegraphics[width=\\textwidth]{" <> relPath <> "}}\n" <>
            "\\caption{" <> figCaption <> "}\n" <>
            "\\label{fig:" <> figLabel <> "}\n" <>
            "\\end{figure}"]],
        (* 画像エクスポート失敗: テキストにフォールバック *)
        text = NBAccess`NBCellGetText[nb, cellIdx];
        If[StringQ[text], text, ""]],
      (* テキストのみの Output *)
      text = NBAccess`NBCellGetText[nb, cellIdx];
      If[StringQ[text] && StringTrim[text] =!= "",
        If[format === "markdown",
          "```\n" <> text <> "\n```",
          "\\begin{verbatim}\n" <> text <> "\n\\end{verbatim}"],
        ""]
    ]
  ];

(* ============================================================
   エクスポート: インライン数式検出 & LLM 変換
   ============================================================ *)

(* セル式がインライン数式（FormBox/BoxData in TextData）を含むか判定する *)
iDocCellHasInlineMath[cellExpr_] :=
  Length[Cases[cellExpr,
    Cell[BoxData[___], ___] | FormBox[_, _],
    Infinity, 1]] > 0;

(* セルを画像キャプチャ + LLM でテキスト＋LaTeX 数式に変換する。
   セルの描画結果を画像として LLM に送り、テキスト部分はそのまま保持しつつ
   数式部分だけを LaTeX 表記に変換してもらう。 *)
iDocConvertMathCellViaLLM[nb_NotebookObject, cellIdx_Integer,
    plainText_String, format_String] :=
  Module[{cell, img, prompt, result, model, mathDelim},
    cell = NBAccess`NBResolveCell[nb, cellIdx];
    If[cell === $Failed, Return[plainText]];
    img = Quiet[Check[Rasterize[cell, ImageResolution -> 144], $Failed]];
    If[!ImageQ[img], Return[plainText]];

    mathDelim = If[format === "latex",
      {"\\(", "\\)"}, {"$", "$"}];
    model = If[StringQ[$ClaudeModel] && StringLength[$ClaudeModel] > 0,
      $ClaudeModel, "claude-sonnet-4-20250514"];

    prompt = "You are a LaTeX expert. The image shows a rendered Mathematica cell containing text with mathematical formulas.\n" <>
      "The plain text of this cell is: \"" <> plainText <> "\"\n\n" <>
      "Your task: Reproduce the text EXACTLY, but wrap all mathematical expressions in " <>
      mathDelim[[1]] <> "..." <> mathDelim[[2]] <> " delimiters with proper LaTeX notation.\n\n" <>
      "Rules:\n" <>
      "- Look at the IMAGE to identify mathematical expressions (the image shows the correct rendering)\n" <>
      "- Non-math text must be preserved EXACTLY as-is (including CJK characters)\n" <>
      "- Math expressions: use standard LaTeX (e.g., f(x) = 2x + b → " <> mathDelim[[1]] <> "f(x) = 2x + b" <> mathDelim[[2]] <> ")\n" <>
      "- Fractions: use \\frac{}{}, superscripts: ^{}, subscripts: _{}\n" <>
      "- Do NOT add any preamble, explanation, or LaTeX document structure\n" <>
      "- Do NOT use markdown code fences\n" <>
      "- Output ONLY the converted text, starting from the first character\n";

    result = Quiet[Check[
      LLMSynthesize[{img, prompt},
        LLMEvaluator -> <|"Model" -> model|>],
      $Failed]];
    If[StringQ[result] && StringLength[result] > 0 &&
       !StringStartsQ[result, "Error"] &&
       !StringStartsQ[result, "[ERROR]"],
      (* マークダウンコードフェンス除去 *)
      result = StringReplace[result,
        RegularExpression["^\\s*```[a-z]*\\s*\\n?"] -> ""];
      result = StringReplace[result,
        RegularExpression["\\n?\\s*```\\s*$"] -> ""];
      StringTrim[result],
      plainText]
  ];

(* ============================================================
   エクスポート: ディスプレイ数式セル (DisplayFormula 等)
   ============================================================ *)

iDocDisplayMathToExport[nb_NotebookObject, cellIdx_Integer, format_String] :=
  Module[{cellExpr, content, tex, cell, img, prompt, result, model},
    cellExpr = NBAccess`NBCellRead[nb, cellIdx];
    If[cellExpr === $Failed, Return[""]];
    (* まずプログラム的変換を試みる *)
    content = cellExpr /. Cell[c_, ___] :> c;
    If[Head[content] === BoxData, content = First[content]];
    tex = iDocBoxToTeX[content];
    (* RowBox/FormBox 等の Box 式が残っていたら LLM にフォールバック *)
    If[!StringContainsQ[tex, "Box["],
      Return[If[format === "markdown",
        "\n$$\n" <> tex <> "\n$$\n",
        "\n\\[\n" <> tex <> "\n\\]\n"]]];
    (* LLM フォールバック: セルを画像キャプチャして変換 *)
    cell = NBAccess`NBResolveCell[nb, cellIdx];
    If[cell === $Failed, Return[""]];
    img = Quiet[Check[Rasterize[cell, ImageResolution -> 144], $Failed]];
    If[!ImageQ[img], Return[""]];
    model = If[StringQ[$ClaudeModel] && StringLength[$ClaudeModel] > 0,
      $ClaudeModel, "claude-sonnet-4-20250514"];
    prompt = "The image shows a mathematical formula rendered in Mathematica.\n" <>
      "Convert it to LaTeX notation.\n" <>
      "Rules:\n" <>
      "- Output ONLY the LaTeX math content (no delimiters, no \\[ \\], no $)\n" <>
      "- Use standard LaTeX: \\frac, ^{}, _{}, \\sum, \\int, etc.\n" <>
      "- Do NOT add any explanation or preamble\n";
    result = Quiet[Check[
      LLMSynthesize[{img, prompt},
        LLMEvaluator -> <|"Model" -> model|>],
      $Failed]];
    If[StringQ[result] && StringLength[result] > 0 &&
       !StringStartsQ[result, "Error"],
      result = StringReplace[result,
        RegularExpression["^\\s*```[a-z]*\\s*\\n?"] -> ""];
      result = StringReplace[result,
        RegularExpression["\\n?\\s*```\\s*$"] -> ""];
      tex = StringTrim[result]];
    If[format === "markdown",
      "\n$$\n" <> tex <> "\n$$\n",
      "\n\\[\n" <> tex <> "\n\\]\n"]
  ];

(* ============================================================
   エクスポート: テキストセル処理
   ============================================================ *)

iDocTextCellToExport[nb_NotebookObject, cellIdx_Integer, format_String,
    styleRemap_Association:<||>] :=
  Module[{style, cellExpr, content, text, level},
    style = NBAccess`NBCellStyle[nb, cellIdx];
    (* Directive で指定されたスタイル読み替えを適用 *)
    style = Lookup[styleRemap, style, style];
    cellExpr = NBAccess`NBCellRead[nb, cellIdx];
    If[cellExpr === $Failed, Return[""]];

    (* セル内容を取得 *)
    content = cellExpr /. Cell[c_, ___] :> c;

    (* テキスト変換 *)
    text = Which[
      StringQ[content],
        content,
      Head[content] === TextData,
        Module[{converted},
          converted = iDocTextDataToString[content, format];
          (* Box 式が残っていたらセル画像 + LLM で変換 *)
          If[StringQ[converted] && StringContainsQ[converted, "Box["],
            Module[{plain = NBAccess`NBCellGetText[nb, cellIdx]},
              If[StringQ[plain],
                converted = iDocConvertMathCellViaLLM[nb, cellIdx, plain, format]]];
          ];
          converted],
      Head[content] === BoxData,
        (* 数式セル *)
        Module[{tex = iDocBoxToTeX[First[content]]},
          (* Box 式が残っていたら LLM にフォールバック *)
          If[StringContainsQ[tex, "Box["],
            Module[{plain = NBAccess`NBCellGetText[nb, cellIdx]},
              If[StringQ[plain],
                Return[iDocConvertMathCellViaLLM[nb, cellIdx, plain, format]]]]];
          If[format === "markdown",
            "$" <> tex <> "$",
            "\\(" <> tex <> "\\)"]],
      True,
        NBAccess`NBCellGetText[nb, cellIdx]
    ];
    If[!StringQ[text], text = ""];

    (* スタイルに応じたフォーマット *)
    Switch[style,
      "Title",
        If[format === "markdown", "# " <> text, "\\title{" <> text <> "}"],
      "Subtitle",
        If[format === "markdown", "## " <> text, "\\subtitle{" <> text <> "}"],
      "Chapter",
        If[format === "markdown", "# " <> text, "\\chapter{" <> text <> "}"],
      "Section",
        If[format === "markdown", "## " <> text, "\\section{" <> text <> "}"],
      "Subsection",
        If[format === "markdown", "### " <> text, "\\subsection{" <> text <> "}"],
      "Subsubsection",
        If[format === "markdown", "#### " <> text, "\\subsubsection{" <> text <> "}"],
      "Item",
        If[format === "markdown", "- " <> text, "%%ITEMIZE%%\\item " <> text],
      "Subitem",
        If[format === "markdown", "  - " <> text, "%%SUBITEMIZE%%  \\item " <> text],
      "ItemNumbered",
        If[format === "markdown", "1. " <> text, "%%ENUMERATE%%\\item " <> text],
      "SubitemNumbered",
        If[format === "markdown", "   1. " <> text, "%%SUBENUMERATE%%  \\item " <> text],
      "DisplayFormula" | "DisplayFormulaNumbered",
        iDocDisplayMathToExport[nb, cellIdx, format],
      _,
        text
    ]
  ];

(* ============================================================
   エクスポート: メイン関数
   ============================================================ *)

(* 単一セルをエクスポート文字列に変換 *)
iDocCellToExport[nb_NotebookObject, cellIdx_Integer, outDir_String,
    imgCounter_Integer, format_String,
    figTable_Association:<||>, bibTable_Association:<||>,
    styleRemap_Association:<||>, exportLang_String:"source"] :=
  Module[{style, cellExpr, hasImage, result, mode, showTrans,
          figLabel, figCaption, figEntry},
    style = NBAccess`NBCellStyle[nb, cellIdx];

    (* Note/Dictionary/Directive/Bibliography セルはスキップ *)
    If[iDocIsMetaCell[nb, cellIdx], Return[{Null, imgCounter}]];

    (* Export 除外フラグが設定されたセルはスキップ *)
    If[TrueQ[NBAccess`NBCellGetTaggingRule[nb, cellIdx, $iDocTagExcludeExport]],
      Return[{Null, imgCounter}]];

    (* ドキュメントモード確認: idea モードならパラグラフ版を使う *)
    mode = NBAccess`NBCellGetTaggingRule[nb, cellIdx, $iDocTagMode];
    If[mode === "idea",
      Module[{para = NBAccess`NBCellGetTaggingRule[nb, cellIdx, $iDocTagAlternate]},
        If[StringQ[para] && StringTrim[para] =!= "",
          para = iDocResolveReferences[para, figTable, bibTable, format];
          Return[{para, imgCounter}]]]];

    (* === 全セルタイプ共通: 画像を含むセルは先に図として出力 === *)
    cellExpr = NBAccess`NBCellRead[nb, cellIdx];
    hasImage = NBAccess`NBCellHasImage[cellExpr];
    If[hasImage,
      figLabel = NBAccess`NBCellGetTaggingRule[nb, cellIdx, $iDocTagFigLabel];
      figCaption = NBAccess`NBCellGetTaggingRule[nb, cellIdx, $iDocTagFigCaption];
      If[!StringQ[figLabel] || StringTrim[figLabel] === "",
        figLabel = "fig" <> ToString[imgCounter]];
      If[!StringQ[figCaption], figCaption = ""];
      (* 翻訳モードならキャプションをターゲット言語に翻訳 *)
      If[figCaption =!= "" && exportLang =!= "source",
        figCaption = iDocTranslateFigCaption[figCaption, exportLang]];
      figEntry = Lookup[figTable, figLabel, None];
      Module[{imgFile, figOut, textPart = ""},
        imgFile = iDocExportCellImage[nb, cellIdx, outDir, figLabel];
        If[StringQ[imgFile],
          Module[{relPath = FileNameTake[imgFile], figNumStr},
            figNumStr = ToString[If[AssociationQ[figEntry],
              figEntry["Number"], imgCounter]];
            figOut = If[format === "markdown",
              (* Pandoc 互換形式: ![caption](file){#fig-label} *)
              "![" <>
                If[figCaption =!= "",
                  "Figure " <> figNumStr <> ": " <> figCaption,
                  "Figure " <> figNumStr] <>
                "](" <> relPath <> ")" <>
                "{#fig-" <> figLabel <> " width=100%}",
              (* LaTeX *)
              "\\begin{figure}[h]\n" <>
              "\\centerline{\\includegraphics[width=\\textwidth]{" <> relPath <> "}}\n" <>
              "\\caption{" <> figCaption <> "}\n" <>
              "\\label{fig:" <> figLabel <> "}\n" <>
              "\\end{figure}"];
            (* テキスト系セルなら本文テキストも出力 *)
            If[MemberQ[{"Text", "Section", "Subsection", "Subsubsection",
                        "Title", "Subtitle", "Chapter", "Item", "Subitem",
                        "ItemNumbered", "SubitemNumbered"}, style],
              textPart = iDocTextCellToExport[nb, cellIdx, format, styleRemap];
              textPart = iDocResolveReferences[textPart, figTable, bibTable, format]];
            Return[{If[textPart =!= "", textPart <> "\n\n" <> figOut, figOut],
              imgCounter + 1}]],
          (* 画像エクスポート失敗 → 通常処理にフォールスルー *)
          Null]]];

    (* スタイルに応じた処理 (画像なしセル) *)
    Which[
      (* Input セル → コードブロック *)
      style === "Input",
        {iDocInputCellToCode[nb, cellIdx, format], imgCounter},

      (* Output/Print セル → テキスト出力 (画像は上で処理済み) *)
      MemberQ[{"Output", "Print", "Message", "Echo"}, style],
        Module[{text = NBAccess`NBCellGetText[nb, cellIdx]},
          If[StringQ[text] && StringTrim[text] =!= "",
            {If[format === "markdown",
              "```\n" <> text <> "\n```",
              "\\begin{verbatim}\n" <> text <> "\n\\end{verbatim}"], imgCounter},
            {Null, imgCounter}]],

      (* DisplayFormula 等 *)
      MemberQ[{"DisplayFormula", "DisplayFormulaNumbered"}, style],
        {iDocDisplayMathToExport[nb, cellIdx, format], imgCounter},

      (* テキスト系セル (画像は上で処理済み) *)
      MemberQ[{"Title", "Subtitle", "Chapter", "Section", "Subsection",
               "Subsubsection", "Text", "Item", "Subitem",
               "ItemNumbered", "SubitemNumbered", "ItemParagraph",
               "SubitemParagraph"}, style],
        Module[{text = iDocTextCellToExport[nb, cellIdx, format, styleRemap]},
          text = iDocResolveReferences[text, figTable, bibTable, format];
          {text, imgCounter}],

      (* それ以外: スキップ *)
      True,
        {Null, imgCounter}
    ]
  ];

(* Markdown エクスポート *)

DocExportMarkdown[nb_NotebookObject, opts:OptionsPattern[]] :=
  Module[{outDir, nCells, lines = {}, imgCounter = 1,
          result, line, outFile, baseName, figTable, bibTable, bibLines,
          styleRemap, exportLang, mathFmt, mathCount = 0},
    mathFmt = TrueQ[OptionValue["MathFormat"]];
    outDir = iDocEnsureExportDir[nb, "md"];
    If[outDir === $Failed,
      MessageDialog[iL[
        "ノートブックのディレクトリを取得できません。\n先にノートブックを保存してください。",
        "Cannot get notebook directory.\nPlease save the notebook first."]];
      Return[$Failed]];
    baseName = iDocNotebookBaseName[nb];
    NBAccess`NBInvalidateCellsCache[nb];
    nCells = NBAccess`NBCellCount[nb];

    (* エクスポート言語を検出 *)
    exportLang = iDocDetectExportLanguage[nb];

    (* 図テーブル・参考文献・スタイル読み替えを構築 *)
    figTable = iDocBuildFigureTable[nb];
    bibTable = iDocCollectBibliography[nb];
    styleRemap = iDocParseStyleRemap[nb];

    Quiet[CurrentValue[nb, WindowStatusArea] =
      iL["Markdown エクスポート中...", "Exporting Markdown..."]];

    Do[
      Quiet[CurrentValue[nb, WindowStatusArea] =
        If[mathFmt,
          iL["エクスポート中 (数式最適化): ", "Exporting (math): "] <>
            ToString[i] <> "/" <> ToString[nCells],
          iL["エクスポート中: ", "Exporting: "] <>
            ToString[i] <> "/" <> ToString[nCells]]];
      {line, imgCounter} = iDocCellToExport[nb, i, outDir, imgCounter, "markdown",
        figTable, bibTable, styleRemap, exportLang];
      If[line =!= Null && StringQ[line] && StringTrim[line] =!= "",
        (* 数式最適化: テキスト行のみ対象 *)
        If[mathFmt &&
           !StringStartsQ[line, "```"] &&
           !StringStartsQ[line, "!["] &&
           !StringStartsQ[line, "$$"] &&
           StringLength[line] > 20,
          line = iDocLaTeXifyMath[line,
            iDocExtractCellPDFContext[nb, i]];
          mathCount++];
        AppendTo[lines, line]],
    {i, nCells}];

    If[mathFmt && mathCount > 0,
      Quiet[CurrentValue[nb, WindowStatusArea] =
        iL[ToString[mathCount] <> " セルの数式を最適化しました。",
           ToString[mathCount] <> " cells math-formatted."]]];

    (* 参考文献セクションの出力: Bibliography セル + refSources を統合 *)
    Module[{bibFromRefs, mergedBib = bibTable},
      bibFromRefs = iDocBuildBibFromRefSources[nb];
      Do[If[!KeyExistsQ[mergedBib, key], mergedBib[key] = bibFromRefs[key]],
        {key, Keys[bibFromRefs]}];
      (* 翻訳モードなら日本語タイトルを翻訳 *)
      If[exportLang =!= "source",
        Do[mergedBib[key] = iDocTranslateBibTitle[mergedBib[key], exportLang],
          {key, Keys[mergedBib]}]];
      If[Length[mergedBib] > 0,
        bibLines = {"## References\n"};
        Do[
          AppendTo[bibLines,
            "- <a id=\"ref-" <> key <> "\"></a>" <>
            mergedBib[key]["Author"] <> " (" <> mergedBib[key]["Year"] <> "). " <>
            mergedBib[key]["Title"] <> "."],
        {key, Keys[mergedBib]}];
        AppendTo[lines, StringRiffle[bibLines, "\n"]]]];

    (* ファイル出力 *)
    outFile = FileNameJoin[{outDir, baseName <> ".md"}];
    Export[outFile, StringRiffle[lines, "\n\n"], "Text", CharacterEncoding -> "UTF-8"];

    Quiet[CurrentValue[nb, WindowStatusArea] =
      iL["Markdown エクスポート完了: " <> outFile,
         "Markdown export complete: " <> outFile]];
    RunScheduledTask[With[{pNb = nb},
      Quiet[CurrentValue[pNb, WindowStatusArea] = ""]], {5}];

    outFile
  ];

(* LaTeX リスト環境の統合ポストプロセッサ。
   連続する %%ITEMIZE%%\item 行を \begin{itemize}...\end{itemize} にまとめる。 *)
iDocPostProcessLaTeXLists[text_String] :=
  Module[{lines, result = {}, i = 1, n, envTag, envName, block},
    lines = StringSplit[text, "\n"];
    n = Length[lines];
    While[i <= n,
      Which[
        StringStartsQ[lines[[i]], "%%ITEMIZE%%"],
          (* 連続する ITEMIZE 行を収集 *)
          block = {"\\begin{itemize}"};
          While[i <= n && StringStartsQ[lines[[i]], "%%ITEMIZE%%"],
            AppendTo[block,
              StringReplace[lines[[i]], "%%ITEMIZE%%" -> ""]];
            i++];
          AppendTo[block, "\\end{itemize}"];
          AppendTo[result, StringRiffle[block, "\n"]],
        StringStartsQ[lines[[i]], "%%SUBITEMIZE%%"],
          block = {"\\begin{itemize}"};
          While[i <= n && StringStartsQ[lines[[i]], "%%SUBITEMIZE%%"],
            AppendTo[block,
              StringReplace[lines[[i]], "%%SUBITEMIZE%%" -> ""]];
            i++];
          AppendTo[block, "\\end{itemize}"];
          AppendTo[result, StringRiffle[block, "\n"]],
        StringStartsQ[lines[[i]], "%%ENUMERATE%%"],
          block = {"\\begin{enumerate}"};
          While[i <= n && StringStartsQ[lines[[i]], "%%ENUMERATE%%"],
            AppendTo[block,
              StringReplace[lines[[i]], "%%ENUMERATE%%" -> ""]];
            i++];
          AppendTo[block, "\\end{enumerate}"];
          AppendTo[result, StringRiffle[block, "\n"]],
        StringStartsQ[lines[[i]], "%%SUBENUMERATE%%"],
          block = {"\\begin{enumerate}"};
          While[i <= n && StringStartsQ[lines[[i]], "%%SUBENUMERATE%%"],
            AppendTo[block,
              StringReplace[lines[[i]], "%%SUBENUMERATE%%" -> ""]];
            i++];
          AppendTo[block, "\\end{enumerate}"];
          AppendTo[result, StringRiffle[block, "\n"]],
        True,
          AppendTo[result, lines[[i]]];
          i++
      ]];
    StringRiffle[result, "\n"]
  ];

(* LaTeX エクスポート *)

(* ============================================================
   LaTeX 数式自動フォーマット (LLM ベース)
   テキスト中の数式表現を検出し、LaTeX 数式モードでラップする。
   ============================================================ *)

$iDocLaTeXifyPrompt =
  "You are a LaTeX typesetting expert specializing in mathematical notation. " <>
  "The following text will be included in a LaTeX document body (already inside \\begin{document}). " <>
  "Your task is to identify ALL mathematical expressions, symbols, variables, and notation " <>
  "in the text and wrap them in appropriate LaTeX inline math mode $...$.\n\n" <>
  "CRITICAL RULES:\n" <>
  "- Single variables used as mathematical symbols: $P$, $U$, $R$, $D$, $L$, $f_p$, $F_p$, $n$\n" <>
  "- Subscripted terms: f_p → $f_p$, F_p → $F_p$\n" <>
  "- Set notation: {0, 1} → $\\{0, 1\\}$\n" <>
  "- Superscripts: Z² → $\\mathbb{Z}^2$\n" <>
  "- Arrows: → or \\[RightArrow] → $\\to$\n" <>
  "- Products/crosses: × or * (when used as math operator) → $\\times$\n" <>
  "- Tuples with math: (Z², U, R, D, L, f_p) → $(\\mathbb{Z}^2, U, R, D, L, f_p)$\n" <>
  "- Function signatures: f_p: D * L * U * R → U * R * D * L → $f_p: D \\times L \\times U \\times R \\to U \\times R \\times D \\times L$\n" <>
  "- Equality statements with variables: U = R = D = L = {0, 1} → $U = R = D = L = \\{0, 1\\}$\n" <>
  "- Model names with numbers used mathematically: 2PCA(4) → 2PCA(4) (keep as-is if not pure math)\n" <>
  "- 2*2 or 2×2 blocks → $2 \\times 2$\n" <>
  "- Do NOT change any non-mathematical text — preserve it EXACTLY\n" <>
  "- CRITICAL: Preserve ALL existing LaTeX commands EXACTLY as they appear, including:\n" <>
  "  \\cite{...}, \\ref{...}, \\figurename, \\label{...}, and any other LaTeX commands.\n" <>
  "  These must appear in the output character-for-character identical to the input.\n" <>
  "- Do NOT add any explanation, preamble, or commentary\n" <>
  "- Do NOT add \\begin{document}, \\documentclass, or any LaTeX preamble commands\n" <>
  "- Do NOT wrap entire sentences in math mode — only the mathematical parts\n" <>
  "- Output ONLY the improved text, starting from the first character\n" <>
  "- If reference context from a PDF is provided, use it to identify the correct mathematical notation\n\n" <>
  "Text to format:\n";

(* 同期 LLM 呼び出しで数式フォーマットする。
   アタッチされた PDF の内容を参照コンテキストとして使用。
   Opus モデルで高精度に変換する。 *)
iDocLaTeXifyMath[text_String, pdfContext_String:""] :=
  Module[{prompt, result, model, protected, placeholders = <||>, counter = 0,
          restored, matches},
    (* 短すぎるテキストやセクション見出しのみのセルはスキップ *)
    If[StringLength[text] < 30, Return[text]];
    (* LaTeX コマンドで始まる行（見出し等）は中身だけ処理 *)
    If[StringMatchQ[text, "\\\\section{*}" | "\\\\subsection{*}" |
        "\\\\subsubsection{*}" | "\\\\title{*}" |
        "\\\\chapter{*}"],
      Return[text]];

    model = If[StringQ[$ClaudeModel] && StringLength[$ClaudeModel] > 0,
      $ClaudeModel, "claude-sonnet-4-20250514"];

    (* === LaTeX コマンドをプレースホルダーで保護 ===
       \cite{...}, \ref{...}, \figurename~\ref{...}, \label{...} 等を
       LLM に送る前に一意のプレースホルダーに置換し、戻り後に復元する。 *)
    protected = text;
    (* \figurename~\ref{...} を先に保護（\ref 単体の前に） *)
    matches = StringCases[protected,
      RegularExpression["\\\\figurename~\\\\ref\\{[^}]+\\}"]];
    Do[Module[{tag = "LATEXCMD" <> ToString[++counter] <> "XDMC"},
      placeholders[tag] = m;
      protected = StringReplace[protected, m -> tag, 1]],
    {m, matches}];
    (* \cite{...}, \ref{...}, \label{...}, \eqref{...}, \pageref{...} を保護 *)
    matches = StringCases[protected,
      RegularExpression["\\\\(cite|ref|label|eqref|pageref)\\{[^}]+\\}"]];
    Do[Module[{tag = "LATEXCMD" <> ToString[++counter] <> "XDMC"},
      placeholders[tag] = m;
      protected = StringReplace[protected, m -> tag, 1]],
    {m, matches}];
    (* Markdown 引用・図参照リンク [text](#ref-key) / [Figure N](#fig-label) を保護 *)
    matches = StringCases[protected,
      RegularExpression["\\[[^\\]]+\\]\\(#(ref|fig)-[^)]+\\)"]];
    Do[Module[{tag = "LATEXCMD" <> ToString[++counter] <> "XDMC"},
      placeholders[tag] = m;
      protected = StringReplace[protected, m -> tag, 1]],
    {m, matches}];

    prompt = $iDocLaTeXifyPrompt <>
      If[StringLength[pdfContext] > 0,
        "\n\n=== Reference context from attached PDF (use for accurate math notation) ===\n" <>
        StringTake[pdfContext, Min[8000, StringLength[pdfContext]]] <>
        "\n=== End reference context ===\n\n", ""] <>
      protected;

    result = Quiet[Check[
      LLMSynthesize[prompt,
        LLMEvaluator -> <|"Model" -> model|>],
      $Failed]];
    If[StringQ[result] && StringLength[result] > 0 &&
       !StringStartsQ[result, "Error"] &&
       !StringStartsQ[result, "[ERROR]"] &&
       StringLength[result] > StringLength[protected] * 0.3,
      (* プレースホルダーを元の LaTeX コマンドに復元 *)
      restored = result;
      Do[restored = StringReplace[restored, tag -> placeholders[tag]],
        {tag, Keys[placeholders]}];
      restored,
      text]
  ];

(* ノートブックのアタッチメント PDF からテキストを抽出する *)
iDocExtractPDFContext[nb_NotebookObject] :=
  Module[{atts, pdfFiles, texts = {}},
    atts = Quiet[NBAccess`NBHistoryGetAttachments[nb, "history"]];
    If[!ListQ[atts] || Length[atts] === 0, Return[""]];
    pdfFiles = Select[atts, StringEndsQ[#, ".pdf", IgnoreCase -> True] &];
    If[Length[pdfFiles] === 0, Return[""]];
    Do[
      Module[{txt},
        If[FileExistsQ[f],
          txt = Quiet[Check[Import[f, "Plaintext"], ""]];
          If[StringQ[txt] && StringLength[txt] > 50,
            AppendTo[texts, StringTake[txt, Min[4000, StringLength[txt]]]]]]],
    {f, Take[pdfFiles, Min[3, Length[pdfFiles]]]}];
    StringRiffle[texts, "\n---\n"]
  ];

(* ノートブックの現在のアタッチメントリストを取得する *)
iDocGetCurrentAttachments[nb_NotebookObject] :=
  Module[{atts},
    atts = Quiet[NBAccess`NBHistoryGetAttachments[nb, "history"]];
    If[ListQ[atts], atts, {}]
  ];

(* セルの refSources を取得する。
   形式: {{"filepath.pdf", All}, {"other.pdf", {1, 3, 5}}, ...}
   または旧形式（文字列リスト）も受け付ける *)
iDocGetRefSources[nb_NotebookObject, cellIdx_Integer] :=
  Module[{raw},
    raw = NBAccess`NBCellGetTaggingRule[nb, cellIdx, $iDocTagRefSources];
    Which[
      ListQ[raw] && Length[raw] > 0 && ListQ[First[raw]], raw,
      ListQ[raw], {#, All} & /@ raw,  (* 旧形式: 文字列リスト → All ページ *)
      True, {}]
  ];

(* セルに refSources を設定する *)
iDocSetRefSources[nb_NotebookObject, cellIdx_Integer, sources_List] :=
  NBAccess`NBCellSetTaggingRule[nb, cellIdx, $iDocTagRefSources, sources];

(* PDF ファイルから指定ページのテキストを抽出する。
   pages = All → 全ページ（上限あり）、pages = {1, 3, 5} → 指定ページのみ *)
iDocExtractPDFPages[filePath_String, pages_] :=
  Module[{txt, nPages, selectedPages, result = ""},
    If[!FileExistsQ[filePath], Return[""]];
    If[pages === All,
      txt = Quiet[Check[Import[filePath, "Plaintext"], ""]];
      If[StringQ[txt], Return[StringTake[txt, Min[4000, StringLength[txt]]]]];
      Return[""]];
    (* ページ指定: Import で個別ページ抽出を試みる *)
    nPages = Quiet[Check[Import[filePath, {"PageCount"}], 0]];
    If[!IntegerQ[nPages] || nPages === 0,
      (* PageCount 取得失敗: 全文フォールバック *)
      txt = Quiet[Check[Import[filePath, "Plaintext"], ""]];
      If[StringQ[txt], Return[StringTake[txt, Min[4000, StringLength[txt]]]]];
      Return[""]];
    selectedPages = Select[pages, IntegerQ[#] && 1 <= # <= nPages &];
    If[Length[selectedPages] === 0, Return[""]];
    Do[
      Module[{pageTxt},
        pageTxt = Quiet[Check[Import[filePath, {"Plaintext", p}], ""]];
        If[StringQ[pageTxt] && StringLength[pageTxt] > 0,
          result = result <> "[Page " <> ToString[p] <> "]\n" <> pageTxt <> "\n\n"]],
    {p, selectedPages}];
    StringTake[result, Min[4000, StringLength[result]]]
  ];

(* セル固有の PDF コンテキストを抽出する。
   refSources が設定されていればそれを使い、なければ全アタッチメントにフォールバック。 *)
iDocExtractCellPDFContext[nb_NotebookObject, cellIdx_Integer] :=
  Module[{refs, texts = {}, atts, pdfFiles},
    refs = iDocGetRefSources[nb, cellIdx];
    If[Length[refs] > 0,
      (* refSources が設定済み: 指定ファイル・ページのみ抽出 *)
      Do[
        Module[{f = ref[[1]], pages = ref[[2]], txt},
          txt = iDocExtractPDFPages[f, pages];
          If[StringLength[txt] > 0,
            AppendTo[texts, "[" <> FileNameTake[f] <> "]\n" <> txt]]],
      {ref, refs}];
      Return[StringRiffle[texts, "\n---\n"]]];
    (* フォールバック: ノートブックの全アタッチメント *)
    iDocExtractPDFContext[nb]
  ];

(* 依存資料編集ダイアログ *)
DocEditRefSources[nb_NotebookObject, cellIdx_Integer] :=
  Module[{refs, atts, pdfAtts, dlgRefs, pdfNames},
    refs = iDocGetRefSources[nb, cellIdx];
    atts = iDocGetCurrentAttachments[nb];
    pdfAtts = Select[atts, StringEndsQ[#, ".pdf", IgnoreCase -> True] &];
    pdfNames = FileNameTake /@ pdfAtts;
    (* ダイアログ用: {ファイル名, ページ指定文字列, フルパス, 有効フラグ} *)
    dlgRefs = Table[
      Module[{existing, pageStr},
        existing = Select[refs, #[[1]] === pdfAtts[[i]] &];
        pageStr = If[Length[existing] > 0,
          Module[{ps = existing[[1, 2]]},
            If[ps === All, "All", StringRiffle[ToString /@ ps, ","]]],
          ""];
        {pdfNames[[i]], pageStr, pdfAtts[[i]], pageStr =!= ""}],
    {i, Length[pdfAtts]}];
    If[Length[dlgRefs] === 0,
      MessageDialog[iL["アタッチされた PDF がありません。",
        "No PDF attachments found."]];
      Return[$Failed]];
    DialogInput[
      DynamicModule[{rows = dlgRefs},
      Column[{
        Style[iL["依存資料", "Reference Sources"], Bold, 12],
        Style[iL["ページ: 数字をカンマ区切り (例: 1,3,5) または All",
          "Pages: comma-separated numbers (e.g. 1,3,5) or All"], 8, GrayLevel[0.5]],
        Spacer[3],
        Dynamic[Column[
          Table[
            Row[{
              Checkbox[Dynamic[rows[[i, 4]]]],
              Style[" " <> rows[[i, 1]], 10],
              Spacer[5],
              InputField[Dynamic[rows[[i, 2]]], String, FieldSize -> 10]
            }],
          {i, Length[rows]}], Spacings -> 0.3]],
        Spacer[5],
        Row[{
          DefaultButton[(
            Module[{newRefs = {}},
              Do[
                If[rows[[j, 4]],
                  Module[{pages, pageStr = StringTrim[rows[[j, 2]]]},
                    pages = If[pageStr === "" || ToLowerCase[pageStr] === "all",
                      All,
                      Quiet[ToExpression["{" <> pageStr <> "}"]]];
                    If[!ListQ[pages], pages = All];
                    AppendTo[newRefs, {rows[[j, 3]], pages}]]],
              {j, Length[rows]}];
              iDocSetRefSources[nb, cellIdx, newRefs]];
            DialogReturn[])],
          CancelButton[DialogReturn[]]
        }, Spacer[10]]
      }, Alignment -> Left]],
      WindowTitle -> iL["依存資料", "Reference Sources"],
      WindowSize -> {320, Automatic}]
  ];

iDocEditRefSourcesAction[] :=
  Module[{nb, cellIdx},
    {nb, cellIdx} = iDocResolveTargetCell[];
    If[cellIdx === 0,
      MessageDialog[iL["セルを選択してください。", "Please select a cell."]];
      Return[$Failed]];
    DocEditRefSources[nb, cellIdx]
  ];


(* ============================================================
   自動引用挿入 (Auto-Citation) — 非同期チェーン実行
   
   Phase 1: refSources から文献リスト構築 + LLM で書誌情報を正確化
   Phase 2: 各セルのパラグラフに代表引用を1つ挿入
   Phase 3: 未引用文献を関連パラグラフに配置 / 無関係なら取り消し
   Phase 5: Bibliography セルを生成/更新
   ============================================================ *)

(* PDF ファイル名から引用キー・著者・年を推定する *)
iDocParsePDFFileName[path_String] :=
  Module[{name, parts, year = "", author = "", key},
    name = FileBaseName[path];
    Module[{yearMatch = StringCases[name, RegularExpression["(\\d{4})"] -> "$1"]},
      If[Length[yearMatch] > 0, year = First[yearMatch]]];
    parts = StringSplit[name, {"-", "_", "."}];
    Do[If[!StringMatchQ[p, NumberString] && StringLength[p] > 1,
      author = p; Break[]], {p, parts}];
    If[author === "" && Length[parts] > 0, author = First[parts]];
    key = ToLowerCase[author] <> year;
    {key, author, year}
  ];

(* 初期文献データベースを refSources から構築する *)
iDocBuildBibFromRefSources[nb_NotebookObject] :=
  Module[{nCells, refs, bib = <||>, seen = <||>},
    nCells = NBAccess`NBCellCount[nb];
    Do[
      refs = iDocGetRefSources[nb, i];
      Do[Module[{f = ref[[1]], parsed, key, author, year},
        If[!KeyExistsQ[seen, f],
          seen[f] = True;
          parsed = iDocParsePDFFileName[f];
          {key, author, year} = parsed;
          If[KeyExistsQ[bib, key],
            key = key <> "-" <> ToString[Length[bib] + 1]];
          bib[key] = <|"Author" -> author, "Year" -> year,
            "Title" -> FileBaseName[f], "FilePath" -> f,
            "CiteKey" -> key, "Enriched" -> False, "AutoInserted" -> False,
            "Unrelated" -> False|>]],
      {ref, refs}],
    {i, nCells}];
    bib
  ];

(* セルの refSources から引用キーリストを取得する *)
iDocCellCiteKeys[nb_NotebookObject, cellIdx_Integer, bibDB_Association] :=
  Module[{refs, keys = {}},
    refs = iDocGetRefSources[nb, cellIdx];
    Do[Module[{f = ref[[1]]},
      Do[If[bibDB[k]["FilePath"] === f,
        AppendTo[keys, k]; Break[]], {k, Keys[bibDB]}]],
    {ref, refs}];
    keys
  ];

(* Phase 1: LLM で書誌情報を正確化 *)
iDocEnrichBibPrompt[pdfText_String, fileName_String] :=
  "You are a bibliographic reference expert. " <>
  "Extract the EXACT bibliographic information for the paper from the text below.
" <>
  "If the text is insufficient, use your knowledge to identify the paper from the filename.

" <>
  "Filename: " <> fileName <> "

" <>
  "CRITICAL: Output ONLY in this exact format, one field per line:
" <>
  "Author: <full author names>
Year: <year>
Title: <exact title>
" <>
  "Journal: <journal or Book/Thesis/Preprint>
" <>
  "Volume: <volume or empty>
Pages: <pages or empty>

" <>
  "Paper text (first pages):
" <>
  StringTake[pdfText, Min[3000, StringLength[pdfText]]];

iDocParseEnrichResponse[response_String] :=
  Module[{lines, result = <||>},
    lines = StringSplit[response, "
"];
    Do[Which[
      StringStartsQ[line, "Author:"],
        result["Author"] = StringTrim[StringDrop[line, 7]],
      StringStartsQ[line, "Year:"],
        result["Year"] = StringTrim[StringDrop[line, 5]],
      StringStartsQ[line, "Title:"],
        result["Title"] = StringTrim[StringDrop[line, 6]],
      StringStartsQ[line, "Journal:"],
        result["Journal"] = StringTrim[StringDrop[line, 8]],
      StringStartsQ[line, "Volume:"],
        result["Volume"] = StringTrim[StringDrop[line, 7]],
      StringStartsQ[line, "Pages:"],
        result["Pages"] = StringTrim[StringDrop[line, 6]]],
    {line, lines}];
    result
  ];

iDocEnrichBibChain[nb_, bibDB_, keys_, pos_, completionFn_, fb_] :=
  If[pos > Length[keys],
    completionFn[bibDB],
    Module[{key = keys[[pos]], entry, pdfText, prompt},
      entry = bibDB[key];
      If[TrueQ[entry["Enriched"]],
        iDocEnrichBibChain[nb, bibDB, keys, pos + 1, completionFn, fb],
        Quiet[CurrentValue[nb, WindowStatusArea] =
          iL["文献情報を取得中: ", "Enriching bibliography: "] <>
            ToString[pos] <> "/" <> ToString[Length[keys]]];
        pdfText = If[StringQ[entry["FilePath"]] && FileExistsQ[entry["FilePath"]],
          Quiet[Check[Import[entry["FilePath"], "Plaintext"], ""]], ""];
        prompt = iDocEnrichBibPrompt[
          If[StringQ[pdfText], pdfText, ""], FileNameTake[entry["FilePath"]]];
        NBAccess`$NBLLMQueryFunc[prompt,
          Function[response,
            Module[{parsed, updatedDB = bibDB},
              If[StringQ[response] && StringContainsQ[response, "Author:"],
                parsed = iDocParseEnrichResponse[response];
                If[KeyExistsQ[parsed, "Author"],
                  updatedDB[key] = Join[updatedDB[key], parsed,
                    <|"Enriched" -> True|>]]];
              iDocEnrichBibChain[nb, updatedDB, keys, pos + 1, completionFn, fb]]],
          nb, Fallback -> fb]]]
  ];

(* Phase 2: 各セルに代表引用を1つ挿入 *)
iDocInsertCitePrompt[text_String, citeKey_String, bibEntry_Association] :=
  "Insert a single citation marker into the following paragraph.

" <>
  "Reference: " <> citeKey <> " = " <>
    bibEntry["Author"] <> " (" <> bibEntry["Year"] <> "). " <>
    Lookup[bibEntry, "Title", ""] <> "

" <>
  "Rules:
" <>
  "- Insert exactly ONE <<cite:" <> citeKey <> ">> at the MOST appropriate position
" <>
  "- Best: after mentioning the author/work, or after a claim from this reference
" <>
  "- If author with year appears (e.g. Morita (1996)), convert to Morita <<cite:" <> citeKey <> ">>
" <>
  "- Do NOT change any text content
" <>
  "- If already contains <<cite:" <> citeKey <> ">>, output unchanged
" <>
  "- CRITICAL: Output ONLY the text with the citation inserted

" <>
  "Text:
" <> text;

iDocCiteCellChain[nb_, bibDB_, cellIdxs_, pos_, completionFn_, fb_] :=
  If[pos > Length[cellIdxs],
    completionFn[],
    Module[{cellIdx = cellIdxs[[pos]], mode, text, citeKeys, key, entry, prompt},
      NBAccess`NBInvalidateCellsCache[nb];
      mode = NBAccess`NBCellGetTaggingRule[nb, cellIdx, $iDocTagMode];
      If[mode === "idea" || iDocIsMetaCell[nb, cellIdx],
        iDocCiteCellChain[nb, bibDB, cellIdxs, pos + 1, completionFn, fb];
        Return[]];
      citeKeys = iDocCellCiteKeys[nb, cellIdx, bibDB];
      text = NBAccess`NBCellGetText[nb, cellIdx];
      If[Length[citeKeys] === 0 || !StringQ[text] || StringLength[text] < 20,
        iDocCiteCellChain[nb, bibDB, cellIdxs, pos + 1, completionFn, fb];
        Return[]];
      key = First[citeKeys];
      If[StringContainsQ[text, "<<cite:" <> key <> ">>"],
        iDocCiteCellChain[nb, bibDB, cellIdxs, pos + 1, completionFn, fb];
        Return[]];
      entry = bibDB[key];
      Quiet[CurrentValue[nb, WindowStatusArea] =
        iL["引用挿入中: ", "Inserting citations: "] <>
          ToString[pos] <> "/" <> ToString[Length[cellIdxs]]];
      prompt = iDocInsertCitePrompt[text, key, entry];
      iDocSetJobAnchorCell[nb, cellIdx];
      With[{nb2 = nb, ci = cellIdx, db = bibDB, idxs = cellIdxs,
            p = pos, cfn = completionFn, f = fb},
        NBAccess`$NBLLMQueryFunc[prompt,
          Function[response,
            If[StringQ[response] && StringLength[response] > StringLength[text] * 0.3 &&
               StringContainsQ[response, "<<cite:"],
              NBAccess`NBInvalidateCellsCache[nb2];
              NBAccess`NBCellWriteText[nb2, ci, StringTrim[response]];
              NBAccess`NBCellSetTaggingRule[nb2, ci,
                $iDocTagCleanText, StringTrim[response]]];
            iDocCiteCellChain[nb2, db, idxs, p + 1, cfn, f]],
          nb, PrivacyLevel -> NBAccess`NBCellPrivacyLevel[nb, cellIdx],
          Fallback -> fb]]]
  ];

(* Phase 3: 未引用文献の処理 *)
iDocFindUncitedKeys[nb_NotebookObject, bibDB_Association] :=
  Module[{nCells, allText = "", cited = {}},
    nCells = NBAccess`NBCellCount[nb];
    Do[If[!iDocIsMetaCell[nb, i],
      Module[{t = NBAccess`NBCellGetText[nb, i]},
        If[StringQ[t], allText = allText <> t]]],
    {i, nCells}];
    Do[If[StringContainsQ[allText, "<<cite:" <> k <> ">>"],
      AppendTo[cited, k]], {k, Keys[bibDB]}];
    Complement[Keys[bibDB], cited]
  ];

iDocPlaceUncitedPrompt[uncitedKey_String, bibEntry_Association,
    paragraphs_List] :=
  "You have an uncited reference that needs to be placed in the document.

" <>
  "Reference: " <> uncitedKey <> " = " <>
    bibEntry["Author"] <> " (" <> bibEntry["Year"] <> "). " <>
    Lookup[bibEntry, "Title", ""] <> "

" <>
  "Paragraphs (numbered):
" <>
    StringRiffle[MapIndexed[
      "[" <> ToString[First[#2]] <> "] " <>
        StringTake[#1, Min[200, StringLength[#1]]] <> "..." &,
      paragraphs], "
"] <> "

" <>
  "Rules:
" <>
  "- If this reference is related to any paragraph, output: PLACE <number>
" <>
  "- If clearly unrelated to ALL paragraphs, output: UNRELATED
" <>
  "- Output ONLY one of these two formats";

iDocPlaceUncitedChain[nb_, bibDB_, uncitedKeys_, pos_, completionFn_, fb_,
    paragraphs_, paraIdxs_] :=
  If[pos > Length[uncitedKeys],
    completionFn[bibDB],
    Module[{key = uncitedKeys[[pos]], entry, prompt},
      entry = bibDB[key];
      Quiet[CurrentValue[nb, WindowStatusArea] =
        iL["未引用文献を配置中: ", "Placing uncited: "] <>
          ToString[pos] <> "/" <> ToString[Length[uncitedKeys]]];
      prompt = iDocPlaceUncitedPrompt[key, entry, paragraphs];
      With[{nb2 = nb, db = bibDB, uks = uncitedKeys, p = pos,
            cfn = completionFn, f = fb, pIdxs = paraIdxs, k = key,
            paras = paragraphs},
        NBAccess`$NBLLMQueryFunc[prompt,
          Function[response,
            Module[{updatedDB = db, placeNum, targetIdx, targetText},
              If[StringQ[response],
                Which[
                  StringStartsQ[StringTrim[response], "UNRELATED"],
                    updatedDB[k] = Join[updatedDB[k], <|"Unrelated" -> True|>],
                  StringStartsQ[StringTrim[response], "PLACE"],
                    placeNum = Quiet[ToExpression[
                      StringTrim[StringReplace[response, "PLACE" -> ""]]]];
                    If[IntegerQ[placeNum] && 1 <= placeNum <= Length[pIdxs],
                      targetIdx = pIdxs[[placeNum]];
                      NBAccess`NBInvalidateCellsCache[nb2];
                      targetText = NBAccess`NBCellGetText[nb2, targetIdx];
                      If[StringQ[targetText] &&
                         !StringContainsQ[targetText, "<<cite:" <> k <> ">>"],
                        Module[{newText = targetText <> " <<cite:" <> k <> ">>"},
                          NBAccess`NBCellWriteText[nb2, targetIdx, newText];
                          NBAccess`NBCellSetTaggingRule[nb2, targetIdx,
                            $iDocTagCleanText, newText]]]]
                ]];
              iDocPlaceUncitedChain[nb2, updatedDB, uks, p + 1, cfn, f,
                paras, pIdxs]]],
          nb, Fallback -> fb]]]
  ];

(* Phase 5: Bibliography セル生成/更新 *)
iDocGenerateBibCell[nb_NotebookObject, bibDB_Association] :=
  Module[{existingBib, mergedBib, nCells, bibCellIdx = 0, bibText, bibCell,
          normalEntries, unrelatedEntries},
    existingBib = iDocCollectBibliography[nb];
    mergedBib = existingBib;
    Do[If[!KeyExistsQ[mergedBib, key], mergedBib[key] = bibDB[key]],
      {key, Keys[bibDB]}];
    If[Length[mergedBib] === 0, Return[]];
    NBAccess`NBInvalidateCellsCache[nb];
    nCells = NBAccess`NBCellCount[nb];
    Do[If[NBAccess`NBCellStyle[nb, i] === "Bibliography",
      bibCellIdx = i; Break[]], {i, nCells}];
    normalEntries = Select[Keys[mergedBib],
      !TrueQ[Lookup[mergedBib[#], "Unrelated", False]] &];
    unrelatedEntries = Select[Keys[mergedBib],
      TrueQ[Lookup[mergedBib[#], "Unrelated", False]] &];
    bibText = "{" <> StringRiffle[
      Prepend[
        Join[
          (Module[{e = mergedBib[#]},
            "{\"" <> # <> "\", \"" <> Lookup[e, "Author", "?"] <>
            "\", \"" <> Lookup[e, "Year", "?"] <> "\", \"" <>
            Lookup[e, "Title", "?"] <>
            If[StringQ[Lookup[e, "Journal", ""]] &&
               StringLength[Lookup[e, "Journal", ""]] > 0,
              ", " <> e["Journal"] <>
              If[StringQ[Lookup[e, "Volume", ""]] &&
                 StringLength[e["Volume"]] > 0, " " <> e["Volume"], ""] <>
              If[StringQ[Lookup[e, "Pages", ""]] &&
                 StringLength[e["Pages"]] > 0, ", pp. " <> e["Pages"], ""],
              ""] <> "\"}"] & /@ normalEntries),
          (Module[{e = mergedBib[#]},
            "{\"" <> # <> "\", \"" <> Lookup[e, "Author", "?"] <>
            "\", \"" <> Lookup[e, "Year", "?"] <>
            "\", \"UNRELATED: " <> Lookup[e, "Title", "?"] <>
            "\"}"] & /@ unrelatedEntries)],
        "{<<Key>>, <<Author>>, <<Year>>, <<Title>>}"],
      ", "] <> "}";
    If[bibCellIdx > 0,
      NBAccess`NBInvalidateCellsCache[nb];
      NBAccess`NBCellWriteText[nb, bibCellIdx, bibText],
      bibCell = Cell[bibText, "Bibliography",
        Sequence @@ $iDocBibliographyCellOpts];
      SelectionMove[nb, After, Notebook];
      NotebookWrite[nb, bibCell]];
  ];

(* メインオーケストレータ *)
DocAutoInsertCitations[nb_NotebookObject] :=
  Module[{bibDB, nCells, cellsWithRefs = {}, paragraphs = {}, paraIdxs = {},
          fb},
    NBAccess`NBInvalidateCellsCache[nb];
    bibDB = iDocBuildBibFromRefSources[nb];
    If[Length[bibDB] === 0,
      MessageDialog[iL["依存資料が設定されたセルがありません。
" <>
        "「依存資料」ボタンでセルに資料を関連付けてください。",
        "No cells have reference sources set.
" <>
        "Use Ref Src button to associate sources with cells."]];
      Return[$Failed]];
    fb = ClaudeCode`GetPaletteFallback[];
    nCells = NBAccess`NBCellCount[nb];
    Do[If[!iDocIsMetaCell[nb, i],
      Module[{mode = NBAccess`NBCellGetTaggingRule[nb, i, $iDocTagMode],
              text = NBAccess`NBCellGetText[nb, i]},
        If[Length[iDocGetRefSources[nb, i]] > 0 && mode =!= "idea",
          AppendTo[cellsWithRefs, i]];
        If[StringQ[text] && StringLength[text] > 30 && mode =!= "idea",
          AppendTo[paragraphs, text]; AppendTo[paraIdxs, i]]]],
    {i, nCells}];
    Quiet[CurrentValue[nb, WindowStatusArea] =
      iL["自動引用: 書誌情報を取得中...", "Auto-cite: enriching bibliography..."]];
    iDocEnrichBibChain[nb, bibDB, Keys[bibDB], 1,
      Function[enrichedDB,
        Quiet[CurrentValue[nb, WindowStatusArea] =
          iL["自動引用: 引用を挿入中...", "Auto-cite: inserting citations..."]];
        iDocCiteCellChain[nb, enrichedDB, cellsWithRefs, 1,
          Function[],  fb];
        RunScheduledTask[
          Module[{uncited},
            NBAccess`NBInvalidateCellsCache[nb];
            uncited = iDocFindUncitedKeys[nb, enrichedDB];
            If[Length[uncited] > 0,
              Quiet[CurrentValue[nb, WindowStatusArea] =
                iL["自動引用: 未引用文献を配置中...",
                   "Auto-cite: placing uncited refs..."]];
              iDocPlaceUncitedChain[nb, enrichedDB, uncited, 1,
                Function[finalDB,
                  iDocGenerateBibCell[nb, finalDB];
                  Quiet[CurrentValue[nb, WindowStatusArea] =
                    iL["自動引用完了", "Auto-cite done"]];
                  RunScheduledTask[With[{pNb = nb},
                    Quiet[CurrentValue[pNb, WindowStatusArea] = ""]], {5}]],
                fb, paragraphs, paraIdxs],
              iDocGenerateBibCell[nb, enrichedDB];
              Quiet[CurrentValue[nb, WindowStatusArea] =
                iL["自動引用完了", "Auto-cite done"]];
              RunScheduledTask[With[{pNb = nb},
                Quiet[CurrentValue[pNb, WindowStatusArea] = ""]], {5}]]],
          {3}]],
      fb]
  ];

iDocAutoInsertCitationsAction[] :=
  Module[{nb = iDocUserNotebook[]},
    If[Head[nb] =!= NotebookObject,
      MessageDialog[iL["ノートブックが見つかりません。", "No notebook found."]];
      Return[$Failed]];
    DocAutoInsertCitations[nb]
  ];

DocExportLaTeX[nb_NotebookObject, opts:OptionsPattern[]] :=
  Module[{outDir, nCells, lines = {}, imgCounter = 1,
          result, line, outFile, baseName, header, footer,
          figTable, bibTable, bibLines, styleRemap, mathFmt, mathCount = 0,
          exportLang},
    mathFmt = TrueQ[OptionValue["MathFormat"]];
    outDir = iDocEnsureExportDir[nb, "LaTeX"];
    If[outDir === $Failed,
      MessageDialog[iL[
        "ノートブックのディレクトリを取得できません。\n先にノートブックを保存してください。",
        "Cannot get notebook directory.\nPlease save the notebook first."]];
      Return[$Failed]];
    baseName = iDocNotebookBaseName[nb];
    NBAccess`NBInvalidateCellsCache[nb];
    nCells = NBAccess`NBCellCount[nb];

    (* エクスポート言語を検出 *)
    exportLang = iDocDetectExportLanguage[nb];

    (* 図テーブル・参考文献・スタイル読み替えを構築 *)
    figTable = iDocBuildFigureTable[nb];
    bibTable = iDocCollectBibliography[nb];
    styleRemap = iDocParseStyleRemap[nb];

    Quiet[CurrentValue[nb, WindowStatusArea] =
      iL["LaTeX エクスポート中...", "Exporting LaTeX..."]];

    Do[
      Quiet[CurrentValue[nb, WindowStatusArea] =
        If[mathFmt,
          iL["エクスポート中 (数式最適化): ", "Exporting (math): "] <>
            ToString[i] <> "/" <> ToString[nCells],
          iL["エクスポート中: ", "Exporting: "] <>
            ToString[i] <> "/" <> ToString[nCells]]];
      {line, imgCounter} = iDocCellToExport[nb, i, outDir, imgCounter, "latex",
        figTable, bibTable, styleRemap, exportLang];
      If[line =!= Null && StringQ[line] && StringTrim[line] =!= "",
        (* 数式最適化: テキスト行のみ対象（コードブロック・figure環境は除外） *)
        If[mathFmt &&
           !StringStartsQ[line, "\\begin{lstlisting}"] &&
           !StringStartsQ[line, "\\begin{verbatim}"] &&
           !StringStartsQ[line, "\\begin{figure}"] &&
           !StringStartsQ[line, "\\["] &&
           StringLength[line] > 20,
          line = iDocLaTeXifyMath[line,
            iDocExtractCellPDFContext[nb, i]];
          mathCount++];
        AppendTo[lines, line]],
    {i, nCells}];

    If[mathFmt && mathCount > 0,
      Quiet[CurrentValue[nb, WindowStatusArea] =
        iL[ToString[mathCount] <> " セルの数式を最適化しました。",
           ToString[mathCount] <> " cells math-formatted."]]];

    (* 参考文献セクションの出力: Bibliography セル + refSources を統合 *)
    Module[{bibFromRefs, mergedBib = bibTable},
      bibFromRefs = iDocBuildBibFromRefSources[nb];
      Do[If[!KeyExistsQ[mergedBib, key], mergedBib[key] = bibFromRefs[key]],
        {key, Keys[bibFromRefs]}];
      (* 翻訳モードなら日本語タイトルを翻訳 *)
      If[exportLang =!= "source",
        Do[mergedBib[key] = iDocTranslateBibTitle[mergedBib[key], exportLang],
          {key, Keys[mergedBib]}]];
      If[Length[mergedBib] > 0,
        bibLines = {"\\begin{thebibliography}{99}"};
        Do[
          AppendTo[bibLines,
            "\\bibitem{" <> key <> "} " <>
            mergedBib[key]["Author"] <> " (" <> mergedBib[key]["Year"] <> "). " <>
            mergedBib[key]["Title"] <> "."],
        {key, Keys[mergedBib]}];
        AppendTo[bibLines, "\\end{thebibliography}"];
        AppendTo[lines, StringRiffle[bibLines, "\n"]]]];

    (* LaTeX ヘッダー・フッター *)
    header = "\\documentclass[a4paper,11pt]{article}\n" <>
      "\\usepackage[utf8]{inputenc}\n" <>
      "\\usepackage{amsmath,amssymb,amsfonts}\n" <>
      "\\usepackage{graphicx}\n" <>
      "\\usepackage{hyperref}\n" <>
      "\\usepackage{listings}\n" <>
      "\\usepackage[margin=2.5cm]{geometry}\n" <>
      "\\usepackage{CJKutf8}\n" <>
      "\\lstset{basicstyle=\\ttfamily\\small,breaklines=true,frame=single,\n" <>
      "  columns=fullflexible,keepspaces=true}\n" <>
      "\n\\begin{document}\n" <>
      "\\begin{CJK}{UTF8}{min}\n";
    footer = "\n\\end{CJK}\n\\end{document}\n";

    (* ファイル出力 *)
    outFile = FileNameJoin[{outDir, baseName <> ".tex"}];
    Module[{body = StringRiffle[lines, "\n\n"]},
      body = iDocPostProcessLaTeXLists[body];
      Export[outFile, header <> body <> footer,
        "Text", CharacterEncoding -> "UTF-8"]];

    Quiet[CurrentValue[nb, WindowStatusArea] =
      iL["LaTeX エクスポート完了: " <> outFile,
         "LaTeX export complete: " <> outFile]];
    RunScheduledTask[With[{pNb = nb},
      Quiet[CurrentValue[pNb, WindowStatusArea] = ""]], {5}];

    outFile
  ];

(* Word (.docx) エクスポート: Markdown → Pandoc → .docx *)

DocExportWord[nb_NotebookObject, opts:OptionsPattern[]] :=
  Module[{mdFile, outDir, baseName, docxFile, refDoc, pandocArgs, result,
          mathFmt},
    mathFmt = TrueQ[OptionValue["MathFormat"]];
    (* まず Markdown エクスポートを実行（数式オプションを伝搬） *)
    mdFile = DocExportMarkdown[nb, "MathFormat" -> mathFmt];
    If[!StringQ[mdFile] || !FileExistsQ[mdFile],
      MessageDialog[iL[
        "Markdown エクスポートに失敗しました。",
        "Markdown export failed."]];
      Return[$Failed]];

    outDir = DirectoryName[mdFile];
    baseName = FileBaseName[mdFile];
    docxFile = FileNameJoin[{outDir, baseName <> ".docx"}];
    refDoc = OptionValue["ReferenceDoc"];

    (* Pandoc の存在確認 *)
    result = Quiet[RunProcess[{"pandoc", "--version"}, "ExitCode"]];
    If[result =!= 0,
      MessageDialog[iL[
        "Pandoc が見つかりません。\n" <>
        "インストール: https://pandoc.org/installing.html\n" <>
        "macOS: brew install pandoc\n" <>
        "Windows: choco install pandoc",
        "Pandoc not found.\n" <>
        "Install: https://pandoc.org/installing.html\n" <>
        "macOS: brew install pandoc\n" <>
        "Windows: choco install pandoc"]];
      Return[$Failed]];

    (* Pandoc コマンド構築: 作業ディレクトリを画像フォルダに設定 *)
    pandocArgs = {
      "pandoc",
      FileNameTake[mdFile],  (* 相対パスで指定 *)
      "-o", FileNameTake[docxFile],
      "--from=markdown+implicit_figures"
    };
    If[StringQ[refDoc] && FileExistsQ[refDoc],
      AppendTo[pandocArgs, "--reference-doc=" <> refDoc]];

    Quiet[CurrentValue[nb, WindowStatusArea] =
      iL["Word 変換中...", "Converting to Word..."]];

    result = RunProcess[pandocArgs, ProcessDirectory -> outDir];
    If[result["ExitCode"] === 0 && FileExistsQ[docxFile],
      Quiet[CurrentValue[nb, WindowStatusArea] =
        iL["Word エクスポート完了: " <> docxFile,
           "Word export complete: " <> docxFile]];
      RunScheduledTask[With[{pNb = nb},
        Quiet[CurrentValue[pNb, WindowStatusArea] = ""]], {5}];
      docxFile,
      (* エラー *)
      MessageDialog[iL[
        "Pandoc 変換エラー:\n" <> result["StandardError"],
        "Pandoc conversion error:\n" <> result["StandardError"]]];
      Quiet[CurrentValue[nb, WindowStatusArea] = ""];
      $Failed]
  ];

(* パレットからのエクスポートアクション *)
iDocExportMarkdownAction[] :=
  Module[{nb = iDocUserNotebook[]},
    If[Head[nb] =!= NotebookObject,
      MessageDialog[iL["ノートブックが見つかりません。", "No notebook found."]];
      Return[$Failed]];
    DocExportMarkdown[nb]
  ];

iDocExportLaTeXAction[] :=
  Module[{nb = iDocUserNotebook[]},
    If[Head[nb] =!= NotebookObject,
      MessageDialog[iL["ノートブックが見つかりません。", "No notebook found."]];
      Return[$Failed]];
    DocExportLaTeX[nb]
  ];

iDocExportLaTeXMathAction[] :=
  Module[{nb = iDocUserNotebook[]},
    If[Head[nb] =!= NotebookObject,
      MessageDialog[iL["ノートブックが見つかりません。", "No notebook found."]];
      Return[$Failed]];
    DocExportLaTeX[nb, "MathFormat" -> True]
  ];

iDocExportWordAction[] :=
  Module[{nb = iDocUserNotebook[]},
    If[Head[nb] =!= NotebookObject,
      MessageDialog[iL["ノートブックが見つかりません。", "No notebook found."]];
      Return[$Failed]];
    DocExportWord[nb]
  ];

iDocExportWordMathAction[] :=
  Module[{nb = iDocUserNotebook[]},
    If[Head[nb] =!= NotebookObject,
      MessageDialog[iL["ノートブックが見つかりません。", "No notebook found."]];
      Return[$Failed]];
    DocExportWord[nb, "MathFormat" -> True]
  ];

iDocInsertNoteAction[] :=
  Module[{nb = iDocUserNotebook[]},
    If[Head[nb] =!= NotebookObject,
      MessageDialog[iL["ノートブックが見つかりません。", "No notebook found."]];
      Return[$Failed]];
    DocInsertNote[nb]
  ];

iDocInsertDictionaryAction[] :=
  Module[{nb = iDocUserNotebook[]},
    If[Head[nb] =!= NotebookObject,
      MessageDialog[iL["ノートブックが見つかりません。", "No notebook found."]];
      Return[$Failed]];
    DocInsertDictionary[nb]
  ];

iDocInsertDirectiveAction[] :=
  Module[{nb = iDocUserNotebook[]},
    If[Head[nb] =!= NotebookObject,
      MessageDialog[iL["ノートブックが見つかりません。", "No notebook found."]];
      Return[$Failed]];
    DocInsertDirective[nb]
  ];

(* ============================================================
   パレット設定
   ============================================================ *)

(* ============================================================
   メインパレット
   ============================================================ *)

ShowDocPalette[] := (
  If[$docPalette =!= None, Quiet@NotebookClose[$docPalette]];
  Module[{initNb = Quiet[InputNotebook[]]},
    If[Head[initNb] === NotebookObject,
      ClaudeCode`LoadPaletteSettings[initNb]]];
  $iDocLastPaletteNb = None;
  $docPalette = Quiet[CreatePalette[
    Dynamic[
      Module[{curNb = Quiet[InputNotebook[]]},
        If[Head[curNb] === NotebookObject &&
           Quiet[CurrentValue[curNb, WindowClickSelect]] =!= False &&
           curNb =!= $iDocLastPaletteNb,
          $iDocLastPaletteNb = curNb;
          ClaudeCode`LoadPaletteSettings[curNb]]];
    Column[{
      Style["Documentation", Bold, 11, RGBColor[0.2, 0.5, 0.3]],

      (* -- 執筆ツール -- *)
      Style[iL[" 執筆ツール", " Writing Tools"], Bold, 8, GrayLevel[0.3]],
      iDocButtonRow[
        iDocButton2[iL["展開", "Expand"],
          RGBColor[0.2, 0.55, 0.35], iDocExpandSelected[]],
        iDocButton2[iL["\[Times]展開", "\[Times]Exp"],
          RGBColor[0.6, 0.35, 0.35], iDocDeleteExpandSelected[]]],
      iDocButtonRow[
        iDocButton2[iL["翻訳", "Translate"],
          RGBColor[0.3, 0.4, 0.65], iDocTranslateSelected[]],
        iDocButton2[iL["\[Times]翻訳", "\[Times]Tr"],
          RGBColor[0.6, 0.35, 0.35], iDocDeleteTranslateSelected[]]],
      iDocButtonRow[
        iDocButton2[iL["計算", "Compute"],
          RGBColor[0.7, 0.4, 0.2], iDocComputeSelected[]],
        iDocButton2[iL["\[Times]計算", "\[Times]Cmp"],
          RGBColor[0.6, 0.35, 0.35], iDocDeleteComputeSelected[]]],
      iDocButtonRow[
        iDocButton2[iL["分割", "Split"],
          RGBColor[0.5, 0.45, 0.35], iDocSplitCell[]],
        iDocButton2[iL["合併", "Merge"],
          RGBColor[0.4, 0.5, 0.35], iDocMergeCells[]]],
      Spacer[3],
      iDocButton[iL["\[LeftRightArrow] 切替", "\[LeftRightArrow] Toggle"],
        RGBColor[0.35, 0.45, 0.65],
        iDocToggleSelected[]],
      Spacer[3],
      iDocButtonRow[
        iDocButton2[iL["メモ", "Note"],
          RGBColor[0.7, 0.63, 0.35], iDocInsertNoteAction[]],
        iDocButton2[iL["指示", "Directive"],
          RGBColor[0.65, 0.35, 0.5], iDocInsertDirectiveAction[]]],
      iDocButtonRow[
        iDocButton2[iL["辞書", "Dict"],
          RGBColor[0.35, 0.65, 0.65], iDocInsertDictionaryAction[]],
        iDocButton2[iL["文献", "Bib"],
          RGBColor[0.4, 0.45, 0.6], iDocInsertBibliographyAction[]]],
      iDocButton[iL["\[FilledSmallSquare] 図メタ", "\[FilledSmallSquare] Fig Meta"],
        RGBColor[0.5, 0.5, 0.4],
        iDocEditFigureMetaAction[]],
      iDocButton[iL["\[RightPointer] 参照挿入", "\[RightPointer] Ref Insert"],
        RGBColor[0.45, 0.45, 0.55],
        iDocInsertReferenceAction[]],
      iDocButton[iL["\[FilledSmallSquare] 依存資料", "\[FilledSmallSquare] Ref Src"],
        RGBColor[0.45, 0.4, 0.5],
        iDocEditRefSourcesAction[]],
      iDocButton[iL["\[RightPointer] 自動引用", "\[RightPointer] Auto Cite"],
        RGBColor[0.4, 0.4, 0.6],
        iDocAutoInsertCitationsAction[]],
      Spacer[1],

      (* -- 一括表示切替 -- *)
      Style[iL[" 一括表示", " View All"], Bold, 8, GrayLevel[0.3]],
      iDocButton[iL["\[Ellipsis] 全プロンプト", "\[Ellipsis] All Prompts"],
        RGBColor[0.65, 0.5, 0.2],
        iDocShowAllAs["idea"]],
      iDocButton[iL["\[Paragraph] 全パラグラフ", "\[Paragraph] All Paragraphs"],
        RGBColor[0.25, 0.5, 0.4],
        iDocShowAllAs["paragraph"]],
      iDocButton[iL["\[CapitalAHat] 全翻訳", "\[CapitalAHat] All Translations"],
        RGBColor[0.3, 0.4, 0.65],
        iDocTranslateAllAndShow[]],
      Spacer[1],

      (* -- エクスポート -- *)
      Style[iL[" エクスポート", " Export"], Bold, 8, GrayLevel[0.3]],
      iDocButton[iL["\[RightArrowBar] Markdown", "\[RightArrowBar] Markdown"],
        RGBColor[0.3, 0.5, 0.55],
        iDocExportMarkdownAction[]],
      iDocButtonRow[
        iDocButton2[iL["LaTeX", "LaTeX"],
          RGBColor[0.4, 0.4, 0.55], iDocExportLaTeXAction[]],
        iDocButton2[iL["+Math", "+Math"],
          RGBColor[0.45, 0.35, 0.55], iDocExportLaTeXMathAction[]]],
      iDocButtonRow[
        iDocButton2[iL["Word", "Word"],
          RGBColor[0.3, 0.45, 0.6], iDocExportWordAction[]],
        iDocButton2[iL["+Math", "+Math"],
          RGBColor[0.35, 0.35, 0.6], iDocExportWordMathAction[]]],
      iDocButton[iL["\[Times] 除外切替", "\[Times] Excl Toggle"],
        RGBColor[0.6, 0.35, 0.35],
        iDocToggleExportExclude[]],
      Spacer[1],

      (* -- 設定 -- *)
      Style[iL[" 設定", " Settings"], Bold, 8, GrayLevel[0.3]],
      Dynamic[
        Button[
          Style[iL["モデル: ", "Model: "] <>
            Switch[ClaudeCode`GetPaletteModel[],
              "opus", "Opus", "sonnet", "Sonnet", _, "Default"],
            9, Bold, GrayLevel[0.2]],
          Module[{newModel},
            newModel = Switch[ClaudeCode`GetPaletteModel[],
              "default", "opus", "opus", "sonnet", "sonnet", "default", _, "default"];
            ClaudeCode`SetPaletteModel[newModel];
            ClaudeCode`SetPaletteEffort["medium"];
            ClaudeCode`SavePaletteSettings[InputNotebook[]]],
          Appearance -> "Frameless"]],
      Dynamic[
        Button[
          Style[iL["エフォート: ", "Effort: "] <>
            Switch[ClaudeCode`GetPaletteEffort[],
              "low", "Low", "medium", "Medium", "high", "High", "max", "Max", _, "Medium"],
            9, Bold, GrayLevel[0.2]],
          If[ClaudeCode`GetPaletteModel[] =!= "sonnet",
            Module[{newEffort},
              newEffort = Switch[ClaudeCode`GetPaletteEffort[],
                "low", "medium", "medium", "high", "high", "max", "max", "low", _, "medium"];
              ClaudeCode`SetPaletteEffort[newEffort];
              ClaudeCode`SavePaletteSettings[InputNotebook[]]]],
          Appearance -> "Frameless"]],
      Dynamic[
        Button[
          Style[iL["課金API: ", "Paid API: "] <>
            If[ClaudeCode`GetPaletteFallback[],
              iL["許可", "On"],
              iL["禁止", "Off"]],
            9, Bold, GrayLevel[0.2]],
          (ClaudeCode`SetPaletteFallback[!ClaudeCode`GetPaletteFallback[]];
           ClaudeCode`SavePaletteSettings[InputNotebook[]]),
          Appearance -> "Frameless"]],
      Spacer[1],

      (* -- ステータス -- *)
      Dynamic[
        With[{nb = InputNotebook[]},
          Style[
            If[Head[nb] === NotebookObject,
              Module[{n = NBAccess`NBCellCount[nb], expanded = 0, ideas = 0, translated = 0, m, st},
                Do[
                  m = NBAccess`NBCellGetTaggingRule[nb, i, $iDocTagMode];
                  st = NBAccess`NBCellGetTaggingRule[nb, i, $iDocTagShowTranslation];
                  Which[
                    m === "paragraph", expanded++,
                    m === "idea", ideas++,
                    m === "translated", translated++];
                  If[TrueQ[st], translated++],
                {i, n}];
                iL[" \:5c55: ", " E: "] <> ToString[expanded] <>
                iL[" \:30a2: ", " I: "] <> ToString[ideas] <>
                If[translated > 0,
                  iL[" \:8a33: ", " T: "] <> ToString[translated], ""]],
              ""],
            8, GrayLevel[0.4]]]]

    }, Alignment -> Center, Spacings -> 0],
    TrackedSymbols :> {},
    UpdateInterval -> 2
    ],
    WindowTitle -> "Documentation",
    WindowSize -> {105, All},
    WindowFloating -> True,
    WindowClickSelect -> False,
    WindowMargins -> {{Automatic, 113}, {Automatic, 4}},
    Saveable -> False
  ], General::newsym]
);

(* Job システムのアンカーを対象セル直後に配置する。
   ClaudeQueryAsync → iBeginJobAtCapturedCell → NBBeginJob が
   $iCurrentEvalCell を参照してアンカー位置を決定する。
   未設定だと SelectionMove[nb, After, Notebook] でノートブック末尾にジャンプし
   ちらつきが発生するため、LLM 呼び出し前に必ずこれを呼ぶ。 *)
iDocSetJobAnchorCell[nb_NotebookObject, cellIdx_Integer] :=
  Module[{cell},
    cell = NBAccess`NBResolveCell[nb, cellIdx];
    If[cell =!= $Failed,
      ClaudeCode`Private`$iCurrentEvalCell = cell]];

(* テキストを書き込み、クリーンコピーを保存し、セル選択位置を復元する。
   切替時に編集検出に使う。 *)
iDocComputePromptFn[promptText_String, context_String:""] :=
  context <>
  iL[
    "あなたは Wolfram Language / Mathematica の専門家です。以下のプロンプトに基づいて実行可能なコードを生成してください。\n" <>
    "ルール:\n" <>
    "- 有効な Mathematica / Wolfram Language コードのみを出力する\n" <>
    "- 必要な場合のみ (* ... *) コメントを含める\n" <>
    "- すべてを1つのコードブロックにまとめ、複数に分割しない\n" <>
    "- マークダウン記法、コードフェンス（```）、コード外の説明は一切含めない\n" <>
    "- 出力の最初の文字から最後の文字まで、すべてが直接実行可能なコードでなければならない\n" <>
    "- ファイルを参照する場合は FileNameJoin でパスを構築する\n" <>
    "- グラフや可視化には自己完結した式を生成する\n" <>
    "- ドキュメントコンテキストがある場合は、略語や固有名詞の意味を文脈から判断する\n" <>
    "- Directives（指示）が提供されている場合は、その内容を厳守する\n" <>
    "- リクエストを実行できない場合は、コードではなく (* ERROR: 理由 *) をコメントとして出力する\n\n" <>
    "プロンプト:\n" <> promptText,
    "You are an expert Wolfram Language / Mathematica programmer. " <>
    "Generate executable code based on the following prompt.\n" <>
    "Rules:\n" <>
    "- Output ONLY valid Mathematica / Wolfram Language code\n" <>
    "- Include (* ... *) comments only when necessary for clarity\n" <>
    "- Put everything in a single code block - do NOT split into multiple parts\n" <>
    "- Do NOT include markdown formatting, code fences (```), or explanations outside of code\n" <>
    "- The very first character to the very last must be directly executable code\n" <>
    "- For file references, use FileNameJoin for path construction\n" <>
    "- For plots and visualizations, produce self-contained expressions\n" <>
    "- If document context is provided, use it to disambiguate abbreviations and proper nouns\n" <>
    "- If Directives are provided, strictly follow their instructions\n" <>
    "- If you cannot fulfill the request, output ONLY: (* ERROR: reason *) as a comment\n\n" <>
    "Prompt:\n" <> promptText
  ];

(* LLM 応答からマークダウンコードフェンスを除去する *)
iDocCleanComputeResponse[response_String] :=
  Module[{code = StringTrim[response]},
    code = StringReplace[code,
      RegularExpression["^\\s*```(?:mathematica|wolfram|wl)?\\s*\\n?"] -> ""];
    code = StringReplace[code,
      RegularExpression["\\n?\\s*```\\s*$"] -> ""];
    StringTrim[code]
  ];

(* 計算タグで生成された Input セルを検索する *)
iDocFindComputeCell[nb_NotebookObject, tag_String] :=
  Module[{nCells, val},
    nCells = NBAccess`NBCellCount[nb];
    Do[
      val = NBAccess`NBCellGetTaggingRule[nb, i, $iDocTagComputeSourceTag];
      If[val === tag, Return[i, Module]],
    {i, nCells}];
    0
  ];

(* ============================================================
   コア関数: 計算
   プロンプトテキストから Mathematica コードを生成し、
   セル直後に実行可能な Input セルとして挿入する。
   ============================================================ *)

DocCompute[nb_NotebookObject, cellIdx_Integer, opts:OptionsPattern[]] :=
  Module[{promptText, useFallback, context, directives, dictionary,
          prompt, privLevel, savedScroll, computeTag, syncTag, mode},
    useFallback = TrueQ[OptionValue[Fallback]];
    If[iDocIsMetaCell[nb, cellIdx], Return[$Failed]];

    savedScroll = Quiet[AbsoluteCurrentValue[nb, NotebookAutoScroll]];
    Quiet[SetOptions[nb, NotebookAutoScroll -> False]];

    NBAccess`NBInvalidateCellsCache[nb];
    mode = NBAccess`NBCellGetTaggingRule[nb, cellIdx, $iDocTagMode];

    (* コード表示中のセルには計算を再適用できない（切替でプロンプトに戻してから） *)
    If[mode === "compute",
      Quiet[SetOptions[nb, NotebookAutoScroll -> savedScroll]];
      Quiet[CurrentValue[nb, WindowStatusArea] =
        iL["切替でプロンプトに戻してから計算してください。",
           "Toggle to prompt view before re-computing."]];
      RunScheduledTask[With[{pNb = nb},
        Quiet[CurrentValue[pNb, WindowStatusArea] = ""]], {3}];
      Return[$Failed]];

    (* プロンプトテキスト取得: computePrompt モード時はセルの現在テキスト（編集済み含む） *)
    promptText = NBAccess`NBCellGetText[nb, cellIdx];

    If[!StringQ[promptText] || StringTrim[promptText] === "",
      Quiet[SetOptions[nb, NotebookAutoScroll -> savedScroll]];
      Return[$Failed]];

    (* コンテキスト収集 *)
    directives = iDocCollectDirectives[nb];
    dictionary = iDocCollectDictionary[nb];
    context = directives <> dictionary <> iDocCollectContext[nb, cellIdx];
    prompt = iDocComputePromptFn[promptText, context];

    (* 計算タグ: プロンプトセルと生成 Input セルを紐付ける *)
    computeTag = NBAccess`NBCellGetTaggingRule[nb, cellIdx, $iDocTagComputeTag];
    If[!StringQ[computeTag],
      computeTag = "doc-compute-" <> ToString[UnixTime[]] <> "-" <>
        ToString[RandomInteger[99999]];
      NBAccess`NBCellSetTaggingRule[nb, cellIdx, $iDocTagComputeTag, computeTag]];

    (* 同期タグ: Job セル挿入によるインデックスずれ対策 *)
    syncTag = "doc-csync-" <> ToString[UnixTime[]] <> "-" <>
      ToString[RandomInteger[99999]];
    NBAccess`NBCellSetTaggingRule[nb, cellIdx, {$iDocTagRoot, "syncTag"}, syncTag];

    privLevel = NBAccess`NBCellPrivacyLevel[nb, cellIdx];
    Quiet[CurrentValue[nb, WindowStatusArea] =
      iL["コード生成中...", "Generating code..."]];
    iDocSetJobAnchorCell[nb, cellIdx];

    With[{nb2 = nb, ci = cellIdx, ss = savedScroll,
          stag = syncTag, origPrompt = promptText},
      NBAccess`$NBLLMQueryFunc[prompt,
        Function[response,
          Module[{idx, code},
            NBAccess`NBInvalidateCellsCache[nb2];
            idx = iDocFindSyncTag[nb2, stag];
            If[idx === 0, idx = ci];
            If[StringQ[response] && !StringStartsQ[response, "Error"] &&
               !StringStartsQ[response, "[ERROR]"],
              code = iDocCleanComputeResponse[response];

              (* プロンプトセルを計算モードに切り替え: コード表示、プロンプト保存 *)
              NBAccess`NBCellSetTaggingRule[nb2, idx, $iDocTagAlternate, origPrompt];
              NBAccess`NBCellSetTaggingRule[nb2, idx, $iDocTagComputeCode, code];
              NBAccess`NBCellSetTaggingRule[nb2, idx, $iDocTagMode, "compute"];
              NBAccess`NBCellSetOptions[nb2, idx, Sequence @@ $iDocComputeCellOpts];
              (* NBCellWriteCode が Cell 式全体を Input スタイルで書き換える *)
              iDocWriteCodeAndTrack[nb2, idx, code];
              NBAccess`NBSelectCell[nb2, idx];
              Quiet[CurrentValue[nb2, WindowStatusArea] =
                iL["コード生成完了", "Code generation complete"]],
              (* エラー *)
              Quiet[CurrentValue[nb2, WindowStatusArea] =
                iL["コード生成エラー", "Code generation error"]];
              NBAccess`NBSelectCell[nb2, idx]];
            NBAccess`NBCellSetTaggingRule[nb2, idx,
              {$iDocTagRoot, "syncTag"}, Inherited];
            Quiet[SetOptions[nb2, NotebookAutoScroll -> ss]];
            RunScheduledTask[With[{pNb = nb2},
              Quiet[CurrentValue[pNb, WindowStatusArea] = ""]], {3}]]],
        nb, PrivacyLevel -> privLevel, Fallback -> useFallback]];
    NBAccess`NBSelectCell[nb, cellIdx];
  ];

iDocComputeSelected[] :=
  Module[{nb, cellIdxs},
    {nb, cellIdxs} = iDocResolveTargetCells[];
    If[Length[cellIdxs] === 0,
      MessageDialog[iL["セルを選択してください。", "Please select a cell."]];
      Return[$Failed]];
    If[Length[cellIdxs] === 1,
      DocCompute[nb, First[cellIdxs], Fallback -> ClaudeCode`GetPaletteFallback[]];
      NBAccess`NBSelectCell[nb, First[cellIdxs]],
      iDocComputeSelectedChain[nb, cellIdxs, 1, ClaudeCode`GetPaletteFallback[]]]
  ];

iDocComputeSelectedChain[nb_, idxs_, pos_, fb_] :=
  If[pos > Length[idxs],
    Quiet[CurrentValue[nb, WindowStatusArea] =
      iL[ToString[Length[idxs]] <> " セルのコードを生成しました。",
         ToString[Length[idxs]] <> " cells computed."]];
    RunScheduledTask[With[{pNb = nb},
      Quiet[CurrentValue[pNb, WindowStatusArea] = ""]], {3}],
    Quiet[CurrentValue[nb, WindowStatusArea] =
      iL["コード生成中: ", "Computing: "] <>
        ToString[pos] <> "/" <> ToString[Length[idxs]]];
    Module[{cellIdx = idxs[[pos]]},
      If[iDocIsMetaCell[nb, cellIdx],
        iDocComputeSelectedChain[nb, idxs, pos + 1, fb],
        DocCompute[nb, cellIdx, Fallback -> fb];
        RunScheduledTask[
          With[{pNb = nb, is = idxs, p = pos, f = fb},
            iDocComputeSelectedChain[pNb, is, p + 1, f]], {2}]]]
  ];

(* 選択セルから計算結果を削除し、プロンプト状態に復元する *)
iDocDeleteComputeSelected[] :=
  Module[{nb, cellIdxs},
    {nb, cellIdxs} = iDocResolveTargetCells[];
    If[Length[cellIdxs] === 0,
      MessageDialog[iL["セルを選択してください。", "Please select a cell."]];
      Return[$Failed]];
    If[ChoiceDialog[
        iL["選択セルの計算結果を削除しますか？\nこの操作は元に戻せません。",
           "Delete compute results from selected cell(s)?\nThis cannot be undone."],
        {iL["削除", "Delete"] -> True, iL["キャンセル", "Cancel"] -> False},
        WindowTitle -> iL["確認", "Confirm"]],
      Do[
        Module[{currentMode, origPrompt},
          NBAccess`NBInvalidateCellsCache[nb];
          currentMode = NBAccess`NBCellGetTaggingRule[nb, idx, $iDocTagMode];
          If[currentMode === "compute" || currentMode === "computePrompt",
            origPrompt = NBAccess`NBCellGetTaggingRule[nb, idx, $iDocTagAlternate];
            (* computePrompt の場合、セルの現在テキストがプロンプト *)
            If[!StringQ[origPrompt] || StringTrim[origPrompt] === "",
              origPrompt = NBAccess`NBCellGetText[nb, idx]];
            (* タグをクリア（Cell 式書き換え前に実施） *)
            NBAccess`NBCellSetTaggingRule[nb, idx, $iDocTagMode, Inherited];
            NBAccess`NBCellSetTaggingRule[nb, idx, $iDocTagAlternate, Inherited];
            NBAccess`NBCellSetTaggingRule[nb, idx, $iDocTagComputeCode, Inherited];
            NBAccess`NBCellSetTaggingRule[nb, idx, $iDocTagCleanText, Inherited];
            NBAccess`NBCellSetTaggingRule[nb, idx, $iDocTagCleanMode, Inherited];
            (* CellFrame/CellFrameColor をクリア *)
            NBAccess`NBCellSetOptions[nb, idx,
              CellFrame -> Inherited, CellFrameColor -> Inherited];
            (* テキストとスタイルを復元（Cell 式全体を書き換え） *)
            NBAccess`NBCellWriteText[nb, idx,
              If[StringQ[origPrompt], origPrompt, ""]];
            NBAccess`NBInvalidateCellsCache[nb];
            NBAccess`NBCellSetStyle[nb, idx, "Text"]];
          NBAccess`NBCellSetTaggingRule[nb, idx, $iDocTagComputeTag, None]],
      {idx, Reverse[cellIdxs]}]]
  ];
$iDocTagComputeTag = {$iDocTagRoot, "computeTag"};
$iDocTagComputeSourceTag = {$iDocTagRoot, "computeSourceTag"};
$iDocTagComputeCode = {$iDocTagRoot, "computeCode"};

(* 計算表示モード: 左側にオレンジの枠線 *)
$iDocComputeCellOpts = {
  CellFrame      -> {{3, 0}, {0, 0}},
  CellFrameColor -> RGBColor[0.7, 0.4, 0.2]
};

(* コードを Input スタイルで書き込み、編集追跡用クリーンコピーを保存する。 *)
iDocWriteCodeAndTrack[nb_NotebookObject, cellIdx_Integer, code_String] :=
  Module[{savedScroll},
    savedScroll = Quiet[AbsoluteCurrentValue[nb, NotebookAutoScroll]];
    Quiet[SetOptions[nb, NotebookAutoScroll -> False]];
    NBAccess`NBInvalidateCellsCache[nb];
    NBAccess`NBCellWriteCode[nb, cellIdx, code];
    NBAccess`NBCellSetTaggingRule[nb, cellIdx, $iDocTagCleanText, code];
    NBAccess`NBCellSetTaggingRule[nb, cellIdx, $iDocTagCleanMode,
      ToString[NBAccess`NBCellGetTaggingRule[nb, cellIdx, $iDocTagMode]] <> ":" <>
      ToString[TrueQ[NBAccess`NBCellGetTaggingRule[nb, cellIdx, $iDocTagShowTranslation]]]];
    NBAccess`NBSelectCell[nb, cellIdx];
    Quiet[SetOptions[nb, NotebookAutoScroll -> savedScroll]]];







End[];
EndPackage[];

(* パッケージロード時にパレットを自動表示 *)
Documentation`ShowDocPalette[];

(* パレットメニューに登録（claudecode.wl の AddToPalettesMenu と同じパターン） *)
Module[{itemList, dummyFunction, tempFunction, temp},
  SetAttributes[FrontEnd`AddMenuCommands, HoldRest];
  MathLink`CallFrontEnd[FrontEnd`ResetMenusPacket[{Automatic}]];
  itemList = {
    Item["Documentation",
      FrontEnd`KernelExecute[{EvaluatePacket[
        dummyFunction["Needs[\"Documentation`\"]; Documentation`ShowDocPalette[]"]]}],
      FrontEnd`MenuEvaluator -> Automatic]};
  temp = Function[x,
    tempFunction[{FrontEnd`AddMenuCommands["MenuListPalettesMenu",
      x]}]][itemList] /. dummyFunction -> ToExpression;
  temp /. tempFunction -> FrontEndExecute];