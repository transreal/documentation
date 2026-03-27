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
  "既にパラグラフ表示中の場合は保存済みアイデアから再展開する。\n" <>
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

DocExportMarkdown::usage =
  "DocExportMarkdown[nb] はノートブックを Markdown 形式でエクスポートする。\n" <>
  "出力先: NotebookDirectory[] / <ノートブック名>_md/\n" <>
  "Note スタイルのセルは出力から除外される。\n" <>
  "画像: ラスター→PNG, ベクター/計算結果→PDF で保存。\n" <>
  "Input セルはコードブロック、数式は TeX に変換される。";

DocExportLaTeX::usage =
  "DocExportLaTeX[nb] はノートブックを LaTeX 形式でエクスポートする。\n" <>
  "出力先: NotebookDirectory[] / <ノートブック名>_LaTeX/\n" <>
  "Note スタイルのセルは出力から除外される。\n" <>
  "画像: ラスター→PNG, ベクター/計算結果→PDF で保存。\n" <>
  "Input セルはコードブロック、数式は TeX に変換される。";

ShowDocPalette::usage =
  "ShowDocPalette[] はドキュメント作成用パレットを表示する。";

$DocTranslationLanguage::usage =
  "$DocTranslationLanguage は翻訳先の言語名。\n" <>
  "デフォルト: $Language が英語以外なら \"English\"、英語なら \"Japanese\"。\n" <>
  "ユーザーが任意の言語名に変更可能。\n" <>
  "例: $DocTranslationLanguage = \"French\"";

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

iDocExpandPromptFn[ideaText_String, context_String:""] :=
  context <>
  iL[
    "あなたは熟練したライターです。以下の短いアイデアやフレーズを、" <>
    "よく練られた段落に発展させてください。\n" <>
    "ルール:\n" <>
    "- 元の意味と意図を忠実に保つ\n" <>
    "- 深み、明確さ、プロフェッショナルな文章品質を加える\n" <>
    "- 出力言語: " <> iDocOutputLanguage[] <> "\n" <>
    "- 段落のテキストのみを出力し、それ以外（前置きや説明）は一切出力しない\n" <>
    "- マークダウン記法は使わない\n" <>
    "- ドキュメントコンテキストがある場合は、略語や固有名詞の意味を文脈から判断する\n" <>
    "- リクエストを実行できない場合（ファイル未検出・情報不足等）は、段落ではなく [ERROR]: に続けて理由を出力する\n\n" <>
    "アイデア:\n" <> ideaText,
    "You are a skilled writer. Develop the following brief idea or phrase " <>
    "into a well-crafted paragraph.\n" <>
    "Rules:\n" <>
    "- Maintain the original meaning and intent faithfully\n" <>
    "- Add depth, clarity, and professional quality prose\n" <>
    "- Output language: " <> iDocOutputLanguage[] <> "\n" <>
    "- Output ONLY the paragraph text, nothing else (no preamble or explanation)\n" <>
    "- Do not use markdown formatting\n" <>
    "- If document context is provided, use it to disambiguate abbreviations and proper nouns\n" <>
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
    "- 段落のテキストのみを出力し、それ以外（前置きや説明）は一切出力しない\n" <>
    "- マークダウン記法は使わない\n" <>
    "- ドキュメントコンテキストがある場合は、略語や固有名詞の意味を文脈から判断する\n" <>
    "- リクエストを実行できない場合（ファイル未検出・情報不足等）は、段落ではなく [ERROR]: に続けて理由を出力する\n\n" <>
    "修正されたアイデア:\n" <> ideaText <>
    "\n\n以前の段落:\n" <> prevParagraph,
    "You are a skilled writer. Revise the 'Previous paragraph' based on " <>
    "the 'Updated idea' below.\n" <>
    "Rules:\n" <>
    "- Preserve the style, structure, and user edits of the previous paragraph as much as possible\n" <>
    "- Update only the parts that need to change according to the updated idea\n" <>
    "- Output language: " <> iDocOutputLanguage[] <> "\n" <>
    "- Output ONLY the paragraph text, nothing else (no preamble or explanation)\n" <>
    "- Do not use markdown formatting\n" <>
    "- If document context is provided, use it to disambiguate abbreviations and proper nouns\n" <>
    "- If you cannot fulfill the request (file not found, insufficient info, etc.), output ONLY: [ERROR]: followed by the reason\n\n" <>
    "Updated idea:\n" <> ideaText <>
    "\n\nPrevious paragraph:\n" <> prevParagraph
  ];

(* ============================================================
   コア関数: アイデア展開
   全セル内容アクセスは NBAccess 経由。LLM は NBCellTransformWithLLM 経由。

   動作モード:
   - mode 未設定（初回）: アイデア → パラグラフに展開
   - mode === "idea"（プロンプト表示中）:
     保存済みパラグラフがあれば再展開（修正アイデア + 旧パラグラフを渡す）
     なければ初回展開と同じ
   - mode === "paragraph"（パラグラフ表示中）: 展開を禁止
   ============================================================ *)

Options[DocExpandIdea] = {Fallback -> False};

DocExpandIdea[nb_NotebookObject, cellIdx_Integer, opts:OptionsPattern[]] :=
  Module[{mode, prevParagraph, useFallback, promptFn, context},
    useFallback = TrueQ[OptionValue[Fallback]];

    (* Note セルは対象外 *)
    If[iDocIsNoteCell[nb, cellIdx], Return[$Failed]];

    (* 現在のモード確認 (NBAccess 経由) *)
    mode = NBAccess`NBCellGetTaggingRule[nb, cellIdx, $iDocTagMode];

    (* パラグラフ表示中 → 展開禁止 *)
    If[mode === "paragraph",
      MessageDialog[iL[
        "パラグラフモードでは展開できません。\n" <>
        "先に「切替」でプロンプトモードに戻してから、プロンプトを修正して再展開してください。",
        "Cannot expand in paragraph mode.\n" <>
        "Switch to idea mode first, edit the prompt, then expand again."]];
      Return[$Failed]];

    (* ノートブックコンテキスト収集: 周辺セル + アタッチメント情報 *)
    context = iDocCollectContext[nb, cellIdx];

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
    With[{nb2 = nb},
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
                Sequence @@ $iDocParagraphCellOpts]],
            (* エラー *)
            MessageDialog[iL[
              "エラー: LLM 応答を取得できませんでした。",
              "Error: Could not get LLM response."]]]],
        Fallback -> useFallback]
    ];
  ];

(* ============================================================
   コア関数: トグル表示
   ============================================================ *)

DocToggleView[nb_NotebookObject, cellIdx_Integer] :=
  Module[{currentText, mode, alternate, newMode, showTrans, transSrc,
          storedTranslation},
    (* Note セルは対象外 *)
    If[iDocIsNoteCell[nb, cellIdx], Return[$Failed]];
    NBAccess`NBInvalidateCellsCache[nb];
    mode = NBAccess`NBCellGetTaggingRule[nb, cellIdx, $iDocTagMode];
    showTrans = NBAccess`NBCellGetTaggingRule[nb, cellIdx, $iDocTagShowTranslation];

    (* ========================================================
       翻訳付きセル (mode="translated"): 元テキスト ↔ 翻訳
       ======================================================== *)
    If[mode === "translated",
      If[TrueQ[showTrans],
        (* 翻訳表示中 → 元テキストに戻す（水色枠） *)
        transSrc = NBAccess`NBCellGetTaggingRule[nb, cellIdx, $iDocTagTranslationSrc];
        If[StringQ[transSrc],
          NBAccess`NBCellSetTaggingRule[nb, cellIdx,
            $iDocTagTranslation, NBAccess`NBCellGetText[nb, cellIdx]];
          NBAccess`NBCellSetTaggingRule[nb, cellIdx, $iDocTagShowTranslation, False];
          NBAccess`NBCellSetOptions[nb, cellIdx,
            Sequence @@ $iDocTranslatedCellOpts];
          NBAccess`NBInvalidateCellsCache[nb];
          NBAccess`NBCellWriteText[nb, cellIdx, transSrc];],
        (* 元テキスト表示中 → 翻訳を表示（青枠） *)
        storedTranslation = NBAccess`NBCellGetTaggingRule[nb, cellIdx, $iDocTagTranslation];
        If[StringQ[storedTranslation] && StringTrim[storedTranslation] =!= "",
          NBAccess`NBCellSetTaggingRule[nb, cellIdx,
            $iDocTagTranslationSrc, NBAccess`NBCellGetText[nb, cellIdx]];
          NBAccess`NBCellSetTaggingRule[nb, cellIdx, $iDocTagShowTranslation, True];
          NBAccess`NBCellSetOptions[nb, cellIdx,
            Sequence @@ $iDocTranslationCellOpts];
          NBAccess`NBInvalidateCellsCache[nb];
          NBAccess`NBCellWriteText[nb, cellIdx, storedTranslation];]];
      Return[]];

    (* ========================================================
       翻訳表示中 (paragraph モード): 翻訳 → アイデアに戻す
       ======================================================== *)
    If[TrueQ[showTrans],
      transSrc = NBAccess`NBCellGetTaggingRule[nb, cellIdx, $iDocTagTranslationSrc];
      If[StringQ[transSrc],
        NBAccess`NBCellSetTaggingRule[nb, cellIdx,
          $iDocTagTranslation, NBAccess`NBCellGetText[nb, cellIdx]];
        NBAccess`NBCellSetTaggingRule[nb, cellIdx, $iDocTagShowTranslation, False]];
      alternate = NBAccess`NBCellGetTaggingRule[nb, cellIdx, $iDocTagAlternate];
      If[mode === "paragraph" && StringQ[alternate],
        NBAccess`NBCellSetTaggingRule[nb, cellIdx, $iDocTagAlternate,
          If[StringQ[transSrc], transSrc,
            NBAccess`NBCellGetText[nb, cellIdx]]];
        NBAccess`NBCellSetTaggingRule[nb, cellIdx, $iDocTagMode, "idea"];
        NBAccess`NBCellSetOptions[nb, cellIdx,
          Sequence @@ $iDocIdeaCellOpts];
        NBAccess`NBInvalidateCellsCache[nb];
        NBAccess`NBCellWriteText[nb, cellIdx, alternate];
        Return[alternate]];
      (* fallback: 翻訳元を復元 *)
      If[StringQ[transSrc],
        NBAccess`NBCellSetOptions[nb, cellIdx,
          CellFrame -> Inherited, CellFrameColor -> Inherited];
        NBAccess`NBInvalidateCellsCache[nb];
        NBAccess`NBCellWriteText[nb, cellIdx, transSrc];];
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
        NBAccess`NBInvalidateCellsCache[nb];
        NBAccess`NBCellWriteText[nb, cellIdx, storedTranslation];
        Return[storedTranslation]]];

    (* idea ↔ paragraph の2段階トグル *)
    NBAccess`NBCellSetTaggingRule[nb, cellIdx, $iDocTagAlternate,
      If[StringQ[currentText], currentText, ""]];
    newMode = If[mode === "paragraph", "idea", "paragraph"];
    NBAccess`NBCellSetTaggingRule[nb, cellIdx, $iDocTagMode, newMode];
    NBAccess`NBCellSetOptions[nb, cellIdx,
      Sequence @@ If[newMode === "paragraph",
        $iDocParagraphCellOpts, $iDocIdeaCellOpts]];
    NBAccess`NBInvalidateCellsCache[nb];
    NBAccess`NBCellWriteText[nb, cellIdx, alternate];

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
iDocTranslateAutoPromptFn[text_String, primaryLang_String, alternateLang_String] :=
  "Detect the language of the following text, then translate it.\n" <>
  "- If the text is in " <> primaryLang <> ", translate it into " <> alternateLang <> ".\n" <>
  "- If the text is in any other language, translate it into " <> primaryLang <> ".\n" <>
  "Rules:\n" <>
  "- Produce a natural, fluent translation\n" <>
  "- Preserve the original structure and meaning faithfully\n" <>
  "- Output ONLY the translated text, nothing else\n" <>
  "- Do not use markdown formatting\n" <>
  "- If you cannot fulfill the request, output ONLY: [ERROR]: followed by the reason\n\n" <>
  "Text to translate:\n" <> text;

(* パラグラフ用翻訳プロンプト: 固定ターゲット言語 *)
iDocTranslatePromptFn[text_String, targetLang_String] :=
  "Translate the following text into " <> targetLang <> ".\n" <>
  "Rules:\n" <>
  "- Produce a natural, fluent translation\n" <>
  "- Preserve the original structure and meaning faithfully\n" <>
  "- Output ONLY the translated text, nothing else\n" <>
  "- Do not use markdown formatting\n" <>
  "- If you cannot fulfill the request, output ONLY: [ERROR]: followed by the reason\n\n" <>
  "Text to translate:\n" <> text;

(* 初回翻訳プロンプト（プロンプト参照付き） *)
iDocTranslateWithContextPromptFn[text_String, targetLang_String, ideaText_String] :=
  "Translate the following paragraph into " <> targetLang <> ".\n" <>
  "The paragraph was written based on the 'Original prompt' below. " <>
  "Use it as context to improve translation accuracy.\n" <>
  "Rules:\n" <>
  "- Produce a natural, fluent translation\n" <>
  "- Preserve the original structure and meaning faithfully\n" <>
  "- Output ONLY the translated text, nothing else\n" <>
  "- Do not use markdown formatting\n" <>
  "- If you cannot fulfill the request, output ONLY: [ERROR]: followed by the reason\n\n" <>
  "Original prompt:\n" <> ideaText <>
  "\n\nParagraph to translate:\n" <> text;

(* 再翻訳プロンプト: 既存翻訳のユーザー修正を踏襲しつつ更新 *)
iDocReTranslatePromptFn[text_String, targetLang_String,
    prevTranslation_String, ideaText_String] :=
  "The paragraph below has been updated. Revise the 'Previous translation' accordingly.\n" <>
  If[ideaText =!= "",
    "The 'Original prompt' provides context for what the paragraph is about.\n", ""] <>
  "Rules:\n" <>
  "- Preserve user edits in the previous translation as much as possible\n" <>
  "- Update only the parts that correspond to changes in the paragraph\n" <>
  "- Produce a natural, fluent " <> targetLang <> " translation\n" <>
  "- Output ONLY the revised translation, nothing else\n" <>
  "- Do not use markdown formatting\n" <>
  "- If you cannot fulfill the request, output ONLY: [ERROR]: followed by the reason\n\n" <>
  If[ideaText =!= "",
    "Original prompt:\n" <> ideaText <> "\n\n", ""] <>
  "Updated paragraph:\n" <> text <>
  "\n\nPrevious translation:\n" <> prevTranslation;

DocTranslate[nb_NotebookObject, cellIdx_Integer, opts:OptionsPattern[]] :=
  Module[{currentText, storedTranslation, storedSrc, showTrans,
          mode, targetLang, useFallback, ideaText, promptFn},
    useFallback = TrueQ[OptionValue[Fallback]];
    (* Note セルは対象外 *)
    If[iDocIsNoteCell[nb, cellIdx], Return[$Failed]];
    NBAccess`NBInvalidateCellsCache[nb];

    mode = NBAccess`NBCellGetTaggingRule[nb, cellIdx, $iDocTagMode];
    showTrans = NBAccess`NBCellGetTaggingRule[nb, cellIdx, $iDocTagShowTranslation];

    (* 翻訳不可: プロンプト（アイデア）モード *)
    If[mode === "idea",
      MessageDialog[iL[
        "プロンプトモードでは翻訳できません。\n" <>
        "パラグラフに展開してから翻訳してください。",
        "Cannot translate in idea/prompt mode.\n" <>
        "Expand to paragraph first, then translate."]];
      Return[$Failed]];

    (* 翻訳不可: 翻訳表示中 *)
    If[TrueQ[showTrans],
      MessageDialog[iL[
        "翻訳表示中です。\n" <>
        "「切替」で元テキストに戻してから再翻訳してください。",
        "Currently showing translation.\n" <>
        "Toggle back to original text before re-translating."]];
      Return[$Failed]];

    currentText = NBAccess`NBCellGetText[nb, cellIdx];
    If[!StringQ[currentText] || StringTrim[currentText] === "",
      Return[$Failed]];

    storedTranslation = NBAccess`NBCellGetTaggingRule[nb, cellIdx, $iDocTagTranslation];
    storedSrc = NBAccess`NBCellGetTaggingRule[nb, cellIdx, $iDocTagTranslationSrc];
    targetLang = iDocTranslationTarget[];

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
      Return[]];

    (* プロンプト構築: 既存翻訳の有無で分岐 *)
    promptFn = Which[
      (* 再翻訳: ソースが変わった + 既存翻訳あり → ユーザー修正を踏襲 *)
      StringQ[storedTranslation] && StringTrim[storedTranslation] =!= "",
        With[{prev = storedTranslation, idea = ideaText, tl = targetLang},
          Function[t, iDocReTranslatePromptFn[t, tl, prev, idea]]],
      (* 初回翻訳: プロンプト参照付き（パラグラフモードの場合） *)
      ideaText =!= "",
        With[{idea = ideaText, tl = targetLang},
          Function[t, iDocTranslateWithContextPromptFn[t, tl, idea]]],
      (* 初回翻訳: 普通のセル → 言語自動検出 *)
      True,
        With[{pl = iDocOutputLanguage[], al = iDocTranslationTarget[]},
          Function[t, iDocTranslateAutoPromptFn[t, pl, al]]]
    ];

    (* 非同期翻訳 *)
    With[{nb2 = nb, srcText = currentText,
          isPlain = (!StringQ[mode] || mode === "translated")},
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
                Sequence @@ $iDocTranslationCellOpts]]]],
        Fallback -> useFallback]
    ];
  ];

Options[DocTranslate] = {Fallback -> False};

(* ============================================================
   コア関数: 同期 (Sync)
   プロンプト・パラグラフ・翻訳のうち、現在表示中のテキストを基準として
   他のコンポーネントを LLM で更新する。セル表示は変更しない。

   - プロンプト表示中 (mode="idea"):
     プロンプトから → パラグラフを再生成。翻訳があれば連鎖で再翻訳。
   - パラグラフ表示中 (mode="paragraph"):
     パラグラフから → 翻訳を再生成。
   - 翻訳表示中 (showTranslation=True):
     翻訳から → パラグラフを逆更新。
   ============================================================ *)

(* 翻訳→パラグラフ逆同期プロンプト *)
iDocReverseSyncPromptFn[editedTranslation_String, prevParagraph_String,
    ideaText_String, outputLang_String] :=
  "TASK: The user has edited a translation. Your job is to update the " <>
  "'Original paragraph' so that its MEANING matches the edited translation.\n\n" <>
  "CRITICAL LANGUAGE RULE:\n" <>
  "- The 'Original paragraph' is written in " <> outputLang <> ".\n" <>
  "- The 'Edited translation' is in a DIFFERENT language.\n" <>
  "- You MUST output the updated paragraph in " <> outputLang <> " ONLY.\n" <>
  "- Do NOT output in the translation's language. Do NOT translate the paragraph.\n" <>
  "- The output language must be " <> outputLang <> ".\n\n" <>
  If[ideaText =!= "",
    "The 'Original prompt' provides context for the paragraph.\n\n", ""] <>
  "Rules:\n" <>
  "- Compare the edited translation with the original paragraph to find what changed\n" <>
  "- Update the corresponding parts of the original paragraph IN " <> outputLang <> "\n" <>
  "- Preserve the structure and style of the original paragraph\n" <>
  "- Output ONLY the updated paragraph in " <> outputLang <> ", nothing else\n" <>
  "- Do not use markdown formatting\n" <>
  "- If you cannot fulfill the request, output ONLY: [ERROR]: followed by the reason\n\n" <>
  If[ideaText =!= "",
    "Original prompt:\n" <> ideaText <> "\n\n", ""] <>
  "Original paragraph (" <> outputLang <> "):\n" <> prevParagraph <>
  "\n\nEdited translation (different language — do NOT output in this language):\n" <> editedTranslation;

(* タグからセルインデックスを再検索する。
   Job の進捗セル挿入でインデックスがずれた場合に使用する。 *)
iDocFindSyncTag[nb_NotebookObject, tag_String] :=
  Module[{nCells, val},
    nCells = NBAccess`NBCellCount[nb];
    Do[
      val = NBAccess`NBCellGetTaggingRule[nb, i, {$iDocTagRoot, "syncTag"}];
      If[val === tag, Return[i, Module]],
    {i, nCells}];
    0
  ];

Options[DocSync] = {Fallback -> False};

DocSync[nb_NotebookObject, cellIdx_Integer, opts:OptionsPattern[]] :=
  Module[{mode, showTrans, currentText, useFallback, ideaText, paragraph,
          translation, targetLang, prompt, context, syncTag},
    useFallback = TrueQ[OptionValue[Fallback]];
    (* Note セルは対象外 *)
    If[iDocIsNoteCell[nb, cellIdx], Return[$Failed]];
    NBAccess`NBInvalidateCellsCache[nb];
    mode = NBAccess`NBCellGetTaggingRule[nb, cellIdx, $iDocTagMode];
    showTrans = NBAccess`NBCellGetTaggingRule[nb, cellIdx, $iDocTagShowTranslation];
    currentText = NBAccess`NBCellGetText[nb, cellIdx];
    If[!StringQ[currentText] || StringTrim[currentText] === "",
      Return[$Failed]];

    targetLang = iDocTranslationTarget[];
    context = iDocCollectContext[nb, cellIdx];

    (* セルにタグを付与: Job の進捗セル挿入でインデックスがずれても再発見可能にする *)
    syncTag = "doc-sync-" <> ToString[UnixTime[]] <> "-" <> ToString[RandomInteger[99999]];
    NBAccess`NBCellSetTaggingRule[nb, cellIdx, {$iDocTagRoot, "syncTag"}, syncTag];

    Which[
      (* === Case 1: プロンプト表示中 → パラグラフ再生成 (+翻訳連鎖) === *)
      mode === "idea",
        ideaText = currentText;
        paragraph = NBAccess`NBCellGetTaggingRule[nb, cellIdx, $iDocTagAlternate];
        translation = NBAccess`NBCellGetTaggingRule[nb, cellIdx, $iDocTagTranslation];
        prompt = If[StringQ[paragraph] && StringTrim[paragraph] =!= "",
          iDocReExpandPromptFn[ideaText, paragraph, context],
          iDocExpandPromptFn[ideaText, context]];
        Quiet[CurrentValue[nb, WindowStatusArea] =
          iL["同期中: パラグラフ生成...", "Syncing: generating paragraph..."]];
        With[{nb2 = nb, origIdx = cellIdx, tl = targetLang, fb = useFallback,
              hasTranslation = StringQ[translation] && StringTrim[translation] =!= "",
              oldTranslation = If[StringQ[translation], translation, ""],
              idea = ideaText, stag = syncTag},
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
                        newPara, tl, oldTranslation, idea]},
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
        If[!StringQ[translation] || StringTrim[translation] === "",
          NBAccess`NBCellSetTaggingRule[nb, cellIdx,
            {$iDocTagRoot, "syncTag"}, Inherited];
          MessageDialog[iL[
            "翻訳がありません。先に翻訳ボタンで翻訳を生成してください。",
            "No translation exists. Use the Translate button first."]];
          Return[$Failed]];
        prompt = iDocReTranslatePromptFn[paragraph, targetLang, translation, ideaText];
        Quiet[CurrentValue[nb, WindowStatusArea] =
          iL["同期中: 翻訳更新...", "Syncing: updating translation..."]];
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
          ideaText, iDocOutputLanguage[]];
        Quiet[CurrentValue[nb, WindowStatusArea] =
          iL["同期中: パラグラフ更新...", "Syncing: updating paragraph..."]];
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
          storedTranslation, transSrc, currentText, count = 0},
    If[Head[nb] =!= NotebookObject, Return[]];
    NBAccess`NBInvalidateCellsCache[nb];
    nCells = NBAccess`NBCellCount[nb];
    Do[
      mode = NBAccess`NBCellGetTaggingRule[nb, i, $iDocTagMode];
      showTrans = NBAccess`NBCellGetTaggingRule[nb, i, $iDocTagShowTranslation];
      (* 対象: documentation モードを持つセルのみ *)
      If[StringQ[mode],
        Which[
          (* === 全プロンプト表示 === *)
          targetView === "idea" && mode === "paragraph" && !TrueQ[showTrans],
            (* paragraph → idea *)
            alternate = NBAccess`NBCellGetTaggingRule[nb, i, $iDocTagAlternate];
            If[StringQ[alternate],
              currentText = NBAccess`NBCellGetText[nb, i];
              NBAccess`NBCellSetTaggingRule[nb, i, $iDocTagAlternate,
                If[StringQ[currentText], currentText, ""]];
              NBAccess`NBCellSetTaggingRule[nb, i, $iDocTagMode, "idea"];
              NBAccess`NBCellSetOptions[nb, i, Sequence @@ $iDocIdeaCellOpts];
              NBAccess`NBInvalidateCellsCache[nb];
              NBAccess`NBCellWriteText[nb, i, alternate];
              NBAccess`NBInvalidateCellsCache[nb];
              count++],
          targetView === "idea" && TrueQ[showTrans] && mode === "paragraph",
            (* translation → idea (via paragraph revert + toggle) *)
            transSrc = NBAccess`NBCellGetTaggingRule[nb, i, $iDocTagTranslationSrc];
            alternate = NBAccess`NBCellGetTaggingRule[nb, i, $iDocTagAlternate];
            If[StringQ[transSrc] && StringQ[alternate],
              NBAccess`NBCellSetTaggingRule[nb, i,
                $iDocTagTranslation, NBAccess`NBCellGetText[nb, i]];
              NBAccess`NBCellSetTaggingRule[nb, i, $iDocTagShowTranslation, False];
              NBAccess`NBCellSetTaggingRule[nb, i, $iDocTagAlternate, transSrc];
              NBAccess`NBCellSetTaggingRule[nb, i, $iDocTagMode, "idea"];
              NBAccess`NBCellSetOptions[nb, i, Sequence @@ $iDocIdeaCellOpts];
              NBAccess`NBInvalidateCellsCache[nb];
              NBAccess`NBCellWriteText[nb, i, alternate];
              NBAccess`NBInvalidateCellsCache[nb];
              count++],

          (* === 全パラグラフ表示 === *)
          targetView === "paragraph" && mode === "idea",
            (* idea → paragraph *)
            alternate = NBAccess`NBCellGetTaggingRule[nb, i, $iDocTagAlternate];
            If[StringQ[alternate],
              currentText = NBAccess`NBCellGetText[nb, i];
              NBAccess`NBCellSetTaggingRule[nb, i, $iDocTagAlternate,
                If[StringQ[currentText], currentText, ""]];
              NBAccess`NBCellSetTaggingRule[nb, i, $iDocTagMode, "paragraph"];
              NBAccess`NBCellSetOptions[nb, i, Sequence @@ $iDocParagraphCellOpts];
              NBAccess`NBInvalidateCellsCache[nb];
              NBAccess`NBCellWriteText[nb, i, alternate];
              NBAccess`NBInvalidateCellsCache[nb];
              count++],
          targetView === "paragraph" && TrueQ[showTrans] && mode === "paragraph",
            (* translation → paragraph *)
            transSrc = NBAccess`NBCellGetTaggingRule[nb, i, $iDocTagTranslationSrc];
            If[StringQ[transSrc],
              NBAccess`NBCellSetTaggingRule[nb, i,
                $iDocTagTranslation, NBAccess`NBCellGetText[nb, i]];
              NBAccess`NBCellSetTaggingRule[nb, i, $iDocTagShowTranslation, False];
              NBAccess`NBCellSetOptions[nb, i, Sequence @@ $iDocParagraphCellOpts];
              NBAccess`NBInvalidateCellsCache[nb];
              NBAccess`NBCellWriteText[nb, i, transSrc];
              NBAccess`NBInvalidateCellsCache[nb];
              count++],

          (* === 全翻訳表示 === *)
          targetView === "translation" && !TrueQ[showTrans],
            storedTranslation = NBAccess`NBCellGetTaggingRule[nb, i, $iDocTagTranslation];
            If[StringQ[storedTranslation] && StringTrim[storedTranslation] =!= "",
              (* 現在のテキストを translationSrc に保存 *)
              currentText = NBAccess`NBCellGetText[nb, i];
              NBAccess`NBCellSetTaggingRule[nb, i,
                $iDocTagTranslationSrc, If[StringQ[currentText], currentText, ""]];
              NBAccess`NBCellSetTaggingRule[nb, i, $iDocTagShowTranslation, True];
              NBAccess`NBCellSetOptions[nb, i, Sequence @@ $iDocTranslationCellOpts];
              NBAccess`NBInvalidateCellsCache[nb];
              NBAccess`NBCellWriteText[nb, i, storedTranslation];
              NBAccess`NBInvalidateCellsCache[nb];
              count++]
        ]];
      (* translated モード（普通セル+翻訳）のトグルも処理 *)
      If[mode === "translated",
        Which[
          targetView === "translation" && !TrueQ[showTrans],
            storedTranslation = NBAccess`NBCellGetTaggingRule[nb, i, $iDocTagTranslation];
            If[StringQ[storedTranslation] && StringTrim[storedTranslation] =!= "",
              currentText = NBAccess`NBCellGetText[nb, i];
              NBAccess`NBCellSetTaggingRule[nb, i,
                $iDocTagTranslationSrc, If[StringQ[currentText], currentText, ""]];
              NBAccess`NBCellSetTaggingRule[nb, i, $iDocTagShowTranslation, True];
              NBAccess`NBCellSetOptions[nb, i, Sequence @@ $iDocTranslationCellOpts];
              NBAccess`NBInvalidateCellsCache[nb];
              NBAccess`NBCellWriteText[nb, i, storedTranslation];
              NBAccess`NBInvalidateCellsCache[nb];
              count++],
          (targetView === "idea" || targetView === "paragraph") && TrueQ[showTrans],
            transSrc = NBAccess`NBCellGetTaggingRule[nb, i, $iDocTagTranslationSrc];
            If[StringQ[transSrc],
              NBAccess`NBCellSetTaggingRule[nb, i,
                $iDocTagTranslation, NBAccess`NBCellGetText[nb, i]];
              NBAccess`NBCellSetTaggingRule[nb, i, $iDocTagShowTranslation, False];
              NBAccess`NBCellSetOptions[nb, i, Sequence @@ $iDocTranslatedCellOpts];
              NBAccess`NBInvalidateCellsCache[nb];
              NBAccess`NBCellWriteText[nb, i, transSrc];
              NBAccess`NBInvalidateCellsCache[nb];
              count++]
        ]],
    {i, nCells}];
    If[count > 0,
      Quiet[CurrentValue[nb, WindowStatusArea] =
        iL[ToString[count] <> " セルを切り替えました。",
           ToString[count] <> " cells switched."]];
      RunScheduledTask[With[{pNb = nb},
        Quiet[CurrentValue[pNb, WindowStatusArea] = ""]], {3}]];
  ];

(* ============================================================
   パレットボタンアクション
   ============================================================ *)

SetAttributes[iDocButton, HoldRest];
iDocButton[label_String, color_, action_] :=
  Button[
    Style[label, Bold, 10, White],
    CompoundExpression[action,
      With[{inb = InputNotebook[]},
        If[Head[inb] === NotebookObject,
          SetSelectedNotebook[inb]]]],
    Appearance -> "Frameless",
    Background -> color,
    ImageSize -> {100, 22},
    FrameMargins -> {{4, 4}, {2, 2}},
    Method -> "Queued"
  ];

iDocExpandSelected[] :=
  Module[{nb, cellIdxs},
    {nb, cellIdxs} = iDocResolveTargetCells[];
    If[Length[cellIdxs] === 0,
      MessageDialog[iL["セルを選択してください。", "Please select a cell."]];
      Return[$Failed]];
    If[Length[cellIdxs] === 1,
      DocExpandIdea[nb, First[cellIdxs], Fallback -> ClaudeCode`GetPaletteFallback[]],
      (* 複数セル: 非同期チェーンで逐次展開 *)
      iDocExpandSelectedChain[nb, cellIdxs, 1, ClaudeCode`GetPaletteFallback[]]]
  ];

(* 複数セル展開の非同期チェーン *)
iDocExpandSelectedChain[nb_, idxs_, pos_, fb_] :=
  If[pos > Length[idxs],
    Quiet[CurrentValue[nb, WindowStatusArea] =
      iL[ToString[Length[idxs]] <> " セルを展開しました。",
         ToString[Length[idxs]] <> " cells expanded."]];
    RunScheduledTask[With[{pNb = nb},
      Quiet[CurrentValue[pNb, WindowStatusArea] = ""]], {3}],
    Quiet[CurrentValue[nb, WindowStatusArea] =
      iL["展開中: ", "Expanding: "] <> ToString[pos] <> "/" <> ToString[Length[idxs]]];
    Module[{cellIdx = idxs[[pos]], mode},
      mode = NBAccess`NBCellGetTaggingRule[nb, cellIdx, $iDocTagMode];
      If[mode === "paragraph" || iDocIsNoteCell[nb, cellIdx],
        (* パラグラフモード / Note セルはスキップ *)
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
      DocTranslate[nb, First[cellIdxs], Fallback -> ClaudeCode`GetPaletteFallback[]],
      (* 複数セル: 非同期チェーンで逐次翻訳 *)
      iDocTranslateSelectedChain[nb, cellIdxs, 1, ClaudeCode`GetPaletteFallback[]]]
  ];

(* 複数セル翻訳の非同期チェーン *)
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
      If[mode === "idea" || iDocIsNoteCell[nb, cellIdx],
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
   Note セル判定ヘルパー
   ============================================================ *)

(* セルが Note スタイルかどうかを判定する *)
iDocIsNoteCell[nb_NotebookObject, cellIdx_Integer] :=
  NBAccess`NBCellStyle[nb, cellIdx] === "Note";

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
        (* ラスター画像: PNG で出力 *)
        filePath = FileNameJoin[{outDir, baseName <> ".png"}];
        NBAccess`NBCellRasterize[nb, cellIdx, filePath];
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

(* セルオブジェクトを解決 (NBAccess の iResolveCell に相当するが、
   Private なので簡易版を用意) *)
iResolveExportCell[nb_NotebookObject, cellIdx_Integer] :=
  Module[{cells},
    cells = Cells[nb];
    If[cellIdx < 1 || cellIdx > Length[cells], $Failed, cells[[cellIdx]]]
  ];

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
    imgCounter_Integer, format_String] :=
  Module[{cellExpr, hasImage, text, imgFile, imgName},
    cellExpr = NBAccess`NBCellRead[nb, cellIdx];
    hasImage = NBAccess`NBCellHasImage[cellExpr];
    If[hasImage,
      (* 画像を含む Output: 画像としてエクスポート *)
      imgName = "img_" <> ToString[imgCounter];
      imgFile = iDocExportCellImage[nb, cellIdx, outDir, imgName];
      If[StringQ[imgFile],
        Module[{relPath = FileNameTake[imgFile]},
          If[format === "markdown",
            "![" <> imgName <> "](" <> relPath <> ")",
            "\\begin{figure}[htbp]\n\\centering\n\\includegraphics[width=0.8\\textwidth]{" <>
              relPath <> "}\n\\end{figure}"]],
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
   エクスポート: ディスプレイ数式セル (DisplayFormula 等)
   ============================================================ *)

iDocDisplayMathToExport[nb_NotebookObject, cellIdx_Integer, format_String] :=
  Module[{cellExpr, content, tex},
    cellExpr = NBAccess`NBCellRead[nb, cellIdx];
    If[cellExpr === $Failed, Return[""]];
    (* Cell[BoxData[...], ...] からコンテンツを取得 *)
    content = cellExpr /. Cell[c_, ___] :> c;
    If[Head[content] === BoxData, content = First[content]];
    tex = iDocBoxToTeX[content];
    If[format === "markdown",
      "\n$$\n" <> tex <> "\n$$\n",
      "\n\\[\n" <> tex <> "\n\\]\n"]
  ];

(* ============================================================
   エクスポート: テキストセル処理
   ============================================================ *)

iDocTextCellToExport[nb_NotebookObject, cellIdx_Integer, format_String] :=
  Module[{style, cellExpr, content, text, level},
    style = NBAccess`NBCellStyle[nb, cellIdx];
    cellExpr = NBAccess`NBCellRead[nb, cellIdx];
    If[cellExpr === $Failed, Return[""]];

    (* セル内容を取得 *)
    content = cellExpr /. Cell[c_, ___] :> c;

    (* テキスト変換 *)
    text = Which[
      StringQ[content],
        content,
      Head[content] === TextData,
        iDocTextDataToString[content, format],
      Head[content] === BoxData,
        (* 数式セル *)
        Module[{tex = iDocBoxToTeX[First[content]]},
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
    imgCounter_Integer, format_String] :=
  Module[{style, cellExpr, hasImage, result, mode, showTrans},
    style = NBAccess`NBCellStyle[nb, cellIdx];

    (* Note セルはスキップ *)
    If[iDocIsNoteCell[nb, cellIdx], Return[{Null, imgCounter}]];

    (* ドキュメントモード確認: idea モードならパラグラフ版を使う *)
    mode = NBAccess`NBCellGetTaggingRule[nb, cellIdx, $iDocTagMode];
    If[mode === "idea",
      (* パラグラフ (展開済み) があればそちらを使ってテキストを一時差し替え *)
      Module[{para = NBAccess`NBCellGetTaggingRule[nb, cellIdx, $iDocTagAlternate]},
        If[StringQ[para] && StringTrim[para] =!= "",
          (* パラグラフ版のテキストでテキストセルとして出力 *)
          Return[{If[format === "markdown", para,  para], imgCounter}]]]];

    (* スタイルに応じた処理 *)
    Which[
      (* Input セル → コードブロック *)
      style === "Input",
        {iDocInputCellToCode[nb, cellIdx, format], imgCounter},

      (* Output/Print セル → 画像 or テキスト *)
      MemberQ[{"Output", "Print", "Message", "Echo"}, style],
        cellExpr = NBAccess`NBCellRead[nb, cellIdx];
        hasImage = NBAccess`NBCellHasImage[cellExpr];
        result = iDocOutputCellToExport[nb, cellIdx, outDir,
          imgCounter, format];
        {result, If[hasImage, imgCounter + 1, imgCounter]},

      (* DisplayFormula 等 *)
      MemberQ[{"DisplayFormula", "DisplayFormulaNumbered"}, style],
        {iDocDisplayMathToExport[nb, cellIdx, format], imgCounter},

      (* テキスト系セル *)
      MemberQ[{"Title", "Subtitle", "Chapter", "Section", "Subsection",
               "Subsubsection", "Text", "Item", "Subitem",
               "ItemNumbered", "SubitemNumbered", "ItemParagraph",
               "SubitemParagraph"}, style],
        (* テキストセルでも画像を含む場合がある *)
        cellExpr = NBAccess`NBCellRead[nb, cellIdx];
        If[NBAccess`NBCellHasImage[cellExpr],
          Module[{imgName = "img_" <> ToString[imgCounter],
                  imgFile, textPart, imgPart},
            imgFile = iDocExportCellImage[nb, cellIdx, outDir, imgName];
            textPart = iDocTextCellToExport[nb, cellIdx, format];
            imgPart = If[StringQ[imgFile],
              Module[{relPath = FileNameTake[imgFile]},
                If[format === "markdown",
                  "\n![" <> imgName <> "](" <> relPath <> ")",
                  "\n\\includegraphics[width=0.8\\textwidth]{" <> relPath <> "}"]],
              ""];
            {textPart <> imgPart, imgCounter + 1}],
          {iDocTextCellToExport[nb, cellIdx, format], imgCounter}],

      (* それ以外: スキップ *)
      True,
        {Null, imgCounter}
    ]
  ];

(* Markdown エクスポート *)
DocExportMarkdown[nb_NotebookObject] :=
  Module[{outDir, nCells, lines = {}, imgCounter = 1,
          result, line, outFile, baseName},
    outDir = iDocEnsureExportDir[nb, "md"];
    If[outDir === $Failed,
      MessageDialog[iL[
        "ノートブックのディレクトリを取得できません。\n先にノートブックを保存してください。",
        "Cannot get notebook directory.\nPlease save the notebook first."]];
      Return[$Failed]];
    baseName = iDocNotebookBaseName[nb];
    NBAccess`NBInvalidateCellsCache[nb];
    nCells = NBAccess`NBCellCount[nb];

    Quiet[CurrentValue[nb, WindowStatusArea] =
      iL["Markdown エクスポート中...", "Exporting Markdown..."]];

    Do[
      Quiet[CurrentValue[nb, WindowStatusArea] =
        iL["エクスポート中: ", "Exporting: "] <> ToString[i] <> "/" <> ToString[nCells]];
      {line, imgCounter} = iDocCellToExport[nb, i, outDir, imgCounter, "markdown"];
      If[line =!= Null && StringQ[line] && StringTrim[line] =!= "",
        AppendTo[lines, line]],
    {i, nCells}];

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
DocExportLaTeX[nb_NotebookObject] :=
  Module[{outDir, nCells, lines = {}, imgCounter = 1,
          result, line, outFile, baseName, header, footer},
    outDir = iDocEnsureExportDir[nb, "LaTeX"];
    If[outDir === $Failed,
      MessageDialog[iL[
        "ノートブックのディレクトリを取得できません。\n先にノートブックを保存してください。",
        "Cannot get notebook directory.\nPlease save the notebook first."]];
      Return[$Failed]];
    baseName = iDocNotebookBaseName[nb];
    NBAccess`NBInvalidateCellsCache[nb];
    nCells = NBAccess`NBCellCount[nb];

    Quiet[CurrentValue[nb, WindowStatusArea] =
      iL["LaTeX エクスポート中...", "Exporting LaTeX..."]];

    Do[
      Quiet[CurrentValue[nb, WindowStatusArea] =
        iL["エクスポート中: ", "Exporting: "] <> ToString[i] <> "/" <> ToString[nCells]];
      {line, imgCounter} = iDocCellToExport[nb, i, outDir, imgCounter, "latex"];
      If[line =!= Null && StringQ[line] && StringTrim[line] =!= "",
        AppendTo[lines, line]],
    {i, nCells}];

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

iDocInsertNoteAction[] :=
  Module[{nb = iDocUserNotebook[]},
    If[Head[nb] =!= NotebookObject,
      MessageDialog[iL["ノートブックが見つかりません。", "No notebook found."]];
      Return[$Failed]];
    DocInsertNote[nb]
  ];

(* ============================================================
   パレット設定
   ============================================================ *)

(* ============================================================
   メインパレット
   ============================================================ *)

ShowDocPalette[] := (
  If[$docPalette =!= None, Quiet@NotebookClose[$docPalette]];
  (* 初期ロード: 現在のノートブックから設定を読み込む *)
  Module[{initNb = Quiet[InputNotebook[]]},
    If[Head[initNb] === NotebookObject,
      ClaudeCode`LoadPaletteSettings[initNb]]];
  $docPalette = CreatePalette[
    DynamicModule[{lastNb = None},
    Dynamic[
      (* ノートブック切替を検出して設定をリロード *)
      Module[{curNb = Quiet[InputNotebook[]]},
        If[Head[curNb] === NotebookObject &&
           Quiet[CurrentValue[curNb, WindowClickSelect]] =!= False &&
           curNb =!= lastNb,
          lastNb = curNb;
          ClaudeCode`LoadPaletteSettings[curNb]]];
    Column[{
      Style["Documentation", Bold, 11, RGBColor[0.2, 0.5, 0.3]],

      (* -- 執筆ツール -- *)
      Style[iL[" 執筆ツール", " Writing Tools"], Bold, 8, GrayLevel[0.3]],
      iDocButton[iL["\[FilledRightTriangle] 展開", "\[FilledRightTriangle] Expand"],
        RGBColor[0.2, 0.55, 0.35],
        iDocExpandSelected[]],
      iDocButton[iL["\[RightGuillemet] 翻訳", "\[RightGuillemet] Translate"],
        RGBColor[0.3, 0.4, 0.65],
        iDocTranslateSelected[]],
      iDocButton[iL["\[Equilibrium] 同期", "\[Equilibrium] Sync"],
        RGBColor[0.45, 0.35, 0.6],
        iDocSyncSelected[]],
      Spacer[1],
      iDocButton[iL["\[LeftRightArrow] 切替", "\[LeftRightArrow] Toggle"],
        RGBColor[0.35, 0.45, 0.65],
        iDocToggleSelected[]],
      iDocButton[iL["\[FilledSmallSquare] メモ", "\[FilledSmallSquare] Note"],
        RGBColor[0.7, 0.63, 0.35],
        iDocInsertNoteAction[]],
      Spacer[2],

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
        iDocShowAllAs["translation"]],
      Spacer[2],

      (* -- エクスポート -- *)
      Style[iL[" エクスポート", " Export"], Bold, 8, GrayLevel[0.3]],
      iDocButton[iL["\[RightArrowBar] Markdown", "\[RightArrowBar] Markdown"],
        RGBColor[0.3, 0.5, 0.55],
        iDocExportMarkdownAction[]],
      iDocButton[iL["\[RightArrowBar] LaTeX", "\[RightArrowBar] LaTeX"],
        RGBColor[0.4, 0.4, 0.55],
        iDocExportLaTeXAction[]],
      Spacer[2],

      (* -- 設定 (ClaudeCode パレットと共有: 公開アクセサ経由) -- *)
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
      Spacer[2],

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
    ]
    ],
    WindowTitle -> "Documentation",
    WindowSize -> {105, All},
    WindowFloating -> True,
    WindowClickSelect -> False,
    WindowMargins -> {{Automatic, 113}, {Automatic, 4}},
    Saveable -> False
  ]
);

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
