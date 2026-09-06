(* ::Package:: *)

(* ============================================================
   documentation_paper2nb.wl -- 論文 PDF → Mathematica ノートブック逆変換

   This file is encoded in UTF-8.
   Load order: documentation.wl -> documentation_paper2nb.wl (末尾で自動 Get)
   Load via:   Block[{$CharacterEncoding = "UTF-8"}, Get["documentation_paper2nb.wl"]]

   == 何をするか ==
     documentation.wl はノートブック → LaTeX/Word/Markdown の順変換を担う。
     このサブモジュールはその逆向き、論文 PDF → documentation 規約のノートブック
     を作る。手作業変換 (file.nb の例) と同じ形を目指す:

     第一部 (本文の再現)
       - 見出し階層 (Section / Subsection / Subsubsection) を復元
       - 段落は翻訳して Text セルへ。原文は TaggingRules (translationSrc) に
         保持し、mode="translated" として DocToggleView で原文と往復できる
       - 本文中の数式は LaTeX → TraditionalForm ボックスとして Text セル中の
         インライン数式 (Cell[BoxData[FormBox[...]]]) に再現する
       - 別行立て数式は "DisplayFormula" セル。LaTeX → ボックス変換に失敗した
         ものは PDF ページ画像から該当領域を切り出して貼る
       - 図・表は PDF ページ画像から領域を切り出して貼り、キャプションは
         Text セル (figLabel / figCaption タグ付き) にする
       - 参考文献は Text セル + Bibliography メタセル
       - 先頭に Directive / Dictionary メタセルを置く (翻訳指示・用語対応)
       - 各セルの refSources に {PDF, {ページ}} を入れる (依存資料として追跡)

     第二部 (計算の再構成)
       - 論文全文から「再現できる計算・アルゴリズム・数式」を抽出し、
         Wolfram Language の定義 (Input セル) と実行例に再構成する
       - 生成コードは SyntaxQ で構文検査し、失敗時は 1 回だけ修正を依頼する。
         評価はしない (利用者が評価する)

   == 位置決めの仕組み ==
     Import[pdf, {"PagePositionedObjects", p}] が返すテキストブロック
     (文字列 + バウンディングボックス, PDF 座標 pt) に id を振って LLM に渡し、
     LLM は各要素 (図・表・数式) を構成するブロック id を返す。切り出し領域は
     その id の矩形の和集合、図のように内部にテキストが無い要素は
     「キャプションと隣接本文の間の隙間」として決定的に求める。
     Import[pdf, {"PageImages", p}, ImageResolution -> r] の画素へは
     px = x * r/72, py = (H - y) * r/72 で写す。

   == LLM 呼び出し ==
     ClaudeCode`ClaudeQueryBg (同期・FE 操作なし・ScheduledTask 生成なし) を使う。
     ページ画像はリスト引数 {prompt, image} で渡す (claudecode CLI は自動で
     vision 処理、anthropic API 経路は Fallback -> True が要る)。
     JSON 応答は ImportByteArray[..., "RawJSON"] で読む (ExportString/RawJSON の
     バイト文字列の罠を避ける)。

   == プライバシー ==
     PDF の本文とページ画像はパレットで選ばれている LLM プロバイダへ送られる。
     非公開の原稿を扱うときはローカルプロバイダ (lmstudio 等) を選ぶこと。
     生成ノートブックの CloudPublishable 宣言は既定では付けない
     ("CloudPublishable" -> True|False で明示したときだけ NBSetCloudPublishable)。
   ============================================================ *)

BeginPackage["Documentation`"];

Needs["NBAccess`"];
Needs["ClaudeCode`"];

DocImportPaper::usage =
  "DocImportPaper[pdfPath] は論文 PDF を documentation 規約のノートブックへ逆変換する。\n" <>
  "第一部: 見出し・段落 (翻訳 + 原文保持, mode=\"translated\")・インライン数式 (LaTeX → TraditionalForm)・\n" <>
  "別行立て数式 (DisplayFormula, 失敗時はページ画像の切り出し)・図表 (ページ画像の切り出し + キャプション)・参考文献。\n" <>
  "第二部: 論文中の計算・アルゴリズム・数式を Wolfram Language の定義と実行例に再構成する。\n" <>
  "出力: 既定では PDF と同じフォルダに <名前>.nb を保存し、開いた NotebookObject を返す (ヘッドレスならパス)。\n" <>
  "Options:\n" <>
  "  \"TargetLanguage\" -> Automatic ($Language), \"Translate\" -> True, \"Reconstruct\" -> True,\n" <>
  "  \"Pages\" -> All | {1,2,...} | Span, \"ImageResolution\" -> 150,\n" <>
  "  \"MathMode\" -> \"Auto\" (LaTeX→ボックス, 失敗時は画像) | \"Image\" (別行立ては常に画像) | \"Text\" (画像にしない),\n" <>
  "  \"Vision\" -> Automatic (ページ画像も LLM へ渡す。失敗時はテキストのみで再試行) | False,\n" <>
  "  \"VisionTimeout\" -> Automatic (画像付き試行の打ち切り秒数: ローカル LLM は 1500 秒、他は 600 秒。超えたらテキストのみで再試行),\n" <>
  "  \"OutputPath\" -> Automatic, \"Open\" -> True, \"Save\" -> True,\n" <>
  "  \"CloudPublishable\" -> None | True | False (SourceVault 宣言。None なら付けない),\n" <>
  "  \"Directive\" -> Automatic (翻訳指示。Directive セルにも書かれる), \"Dictionary\" -> {} ({原語, 訳語, 文脈} のリスト),\n" <>
  "  \"HeadingStyles\" -> Automatic ({\"Section\",\"Subsection\",\"Subsubsection\",\"Subsubsubsection\"}),\n" <>
  "  \"Verbose\" -> True, Fallback -> False (課金 API 許可), Model -> Automatic, Timeout -> Automatic\n" <>
  "例: DocImportPaper[\"C:/papers/original.pdf\"]\n" <>
  "    DocImportPaper[pdf, \"Pages\" -> 1 ;; 3, \"Reconstruct\" -> False]";

DocPaperAnalyzePage::usage =
  "DocPaperAnalyzePage[pdfPath, page] は PDF の 1 ページを LLM で構造解析し、\n" <>
  "読み順に並んだブロック (<|\"type\", \"text\", \"latex\", \"label\", \"ids\", \"translation\", \"Page\", \"Region\", ...|>) のリストを返す。\n" <>
  "DocImportPaper が内部で使う段階処理を単独で試すためのもの。失敗時は $Failed。\n" <>
  "Options: \"TargetLanguage\", \"Translate\", \"ImageResolution\", \"Vision\", \"Directive\", \"Dictionary\", \"Verbose\", Fallback, Model, Timeout";

DocPaperExtractComputations::usage =
  "DocPaperExtractComputations[pdfPath] は論文全文から再現可能な計算を抽出し、\n" <>
  "<|\"summary\" -> 要約, \"units\" -> {<|\"title\", \"description\", \"code\", \"example\", \"syntaxOK\"|>, ...}, \"notes\" -> 注意点|> を返す。\n" <>
  "DocPaperExtractComputations[pdfPath, blocks] は DocPaperAnalyzePage の結果 (全ページ連結) を本文として使う。\n" <>
  "Options: \"TargetLanguage\", \"Pages\", \"Verbose\", Fallback, Model, Timeout";

DocPaperTeXToBoxes::usage =
  "DocPaperTeXToBoxes[latex] は LaTeX 数式文字列を TraditionalForm のボックス式に変換する。\n" <>
  "1) 内蔵の簡易 LaTeX パーサ (添字・分数・根号・行列環境・ギリシャ文字・演算子記号。字面に忠実),\n" <>
  "2) ToExpression[..., TeXForm] → ToBoxes。どちらも失敗なら $Failed。\n" <>
  "例: Cell[BoxData[FormBox[DocPaperTeXToBoxes[\"\\\\frac{a}{b}\"], TraditionalForm]], \"DisplayFormula\"]";

DocPaperTextToTextData::usage =
  "DocPaperTextToTextData[text] は $...$ / \\(...\\) を含む文字列を、インライン数式セルを埋め込んだ TextData に変換する。\n" <>
  "数式が無ければ文字列をそのまま返す。Text セルの内容としてそのまま使える。";

$DocPaperLastAnalysis::usage =
  "$DocPaperLastAnalysis は直近の DocImportPaper / DocPaperAnalyzePage / DocPaperExtractComputations の中間結果\n" <>
  "(<|\"PDF\", \"Pages\", \"Blocks\", \"Computations\", \"Cells\"|>)。デバッグと再利用のために保持する。";

Options[DocImportPaper] = {
  "TargetLanguage" -> Automatic,
  "Translate" -> True,
  "Reconstruct" -> True,
  "Pages" -> All,
  "ImageResolution" -> 150,
  "MathMode" -> "Auto",
  "Vision" -> Automatic,
  "OutputPath" -> Automatic,
  "Open" -> True,
  "Save" -> True,
  "CloudPublishable" -> None,
  "Directive" -> Automatic,
  "Dictionary" -> {},
  "HeadingStyles" -> Automatic,
  "Verbose" -> True,
  "VisionTimeout" -> Automatic,
  Fallback -> False,
  Model -> Automatic,
  Timeout -> Automatic
};

Options[DocPaperAnalyzePage] = {
  "TargetLanguage" -> Automatic,
  "Translate" -> True,
  "ImageResolution" -> 150,
  "Vision" -> Automatic,
  "Directive" -> Automatic,
  "Dictionary" -> {},
  "Verbose" -> True,
  "VisionTimeout" -> Automatic,
  Fallback -> False,
  Model -> Automatic,
  Timeout -> Automatic
};

Options[DocPaperExtractComputations] = {
  "TargetLanguage" -> Automatic,
  "Pages" -> All,
  "Verbose" -> True,
  Fallback -> False,
  Model -> Automatic,
  Timeout -> Automatic
};

DocImportPaper::nofile = "PDF ファイルが見つかりません: `1`";
DocImportPaper::nopages = "PDF のページ数を取得できません: `1`";
DocImportPaper::llm = "LLM 呼び出しに失敗しました: `1`";
DocImportPaper::json = "LLM 応答を JSON として読めませんでした (ページ `1`)。";
DocImportPaper::syntax = "再構成コード「`1`」は構文修正後も SyntaxQ を通りません。そのまま挿入します。";

Begin["`Private`"];

If[!AssociationQ[$DocPaperLastAnalysis], $DocPaperLastAnalysis = <||>];

(* ============================================================
   小道具
   ============================================================ *)

(* 進捗: Print (評価ノートブック / メッセージ窓) + 手前のノートブックのステータスバー
   (パレットのボタンから呼ばれると Print が見えない場所へ行くため) *)
iDocPaperLog[verbose_, msg_String] :=
  If[TrueQ[verbose],
    Print[Style["[DocImportPaper] ", Bold, GrayLevel[0.4]], msg];
    If[$FrontEnd =!= Null,
      Quiet[With[{nb = InputNotebook[]},
        If[Head[nb] === NotebookObject,
          CurrentValue[nb, WindowStatusArea] = "DocImportPaper: " <> msg]]]]];

iDocPaperTargetLanguage[opt_] :=
  Which[
    StringQ[opt] && StringTrim[opt] =!= "", opt,
    StringQ[$Language], $Language,
    True, "English"];

(* 日本語・中国語は翻訳片を空白なしで連結する *)
iDocPaperJoinSep[lang_String] :=
  If[StringMatchQ[lang, "Japanese" | "Chinese" | "ChineseSimplified" | "ChineseTraditional", IgnoreCase -> True],
    "", " "];

iDocPaperHeadingStyles[opt_] :=
  If[ListQ[opt] && Length[opt] >= 4 && AllTrue[opt, StringQ], opt,
    {"Section", "Subsection", "Subsubsection", "Subsubsubsection"}];

iDocPaperDefaultDirective[lang_String] :=
  If[StringMatchQ[lang, "Japanese", IgnoreCase -> True],
    "論文なのでである調で内容に正確に翻訳する",
    "Translate faithfully in a formal academic register; keep terminology consistent."];

(* Dictionary セル本文 (documentation.wl の形式) *)
iDocPaperDictionaryCellText[dict_List, lang_String] :=
  Module[{rows, q},
    q = Function[s, "\"" <> StringReplace[ToString[s], "\"" -> "\\\""] <> "\""];
    rows = Select[dict, ListQ[#] && Length[#] >= 2 &];
    "{{<<" <> If[StringMatchQ[lang, "Japanese", IgnoreCase -> True], "Japanese", lang] <>
      ">>, <<English>>, <<Context>>}" <>
    StringJoin[Map[Function[r,
      ", {" <> q[r[[1]]] <> ", " <> q[r[[2]]] <> ", " <>
        q[If[Length[r] >= 3, r[[3]], ""]] <> "}"], rows]] <> "}"];

iDocPaperDictionaryPrompt[dict_List] :=
  Module[{rows = Select[dict, ListQ[#] && Length[#] >= 2 &]},
    If[Length[rows] === 0, "",
      "Terminology (translate the source term as given; context in parentheses):\n" <>
      StringJoin[Map[Function[r,
        "  - " <> ToString[r[[2]]] <> " -> " <> ToString[r[[1]]] <>
          If[Length[r] >= 3 && ToString[r[[3]]] =!= "", " (" <> ToString[r[[3]]] <> ")", ""] <> "\n"],
        rows]]]];

(* ページ指定の正規化 *)
iDocPaperResolvePages[spec_, nPages_Integer] :=
  Module[{pages},
    pages = Which[
      spec === All, Range[nPages],
      MatchQ[spec, _Span], Quiet @ Check[Range[nPages][[spec]], Range[nPages]],
      IntegerQ[spec], {spec},
      ListQ[spec], Select[spec, IntegerQ],
      True, Range[nPages]];
    DeleteDuplicates @ Select[pages, 1 <= # <= nPages &]];

(* ============================================================
   LLM 呼び出しと JSON 読み取り
   ============================================================ *)

(* items: {promptString} または {promptString, image, ...}。
   生の返り値: 応答文字列 ("Error..." を含む) または $Failed。メッセージは出さない。 *)
iDocPaperQueryRaw[items_List, cfg_Association] :=
  Module[{arg},
    arg = If[Length[items] === 1 && StringQ[First[items]], First[items], items];
    Quiet[
      ClaudeCode`ClaudeQueryBg[arg,
        Fallback -> TrueQ[cfg["Fallback"]],
        Model -> cfg["Model"],
        Timeout -> cfg["Timeout"]]]];

iDocPaperErrorStringQ[res_] :=
  StringQ[res] && (StringStartsQ[StringTrim[res], "Error"] || StringStartsQ[StringTrim[res], "[ERROR]"]);

(* 返り値: 応答文字列。失敗は $Failed (メッセージ付き)。 *)
iDocPaperQuery[items_List, cfg_Association] :=
  Module[{res = iDocPaperQueryRaw[items, cfg]},
    Which[
      !StringQ[res],
        Message[DocImportPaper::llm, ToString[Head[res]]]; $Failed,
      iDocPaperErrorStringQ[res],
        Message[DocImportPaper::llm, StringTake[StringTrim[res], UpTo[300]]]; $Failed,
      True, res]];

(* 画像入力に対応しないモデル (claudecode.wl が "NoVision" を含むエラーで知らせる) を
   このセッションで覚えておき、以後のページでは画像付き試行を最初から省く *)
If[!ListQ[$iDocPaperNoVisionModels], $iDocPaperNoVisionModels = {}];
iDocPaperModelKey[cfg_Association] := ToString[{cfg["Model"], ClaudeCode`$ClaudeModel}, InputForm];

(* 画像付きで問い、失敗したらテキストのみで再試行する。
   画像付きの試行は "VisionTimeout" (既定 600 秒) で打ち切る: 長いプロンプト + 画像で CLI が
   応答しないまま固まる事例があり、既定の Timeout (1200 秒) をページ毎に浪費しないため。 *)
iDocPaperQueryMaybeVision[prompt_String, img_, cfg_Association] :=
  Module[{res = $Failed, key = iDocPaperModelKey[cfg]},
    If[TrueQ[cfg["Vision"]] && ImageQ[img] && !MemberQ[$iDocPaperNoVisionModels, key],
      res = iDocPaperQueryRaw[{prompt, img}, Append[cfg, "Timeout" -> cfg["VisionTimeout"]]];
      Which[
        StringQ[res] && StringContainsQ[res, "NoVision"],
          AppendTo[$iDocPaperNoVisionModels, key];
          iDocPaperLog[cfg["Verbose"],
            "このモデルは画像入力に対応しないため、以後はテキストのみで解析します。"];
          res = $Failed,
        !StringQ[res] || iDocPaperErrorStringQ[res],
          iDocPaperLog[cfg["Verbose"], "画像付き問い合わせに失敗 (" <>
            If[StringQ[res], StringTake[StringTrim[res], UpTo[120]], ToString[Head[res]]] <>
            ")。テキストのみで再試行します。"];
          res = $Failed,
        True, Null]];
    If[res === $Failed, res = iDocPaperQuery[{prompt}, cfg]];
    res];

(* 応答からコードフェンスを剥がし、最初の [ / { から最後の ] / } までを RawJSON で読む *)
iDocPaperParseJSON[s_String] :=
  Module[{t = StringTrim[s], openPos, closePos, body, parsed},
    t = StringReplace[t, {
      RegularExpression["(?s)^```[A-Za-z]*[ \\t]*\\r?\\n"] -> "",
      RegularExpression["(?s)\\r?\\n```[ \\t]*$"] -> ""}];
    openPos = StringPosition[t, "[" | "{", 1];
    closePos = StringPosition[t, "]" | "}"];
    If[openPos === {} || closePos === {}, Return[$Failed]];
    body = StringTake[t, {openPos[[1, 1]], closePos[[-1, 1]]}];
    parsed = Quiet[ImportByteArray[StringToByteArray[body, "UTF-8"], "RawJSON"]];
    If[parsed === $Failed,
      (* LaTeX の \a \g のような JSON として不正なエスケープを \\ に直して再試行 *)
      body = StringReplace[body, RegularExpression["\\\\(?![\"\\\\/bfnrtu])"] -> "\\\\"];
      parsed = Quiet[ImportByteArray[StringToByteArray[body, "UTF-8"], "RawJSON"]]];
    parsed];

iDocPaperParseJSON[_] := $Failed;

(* JSON の値を安全に文字列へ *)
iDocPaperStr[v_] := Which[StringQ[v], v, v === Null || MissingQ[v], "", True, ToString[v]];
iDocPaperBool[v_] := TrueQ[v] || (StringQ[v] && ToLowerCase[v] === "true");

(* ids: ["B3", 4, "12", "B20-B25"] → {3, 4, 12, 20, 21, ..., 25} (範囲表記も受ける) *)
iDocPaperIds[v_] :=
  Which[
    ListQ[v], DeleteDuplicates @ Flatten[Map[iDocPaperOneId, v]],
    v === Null || MissingQ[v], {},
    True, DeleteDuplicates @ Flatten[{iDocPaperOneId[v]}]];

iDocPaperOneId[x_Integer] := {x};
iDocPaperOneId[x_Real] := {Round[x]};
iDocPaperOneId[s_String] :=
  Module[{d = StringCases[s, DigitCharacter ..], a, b},
    Which[
      d === {}, {},
      Length[d] >= 2 && StringContainsQ[s, "-" | "\[Dash]" | "\[LongDash]" | ".." | ":"],
        {a, b} = FromDigits /@ Take[d, 2];
        If[b >= a && b - a <= 2000, Range[a, b], {a, b}],
      True, {FromDigits[First[d]]}]];
iDocPaperOneId[_] := {};

(* ============================================================
   PDF 抽出: テキストブロック (座標付き) とページ画像
   ============================================================ *)

(* 返り値: {<|"id", "text", "Left", "Top", "Right", "Bottom"|>, ...}
   座標は PDF pt (原点左下、Top > Bottom)。抽出できなければ {} *)
iDocPaperPageBlocks[pdf_String, p_Integer] :=
  Module[{raw, objs, blocks},
    raw = Quiet[Import[pdf, {"PagePositionedObjects", p}]];
    objs = Which[
      AssociationQ[raw] && Length[raw] > 0, First[Values[raw]],
      ListQ[raw], raw,
      True, {}];
    If[!ListQ[objs], objs = {}];
    blocks = Cases[objs,
      {txt_String, {{x0_?NumericQ, y0_?NumericQ}, {x1_?NumericQ, y1_?NumericQ}}} /;
        StringTrim[txt] =!= "" :>
        <|"text" -> StringTrim[txt],
          "Left" -> Min[x0, x1], "Right" -> Max[x0, x1],
          "Top" -> Max[y0, y1], "Bottom" -> Min[y0, y1]|>];
    MapIndexed[Append[#1, "id" -> First[#2]] &,
      iDocPaperMergeFragments[Map[iDocPaperSanitizeBlock, blocks]]]];

(* 文字層の矩形は時々壊れている: 1 文字のブロックで 2 点目が {x, 0} になり Bottom = 0 (ページ下端) に
   なる等。そのままだと和集合がページ全体に広がり、図の切り出しが全ページになる。
   行数から妥当な高さ (1 行 ≈ 11pt) を見積もって直す。座標が全く無いもの (Top <= 0) は
   幾何計算から外す (iDocPaperGeomQ)。 *)
iDocPaperSanitizeBlock[b_Association] :=
  Module[{nLines, h, bb = b},
    nLines = Max[1, StringCount[b["text"], "\n"] + 1];
    h = b["Top"] - b["Bottom"];
    If[b["Top"] > 0.5,
      If[b["Bottom"] <= 0.5 || h > 18 nLines + 6, bb["Bottom"] = b["Top"] - 11 nLines];
      If[bb["Top"] - bb["Bottom"] < 4, bb["Bottom"] = bb["Top"] - 8]];
    If[b["Right"] - b["Left"] < 2, bb["Right"] = b["Left"] + 5 StringLength[b["text"]]];
    bb];

iDocPaperGeomQ[b_Association] := TrueQ[b["Top"] > 0.5 && b["Right"] > b["Left"]];

(* 同じ行 (Top の差 3.5pt 以内) で隣接 (隙間 12pt 以内)、高さも近いブロックを 1 個に結合する。
   PDF の文字層は数式まわりで "This work uses one-dimensional" / "2" / "-state" のように
   細切れになり (図の多いページでは 500 ブロックを超える)、LLM の入出力を無駄に膨らませる。
   結合後は行順 (上→下、左→右) に並ぶので、読み順の再構成も楽になる。
   複数行の段落ブロック (高さが大きい) には 1 行の断片を結合しない。 *)
iDocPaperMergeFragments[blocks_List] :=
  Module[{sorted, rows, out = {}},
    If[Length[blocks] < 2, Return[blocks]];
    sorted = SortBy[blocks, {-#["Top"] &, #["Left"] &}];
    rows = Split[sorted, Abs[#1["Top"] - #2["Top"]] <= 3.5 &];
    Do[
      Module[{row = SortBy[r, #["Left"] &], acc = None},
        Do[
          If[acc === None, acc = b,
            If[b["Left"] - acc["Right"] <= 12 &&
               Abs[(acc["Top"] - acc["Bottom"]) - (b["Top"] - b["Bottom"])] <= 14,
              acc = <|"text" -> acc["text"] <> " " <> b["text"],
                      "Left" -> Min[acc["Left"], b["Left"]], "Right" -> Max[acc["Right"], b["Right"]],
                      "Top" -> Max[acc["Top"], b["Top"]], "Bottom" -> Min[acc["Bottom"], b["Bottom"]]|>,
              AppendTo[out, acc]; acc = b]],
          {b, row}];
        If[acc =!= None, AppendTo[out, acc]]],
      {r, rows}];
    out];

(* 座標なしの全文フォールバック (スキャン PDF 等) *)
iDocPaperPagePlainText[pdf_String, p_Integer] :=
  Module[{txt = Quiet[Import[pdf, {"Plaintext", p}]]},
    If[StringQ[txt], txt, ""]];

iDocPaperPageImage[pdf_String, p_Integer, res_] :=
  Module[{img = Quiet[Import[pdf, {"PageImages", p}, ImageResolution -> res]]},
    If[ListQ[img] && Length[img] > 0, img = First[img]];
    If[ImageQ[img], img, $Failed]];

(* ブロック一覧を LLM 向けテキストにする *)
iDocPaperBlocksToPrompt[blocks_List] :=
  StringJoin[Map[Function[b,
    "[B" <> ToString[b["id"]] <> "] " <>
    StringReplace[b["text"], "\n" -> " / "] <> "\n"], blocks]];

(* ============================================================
   ページ構造解析プロンプト
   ============================================================ *)

iDocPaperAnalysisPrompt[p_Integer, nPages_Integer, blocksText_String, hasBlocks_, hasImage_,
                        translateQ_, lang_String, directive_String, dictPrompt_String] :=
  StringJoin[
    "You are converting a scientific paper (PDF) into a structured, computable notebook.\n",
    "This is page ", ToString[p], " of ", ToString[nPages], ".\n",
    If[hasBlocks,
      "Below is the text layer of the page, split into positioned text blocks. Each block starts with its id [Bn]. " <>
      "The extraction order can be broken (columns, headers, footnotes, equations split into fragments): reconstruct the logical reading order.\n",
      "The page has no usable text layer. Transcribe the page from the attached image.\n"],
    If[hasImage,
      "The page image is attached. Use it to recover mathematical notation that the text layer flattened " <>
      "(subscripts, superscripts, Greek letters, operators, matrices) and to identify figures and tables.\n", ""],
    "\nReturn ONLY a JSON object: {\"language\": \"<language of the paper>\", \"blocks\": [ ... ]}.\n",
    "Each element of \"blocks\", in reading order, is an object with these fields:\n",
    "  \"type\": one of \"title\", \"authors\", \"affiliation\", \"abstract\", \"keywords\", \"heading\", \"paragraph\", \"list\", ",
    "\"display_math\", \"figure\", \"table\", \"caption\", \"references\", \"footnote\", \"page_header\", \"other\"\n",
    "  \"level\": heading depth 1-3 (heading only; 1 = top-level numbered section)\n",
    "  \"text\": content in the ORIGINAL language, with every inline formula written as LaTeX between $...$ ",
    "(for title, authors, affiliation, abstract, keywords, heading, paragraph, list, caption, references, footnote). ",
    "Join broken lines and fix hyphenation. Keep citation markers like [3] as they are.\n",
    "  \"latex\": LaTeX source of the equation WITHOUT $$ or environments (display_math only). Use \\begin{pmatrix} for matrices.\n",
    "  \"label\": equation number such as \"(2)\", or figure/table label such as \"Fig. 1\" / \"Table 2\" (when present)\n",
    "  \"ids\": array of block ids that this element is made of, e.g. [\"B4\",\"B5\"]; consecutive ids may be written as a range \"B12-B40\". ",
    "For display_math: the ids of the equation fragments. For table: all ids of the table cells (not the caption). ",
    "For figure: ids of text INSIDE the drawing (axis labels, node labels); may be empty. For everything else: the ids of its text.\n",
    "  \"continues\": true when the first paragraph/list/references entry of this page continues an element cut at the end of the previous page\n",
    "  \"unfinished\": true when the last paragraph/list/references entry of this page is cut at the page bottom\n",
    If[translateQ,
      "  \"translation\": the \"text\" translated into " <> lang <> ", keeping the same inline LaTeX $...$, citation markers, names and labels untouched. " <>
      "Provide it for abstract, paragraph, list, caption, footnote. Omit it for title, authors, affiliation, keywords, heading, references, display_math. " <>
      If[StringTrim[directive] =!= "", "Translation directive: " <> directive <> "\n", "\n"] <> dictPrompt,
      ""],
    "  \"bib\": for type \"references\" only: {\"key\": short ascii key like \"lecuyer1996\", \"author\": \"...\", \"year\": \"...\", \"title\": \"...\"}\n",
    "Rules:\n",
    "  - Do not drop body text. Mark running headers, page numbers and footnotes as page_header / footnote (they will be removed).\n",
    "  - One paragraph per \"paragraph\" block. One reference entry per \"references\" block. A list is one \"list\" block with one item per line, keeping bullets/numbers.\n",
    "  - A caption is its own \"caption\" block placed right before or after its figure/table block, in the order of the page.\n",
    "  - Keep display equations as display_math even when the text layer garbled them; reconstruct the LaTeX from context and the image.\n",
    "  - Output valid JSON only, no comments, no markdown fences.\n",
    If[hasBlocks, "\nText blocks:\n" <> blocksText, ""]];

(* LLM 応答のブロック配列を正規化し、座標を付ける *)
iDocPaperNormalizeBlocks[parsed_, pageBlocks_List, p_Integer] :=
  Module[{arr, blockById, norm},
    arr = Which[
      AssociationQ[parsed], Lookup[parsed, "blocks", {}],
      ListQ[parsed], parsed,
      True, {}];
    If[!ListQ[arr], arr = {}];
    blockById = Association[Map[(#["id"] -> #) &, pageBlocks]];
    norm = Map[Function[b,
      If[!AssociationQ[b], Nothing,
        Module[{ids = iDocPaperIds[Lookup[b, "ids", {}]], rects, type},
          type = ToLowerCase[iDocPaperStr[Lookup[b, "type", "paragraph"]]];
          rects = Map[Lookup[blockById, #, Nothing] &, ids];
          <|"type" -> type,
            "level" -> Replace[Lookup[b, "level", 1], {x_Real :> Round[x], Except[_Integer] -> 1}],
            "text" -> iDocPaperStr[Lookup[b, "text", ""]],
            "latex" -> iDocPaperStr[Lookup[b, "latex", ""]],
            "label" -> iDocPaperStr[Lookup[b, "label", ""]],
            "ids" -> ids,
            "continues" -> iDocPaperBool[Lookup[b, "continues", False]],
            "unfinished" -> iDocPaperBool[Lookup[b, "unfinished", False]],
            "translation" -> iDocPaperStr[Lookup[b, "translation", ""]],
            "bib" -> Replace[Lookup[b, "bib", None], Except[_Association] -> None],
            "Page" -> p,
            "Pages" -> {p},
            "Region" -> iDocPaperUnionRect[rects]|>]]], arr];
    norm];

(* 矩形 (Left/Top/Right/Bottom) の和集合。座標の無いブロックは無視。空なら None *)
iDocPaperUnionRect[rectsIn_List] :=
  Module[{rects = Select[rectsIn, AssociationQ[#] && iDocPaperGeomQ[#] &]},
    If[Length[rects] === 0, None,
      <|"Left" -> Min[#["Left"] & /@ rects], "Right" -> Max[#["Right"] & /@ rects],
        "Top" -> Max[#["Top"] & /@ rects], "Bottom" -> Min[#["Bottom"] & /@ rects]|>]];

(* ============================================================
   公開: 1 ページ解析
   ============================================================ *)

DocPaperAnalyzePage[pdf_String, p_Integer, opts:OptionsPattern[]] :=
  Module[{cfg, nPages},
    If[!FileExistsQ[pdf], Message[DocImportPaper::nofile, pdf]; Return[$Failed]];
    nPages = Quiet[Import[pdf, "PageCount"]];
    If[!IntegerQ[nPages], Message[DocImportPaper::nopages, pdf]; Return[$Failed]];
    cfg = iDocPaperConfig[{opts}, Options[DocPaperAnalyzePage]];
    iDocPaperAnalyzePageImpl[pdf, p, nPages, cfg]];

(* オプション → 設定 Association。opts が先、defaults が後 (Lookup は最初の一致を返す) *)
$iDocPaperAllDefaults = {
  "TargetLanguage" -> Automatic, "Translate" -> True, "Reconstruct" -> True, "Pages" -> All,
  "ImageResolution" -> 150, "MathMode" -> "Auto", "Vision" -> Automatic, "OutputPath" -> Automatic,
  "Open" -> True, "Save" -> True, "CloudPublishable" -> None, "Directive" -> Automatic,
  "Dictionary" -> {}, "HeadingStyles" -> Automatic, "Verbose" -> True, "VisionTimeout" -> Automatic,
  Fallback -> False, Model -> Automatic, Timeout -> Automatic};

(* 画像付き試行の打ち切り秒数。Automatic はプロバイダで変える:
   ローカル (lmstudio / llamacpp / freetoken) は 27B 級モデルで 1 ページ 11 分かかった実測 (2026-09-05,
   qwen3.8-27b, 70 ブロック + 画像) があるので 1500 秒、クラウド / CLI は 600 秒。 *)
iDocPaperResolveVisionTimeout[spec_, modelOpt_] :=
  Module[{provider},
    If[NumericQ[spec], Return[spec]];
    provider = Which[
      ListQ[modelOpt] && Length[modelOpt] >= 1 && StringQ[modelOpt[[1]]], ToLowerCase[modelOpt[[1]]],
      ListQ[ClaudeCode`$ClaudeModel] && Length[ClaudeCode`$ClaudeModel] >= 1 && StringQ[ClaudeCode`$ClaudeModel[[1]]],
        ToLowerCase[ClaudeCode`$ClaudeModel[[1]]],
      True, ""];
    If[MemberQ[{"lmstudio", "llamacpp", "freetoken"}, provider], 1500, 600]];

iDocPaperConfig[opts_List, defaults_List] :=
  Module[{all, get, lang, directive},
    all = Join[Flatten[opts], defaults, $iDocPaperAllDefaults];
    get = Function[name, Lookup[all, name, Lookup[$iDocPaperAllDefaults, name]]];
    lang = iDocPaperTargetLanguage[get["TargetLanguage"]];
    directive = get["Directive"];
    <|"TargetLanguage" -> lang,
      "Translate" -> TrueQ[get["Translate"]],
      "Reconstruct" -> TrueQ[get["Reconstruct"]],
      "Pages" -> get["Pages"],
      "ImageResolution" -> Replace[get["ImageResolution"], Except[_?NumericQ] -> 150],
      "MathMode" -> Replace[get["MathMode"], Except["Auto" | "Image" | "Text"] -> "Auto"],
      "Vision" -> Replace[get["Vision"], Automatic -> True],
      "Directive" -> If[StringQ[directive], directive, iDocPaperDefaultDirective[lang]],
      "Dictionary" -> Replace[get["Dictionary"], Except[_List] -> {}],
      "HeadingStyles" -> iDocPaperHeadingStyles[get["HeadingStyles"]],
      "OutputPath" -> get["OutputPath"],
      "Open" -> TrueQ[get["Open"]],
      "Save" -> TrueQ[get["Save"]],
      "CloudPublishable" -> get["CloudPublishable"],
      "Verbose" -> TrueQ[get["Verbose"]],
      "VisionTimeout" -> iDocPaperResolveVisionTimeout[get["VisionTimeout"], get[Model]],
      "Fallback" -> TrueQ[get[Fallback]],
      "Model" -> get[Model],
      "Timeout" -> get[Timeout]|>];

iDocPaperAnalyzePageImpl[pdf_String, p_Integer, nPages_Integer, cfg_Association] :=
  Module[{pageBlocks, img, blocksText, hasBlocks, prompt, resp, parsed, norm, plain, lang},
    lang = cfg["TargetLanguage"];
    iDocPaperLog[cfg["Verbose"], "ページ " <> ToString[p] <> "/" <> ToString[nPages] <> " を抽出中..."];
    pageBlocks = iDocPaperPageBlocks[pdf, p];
    hasBlocks = Length[pageBlocks] > 0;
    img = iDocPaperPageImage[pdf, p, cfg["ImageResolution"]];
    blocksText = If[hasBlocks, iDocPaperBlocksToPrompt[pageBlocks],
      With[{t = iDocPaperPagePlainText[pdf, p]},
        If[t =!= "", "[B1] " <> StringReplace[t, "\n" -> " / "] <> "\n", ""]]];
    If[!hasBlocks && blocksText =!= "",
      (* 座標なしでも id 1 のブロックとして扱う *)
      pageBlocks = {<|"id" -> 1, "text" -> iDocPaperPagePlainText[pdf, p],
        "Left" -> 0, "Right" -> 0, "Top" -> 0, "Bottom" -> 0|>};
      hasBlocks = True];
    prompt = iDocPaperAnalysisPrompt[p, nPages, blocksText, hasBlocks,
      TrueQ[cfg["Vision"]] && ImageQ[img], cfg["Translate"], lang,
      cfg["Directive"], iDocPaperDictionaryPrompt[cfg["Dictionary"]]];
    iDocPaperLog[cfg["Verbose"], "ページ " <> ToString[p] <> " を LLM で構造解析中 (" <>
      ToString[Length[pageBlocks]] <> " ブロック" <>
      If[TrueQ[cfg["Vision"]] && ImageQ[img], ", 画像付き", ""] <> ")..."];
    resp = iDocPaperQueryMaybeVision[prompt, If[TrueQ[cfg["Vision"]], img, $Failed], cfg];
    If[resp === $Failed, Return[$Failed]];
    parsed = iDocPaperParseJSON[resp];
    If[parsed === $Failed,
      iDocPaperLog[cfg["Verbose"], "JSON を読めません。JSON のみで再依頼します。"];
      resp = iDocPaperQuery[{prompt <> "\n\nYour previous answer was not valid JSON. Return the JSON object only."}, cfg];
      parsed = If[resp === $Failed, $Failed, iDocPaperParseJSON[resp]]];
    If[parsed === $Failed, Message[DocImportPaper::json, p]; Return[$Failed]];
    norm = iDocPaperNormalizeBlocks[parsed, pageBlocks, p];
    (* 図表・数式の切り出し用に、ページ情報を各ブロックへ添える。
       PageClaimedIds = このページで LLM が何らかの要素 (ヘッダ・脚注を含む) に割り当てた全ブロック id。
       図表の切り出し境界候補になる (後で落とされる page_header も境界としては要る)。 *)
    With[{allIds = Union @@ Map[#["ids"] &, norm]},
      norm = Map[Append[#, {"PageBlocks" -> pageBlocks, "PageImage" -> img, "PageClaimedIds" -> allIds,
        "Language" -> If[AssociationQ[parsed], iDocPaperStr[Lookup[parsed, "language", ""]], ""]}] &, norm]];
    $DocPaperLastAnalysis = Append[$DocPaperLastAnalysis,
      {"PDF" -> pdf, "LastPage" -> p, "LastPageBlocks" -> norm}];
    norm];

(* ============================================================
   ページ間の結合とメタ除去
   ============================================================ *)

$iDocPaperDropTypes = {"page_header", "footnote", "other"};
$iDocPaperMergeableTypes = {"paragraph", "list", "references", "abstract"};

iDocPaperMergeAllPages[pageResults_List, lang_String] :=
  Module[{all, out = {}, sep = iDocPaperJoinSep[lang]},
    all = Flatten[Select[pageResults, ListQ], 1];
    all = Select[all, AssociationQ[#] && !MemberQ[$iDocPaperDropTypes, #["type"]] &];
    Do[
      If[TrueQ[b["continues"]] && Length[out] > 0 &&
         MemberQ[$iDocPaperMergeableTypes, b["type"]] &&
         MemberQ[$iDocPaperMergeableTypes, out[[-1, "type"]]] &&
         out[[-1, "Page"]] =!= b["Page"],
        out[[-1]] = iDocPaperMergeTwo[out[[-1]], b, sep],
        AppendTo[out, b]],
      {b, all}];
    out];

iDocPaperJoinText[a_String, b_String, sep_String] :=
  Which[
    StringTrim[a] === "", b,
    StringTrim[b] === "", a,
    StringEndsQ[StringTrim[a], "-"], StringDrop[StringTrim[a], -1] <> StringTrim[b],
    True, StringTrim[a] <> " " <> StringTrim[b]];

iDocPaperMergeTwo[a_Association, b_Association, sep_String] :=
  Module[{m = a},
    m["text"] = iDocPaperJoinText[a["text"], b["text"], " "];
    m["translation"] = If[StringTrim[a["translation"]] === "" || StringTrim[b["translation"]] === "",
      a["translation"] <> b["translation"],
      StringTrim[a["translation"]] <> sep <> StringTrim[b["translation"]]];
    m["Pages"] = DeleteDuplicates[Join[a["Pages"], b["Pages"]]];
    m["unfinished"] = b["unfinished"];
    m];

(* ============================================================
   画像切り出し (PDF pt → ページ画像の画素)
   ============================================================ *)

(* rect: <|"Left","Top","Right","Bottom"|> (pt)。margin は pt (数値 = 四方同じ、{mx, my} = 横・縦)。 *)
iDocPaperCropRect[img_?ImageQ, res_?NumericQ, rect_Association, margin_] :=
  Module[{w, h, k, hPt, c0, c1, r0, r1, mx, my},
    {mx, my} = Replace[margin, {{x_?NumericQ, y_?NumericQ} :> {x, y}, m_?NumericQ :> {m, m}, _ -> {0, 0}}];
    {w, h} = ImageDimensions[img];
    k = N[res / 72];
    hPt = h / k;
    c0 = Clip[Floor[(rect["Left"] - mx) k], {1, w}];
    c1 = Clip[Ceiling[(rect["Right"] + mx) k], {1, w}];
    r0 = Clip[Floor[(hPt - rect["Top"] - my) k], {1, h}];
    r1 = Clip[Ceiling[(hPt - rect["Bottom"] + my) k], {1, h}];
    If[c1 - c0 < 8 || r1 - r0 < 4, Return[$Failed]];
    Quiet @ Check[ImageTake[img, {r0, r1}, {c0, c1}], $Failed]];

iDocPaperCropRect[___] := $Failed;

(* ページの本文カラム幅 (左端・右端) *)
iDocPaperColumnExtent[pageBlocksIn_List] :=
  Module[{pageBlocks = Select[pageBlocksIn, iDocPaperGeomQ], lefts, rights},
    If[Length[pageBlocks] === 0, Return[{0, 0}]];
    lefts = #["Left"] & /@ pageBlocks;
    rights = #["Right"] & /@ pageBlocks;
    {Min[lefts], Max[rights]}];

(* 要素 (図・表・数式) の切り出し領域を決める。
   - display_math: ids の矩形の和集合を本文カラム幅へ広げる
   - 図・表: 「他の要素 (段落・見出し・別のキャプション等) が使っているブロック」だけを境界候補にし、
     要素の基準位置 (ids の矩形、無ければキャプションの縁) から上下に最も近い境界までを領域とする。
     図の内部ラベルはどの要素にも属さないので境界にならない (boundaryIds に無い)。
     boundaryIds が空 (LLM が ids を返さなかった) なら、カラム幅の 40% 以上の幅を持つブロックを境界候補にする。 *)
iDocPaperElementRegion[elem_Association, caption_, captionBefore_, boundaryIds_List] :=
  Module[{pageBlocks = elem["PageBlocks"], reg = elem["Region"], excl, xL, xR, colW, cands,
          refTop, refBottom, above, below, capRect, top, bottom},
    If[!ListQ[pageBlocks] || Length[pageBlocks] === 0, Return[None]];
    {xL, xR} = iDocPaperColumnExtent[pageBlocks];
    colW = Max[xR - xL, 1];
    capRect = If[AssociationQ[caption], caption["Region"], None];
    excl = Join[elem["ids"], If[AssociationQ[caption], caption["ids"], {}]];
    (* テキストブロックの Top は 1 行目の文字上端付近、Bottom は最終行のベースライン付近。
       要素自身の矩形は上 6pt / 下 4pt 広げ (上付き・下付き・ディセンダ)、
       隣接要素で決まる境界は広げない (隣の行が写り込む)。 *)
    If[elem["type"] === "display_math",
      If[!AssociationQ[reg], Return[None]];
      Return[<|"Left" -> Min[xL, reg["Left"]], "Right" -> Max[xR, reg["Right"]],
               "Top" -> reg["Top"] + 6, "Bottom" -> reg["Bottom"] - 4|>]];
    cands = Select[pageBlocks, iDocPaperGeomQ[#] && MemberQ[boundaryIds, #["id"]] && !MemberQ[excl, #["id"]] &];
    If[Length[cands] === 0,
      (* LLM が ids を返していない: 左端から始まる幅広のブロック (本文行らしいもの) を境界候補に *)
      cands = Select[pageBlocks, iDocPaperGeomQ[#] && !MemberQ[excl, #["id"]] &&
        (#["Right"] - #["Left"]) >= 0.6 colW && #["Left"] <= xL + 0.1 colW &]];
    {refTop, refBottom} = Which[
      AssociationQ[reg], {reg["Top"], reg["Bottom"]},
      AssociationQ[capRect] && TrueQ[captionBefore], {capRect["Bottom"] - 1, capRect["Bottom"] - 1},
      AssociationQ[capRect], {capRect["Top"] + 1, capRect["Top"] + 1},
      True, Return[None]];
    above = Select[cands, #["Bottom"] >= refTop &];
    below = Select[cands, #["Top"] <= refBottom &];
    top = If[Length[above] > 0, Min[#["Bottom"] & /@ above], Max[#["Top"] & /@ pageBlocks] + 20];
    bottom = If[Length[below] > 0, Max[#["Top"] & /@ below], Min[#["Bottom"] & /@ pageBlocks] - 20];
    (* キャプションで境を切る *)
    If[AssociationQ[capRect],
      If[TrueQ[captionBefore], top = Min[top, capRect["Bottom"]], bottom = Max[bottom, capRect["Top"]]]];
    (* 境界のすぐ内側まで (隣の行を入れない) *)
    top -= 1; bottom += 1;
    (* ids の矩形は必ず含める *)
    If[AssociationQ[reg], top = Max[top, reg["Top"] + 6]; bottom = Min[bottom, reg["Bottom"] - 4]];
    If[top - bottom < 10, Return[None]];
    <|"Left" -> xL, "Right" -> xR, "Top" -> top, "Bottom" -> bottom|>];

iDocPaperCropElement[elem_Association, caption_, captionBefore_, res_, boundaryIds_List] :=
  Module[{region = iDocPaperElementRegion[elem, caption, captionBefore, boundaryIds], img = elem["PageImage"]},
    If[!AssociationQ[region] || !ImageQ[img], Return[$Failed]];
    (* 縦方向の余白は領域計算で済んでいる。横だけ少し広げる *)
    iDocPaperCropRect[img, res, region, {6, 0}]];

(* ============================================================
   LaTeX → ボックス
   ============================================================ *)

iDocPaperNamedChar[name_String] :=
  Quiet @ Check[ToExpression["\"\\[" <> name <> "]\""], name];

$iDocPaperTeXSymbols = <|
  "alpha" -> "\[Alpha]", "beta" -> "\[Beta]", "gamma" -> "\[Gamma]", "delta" -> "\[Delta]",
  "epsilon" -> "\[Epsilon]", "varepsilon" -> "\[CurlyEpsilon]", "zeta" -> "\[Zeta]", "eta" -> "\[Eta]",
  "theta" -> "\[Theta]", "vartheta" -> "\[CurlyTheta]", "iota" -> "\[Iota]", "kappa" -> "\[Kappa]",
  "lambda" -> "\[Lambda]", "mu" -> "\[Mu]", "nu" -> "\[Nu]", "xi" -> "\[Xi]", "pi" -> "\[Pi]",
  "varpi" -> "\[CurlyPi]", "rho" -> "\[Rho]", "varrho" -> "\[CurlyRho]", "sigma" -> "\[Sigma]",
  "varsigma" -> "\[FinalSigma]", "tau" -> "\[Tau]", "upsilon" -> "\[Upsilon]", "phi" -> "\[Phi]",
  "varphi" -> "\[CurlyPhi]", "chi" -> "\[Chi]", "psi" -> "\[Psi]", "omega" -> "\[Omega]",
  "Gamma" -> "\[CapitalGamma]", "Delta" -> "\[CapitalDelta]", "Theta" -> "\[CapitalTheta]",
  "Lambda" -> "\[CapitalLambda]", "Xi" -> "\[CapitalXi]", "Pi" -> "\[CapitalPi]", "Sigma" -> "\[CapitalSigma]",
  "Upsilon" -> "\[CapitalUpsilon]", "Phi" -> "\[CapitalPhi]", "Psi" -> "\[CapitalPsi]", "Omega" -> "\[CapitalOmega]",
  "ell" -> "\[ScriptL]", "hbar" -> "\[HBar]", "infty" -> "\[Infinity]", "partial" -> "\[PartialD]",
  "nabla" -> "\[Del]", "emptyset" -> "\[EmptySet]", "varnothing" -> "\[EmptySet]",
  "cdot" -> "\[CenterDot]", "cdots" -> "\[CenterEllipsis]", "ldots" -> "\[Ellipsis]", "dots" -> "\[Ellipsis]",
  "vdots" -> "\[VerticalEllipsis]", "ddots" -> "\[DescendingEllipsis]",
  "times" -> "\[Times]", "div" -> "\[Divide]", "pm" -> "\[PlusMinus]", "mp" -> "\[MinusPlus]",
  "oplus" -> "\[CirclePlus]", "otimes" -> "\[CircleTimes]", "odot" -> "\[CircleDot]", "ominus" -> "\[CircleMinus]",
  "circ" -> "\[SmallCircle]", "bullet" -> "\[Bullet]", "ast" -> "*", "star" -> "\[Star]",
  "in" -> "\[Element]", "notin" -> "\[NotElement]", "ni" -> "\[ReverseElement]",
  "cup" -> "\[Union]", "cap" -> "\[Intersection]", "bigcup" -> "\[Union]", "bigcap" -> "\[Intersection]",
  "subset" -> "\[Subset]", "subseteq" -> "\[SubsetEqual]", "supset" -> "\[Superset]", "supseteq" -> "\[SupersetEqual]",
  "setminus" -> "\[Backslash]",
  "le" -> "\[LessEqual]", "leq" -> "\[LessEqual]", "leqslant" -> "\[LessSlantEqual]",
  "ge" -> "\[GreaterEqual]", "geq" -> "\[GreaterEqual]", "geqslant" -> "\[GreaterSlantEqual]",
  "ne" -> "\[NotEqual]", "neq" -> "\[NotEqual]", "ll" -> "\[LessLess]", "gg" -> "\[GreaterGreater]",
  "approx" -> "\[TildeTilde]", "simeq" -> "\[TildeEqual]", "sim" -> "\[Tilde]", "cong" -> "\[TildeFullEqual]",
  "equiv" -> "\[Congruent]", "propto" -> "\[Proportional]", "perp" -> "\[UpTee]", "parallel" -> "\[DoubleVerticalBar]",
  "mid" -> "|", "vert" -> "|", "Vert" -> "\[DoubleVerticalBar]",
  "to" -> "\[RightArrow]", "rightarrow" -> "\[RightArrow]", "leftarrow" -> "\[LeftArrow]",
  "longrightarrow" -> "\[LongRightArrow]", "leftrightarrow" -> "\[LeftRightArrow]",
  "Rightarrow" -> "\[Implies]", "Leftarrow" -> "\[DoubleLeftArrow]", "Leftrightarrow" -> "\[Equivalent]",
  "mapsto" -> "\[RightTeeArrow]", "uparrow" -> "\[UpArrow]", "downarrow" -> "\[DownArrow]",
  "forall" -> "\[ForAll]", "exists" -> "\[Exists]", "nexists" -> "\[NotExists]",
  "land" -> "\[And]", "wedge" -> "\[And]", "lor" -> "\[Or]", "vee" -> "\[Or]", "neg" -> "\[Not]", "lnot" -> "\[Not]",
  "lfloor" -> "\[LeftFloor]", "rfloor" -> "\[RightFloor]", "lceil" -> "\[LeftCeiling]", "rceil" -> "\[RightCeiling]",
  "langle" -> "\[LeftAngleBracket]", "rangle" -> "\[RightAngleBracket]",
  "lbrace" -> "{", "rbrace" -> "}", "lbrack" -> "[", "rbrack" -> "]",
  "prime" -> "\[Prime]", "angle" -> "\[Angle]", "triangle" -> "\[EmptyUpTriangle]", "square" -> "\[EmptySquare]",
  "sum" -> "\[Sum]", "prod" -> "\[Product]", "int" -> "\[Integral]", "oint" -> "\[ContourIntegral]",
  "iint" -> "\[Integral]\[Integral]",
  "quad" -> "  ", "qquad" -> "    ", "," -> " ", ";" -> " ", ":" -> " ", "!" -> "", " " -> " ",
  "{" -> "{", "}" -> "}", "|" -> "\[DoubleVerticalBar]", "_" -> "_", "%" -> "%", "&" -> "&", "#" -> "#", "$" -> "$",
  "backslash" -> "\\", "colon" -> ":",
  "log" -> "log", "ln" -> "ln", "exp" -> "exp", "sin" -> "sin", "cos" -> "cos", "tan" -> "tan",
  "arcsin" -> "arcsin", "arccos" -> "arccos", "arctan" -> "arctan", "sinh" -> "sinh", "cosh" -> "cosh", "tanh" -> "tanh",
  "min" -> "min", "max" -> "max", "gcd" -> "gcd", "lcm" -> "lcm", "det" -> "det", "dim" -> "dim",
  "deg" -> "deg", "ker" -> "ker", "sup" -> "sup", "inf" -> "inf", "lim" -> "lim", "arg" -> "arg",
  "mod" -> "mod", "bmod" -> "mod", "pmod" -> "mod", "Pr" -> "Pr", "Re" -> "Re", "Im" -> "Im",
  "left" -> "", "right" -> "", "displaystyle" -> "", "textstyle" -> "", "scriptstyle" -> "",
  "nonumber" -> "", "notag" -> "", "limits" -> "", "nolimits" -> "", "big" -> "", "Big" -> "", "bigg" -> "", "Bigg" -> "",
  "bigl" -> "", "bigr" -> "", "Bigl" -> "", "Bigr" -> "", "biggl" -> "", "biggr" -> "", "Biggl" -> "", "Biggr" -> "",
  "rm" -> "", "it" -> "", "bf" -> "", "cal" -> "", "tt" -> "", "sf" -> ""
|>;

$iDocPaperTeXAccents = <|
  "hat" -> "^", "widehat" -> "^", "bar" -> "_", "overline" -> "_", "tilde" -> "~", "widetilde" -> "~",
  "vec" -> "\[RightVector]", "dot" -> ".", "ddot" -> "..", "check" -> "\[Breve]", "breve" -> "\[Breve]"
|>;

(* 前処理: 環境や $$ を剥がし、行列環境を \pmatrix{...} 相当に整える *)
iDocPaperNormalizeTeX[tex_String] :=
  Module[{t = StringTrim[tex]},
    t = StringReplace[t, {
      RegularExpression["^\\$\\$"] -> "", RegularExpression["\\$\\$$"] -> "",
      RegularExpression["^\\$"] -> "", RegularExpression["\\$$"] -> "",
      RegularExpression["^\\\\\\["] -> "", RegularExpression["\\\\\\]$"] -> "",
      RegularExpression["^\\\\\\("] -> "", RegularExpression["\\\\\\)$"] -> "",
      RegularExpression["\\\\begin\\{(equation|align|gather|multline|eqnarray|displaymath|math)\\*?\\}"] -> "",
      RegularExpression["\\\\end\\{(equation|align|gather|multline|eqnarray|displaymath|math)\\*?\\}"] -> "",
      RegularExpression["\\\\(label|tag)\\{[^}]*\\}"] -> "",
      "\\nonumber" -> "", "\\notag" -> ""}];
    StringTrim[t]];

(* --- Tier 1: TeXForm パーサ --- *)
iDocPaperTeXViaTeXForm[t_String] :=
  Module[{e, b},
    e = Quiet[ToExpression[t, TeXForm, HoldForm]];
    If[e === $Failed || !FreeQ[e, $Failed], Return[$Failed]];
    b = Quiet @ Check[ToBoxes[e, TraditionalForm], $Failed];
    If[b === $Failed, Return[$Failed]];
    b = b //. {TagBox[x_, HoldForm] :> x, FormBox[x_, TraditionalForm] :> x};
    (* FE の無いカーネルでは一部の演算子が ASCII 表記で出る。名前付き文字へ戻す *)
    b = b /. $iDocPaperAsciiOperatorFix];

$iDocPaperAsciiOperatorFix = {
  "==" -> "=", "(+)" -> "\[CirclePlus]", "(x)" -> "\[CircleTimes]", "(.)" -> "\[CircleDot]",
  "~=" -> "\[TildeEqual]", "~~" -> "\[TildeTilde]", "!=" -> "\[NotEqual]",
  "<=" -> "\[LessEqual]", ">=" -> "\[GreaterEqual]", "->" -> "\[RightArrow]", "<->" -> "\[LeftRightArrow]",
  "&&" -> "\[And]", "||" -> "\[Or]", "===" -> "\[Congruent]"};

(* --- Tier 2: 簡易 LaTeX パーサ --- *)

(* トークン化: {"cmd", name} | {"char", c} | {"open"} | {"close"} | {"sup"} | {"sub"} | {"amp"} | {"newline"} *)
iDocPaperTeXTokenize[t_String] :=
  Module[{chars = Characters[t], i = 1, n, toks = {}, c, name},
    n = Length[chars];
    While[i <= n,
      c = chars[[i]];
      Which[
        c === "\\",
          If[i + 1 <= n && chars[[i + 1]] === "\\",
            AppendTo[toks, {"newline"}]; i += 2,
            If[i + 1 <= n && LetterQ[chars[[i + 1]]],
              name = "";
              i += 1;
              While[i <= n && LetterQ[chars[[i]]], name = name <> chars[[i]]; i += 1];
              AppendTo[toks, {"cmd", name}],
              If[i + 1 <= n, AppendTo[toks, {"cmd", chars[[i + 1]]}]; i += 2, i += 1]]],
        c === "{", AppendTo[toks, {"open"}]; i += 1,
        c === "}", AppendTo[toks, {"close"}]; i += 1,
        c === "^", AppendTo[toks, {"sup"}]; i += 1,
        c === "_", AppendTo[toks, {"sub"}]; i += 1,
        c === "&", AppendTo[toks, {"amp"}]; i += 1,
        c === " " || c === "\t" || c === "\n" || c === "\r",
          (* 空白はトークンとして残す (\text{...} の中で使う)。連続は 1 個に *)
          If[toks === {} || Last[toks] =!= {"space"}, AppendTo[toks, {"space"}]]; i += 1,
        DigitQ[c],
          name = "";
          While[i <= n && (DigitQ[chars[[i]]] || (chars[[i]] === "." && i + 1 <= n && DigitQ[chars[[i + 1]]])),
            name = name <> chars[[i]]; i += 1];
          AppendTo[toks, {"char", name}],
        True, AppendTo[toks, {"char", c}]; i += 1]];
    toks];

(* パーサ状態は $iDocPaperToks / $iDocPaperPos (Module 内で Block) *)
iDocPaperTeXParse[t_String] :=
  Block[{$iDocPaperToks = iDocPaperTeXTokenize[t], $iDocPaperPos = 1, out},
    out = iDocPaperParseSeq[False];
    If[out === $Failed, $Failed, iDocPaperRow[out]]];

iDocPaperRow[items_List] :=
  Module[{clean = DeleteCases[items, "" | Null]},
    Which[Length[clean] === 0, "", Length[clean] === 1, First[clean], True, RowBox[clean]]];

iDocPaperPeek[] := If[$iDocPaperPos <= Length[$iDocPaperToks], $iDocPaperToks[[$iDocPaperPos]], None];
iDocPaperNext[] := Module[{tk = iDocPaperPeek[]}, $iDocPaperPos += 1; tk];
iDocPaperSkipSpaces[] := While[iDocPaperPeek[] === {"space"}, iDocPaperNext[]];

(* 列: inGroup が True なら "close" で止まる *)
iDocPaperParseSeq[inGroup_] :=
  Module[{items = {}, tk, atom, rows = {}, cells = {}, sawAmp = False},
    While[(tk = iDocPaperPeek[]) =!= None,
      Which[
        tk === {"close"},
          If[inGroup, iDocPaperNext[]; Break[], iDocPaperNext[]],
        tk === {"amp"},
          iDocPaperNext[]; sawAmp = True;
          AppendTo[cells, iDocPaperRow[items]]; items = {},
        tk === {"newline"},
          iDocPaperNext[];
          AppendTo[cells, iDocPaperRow[items]]; items = {};
          AppendTo[rows, cells]; cells = {},
        True,
          atom = iDocPaperParseAtom[];
          If[atom === $Failed, Return[$Failed]];
          atom = iDocPaperParseScripts[atom];
          AppendTo[items, atom]]];
    If[Length[rows] > 0 || sawAmp,
      AppendTo[cells, iDocPaperRow[items]];
      AppendTo[rows, cells];
      rows = Select[rows, Length[#] > 0 &];
      With[{w = Max[Length /@ rows]},
        {GridBox[Map[PadRight[#, w, ""] &, rows]]}],
      items]];

(* 直後の ^ / _ を吸収 *)
iDocPaperParseScripts[base_] :=
  Module[{sup = None, sub = None, tk, arg},
    iDocPaperSkipSpaces[];
    While[(tk = iDocPaperPeek[]) === {"sup"} || tk === {"sub"},
      iDocPaperNext[];
      arg = iDocPaperParseArg[];
      If[arg === $Failed, Return[$Failed]];
      If[tk === {"sup"}, sup = arg, sub = arg]];
    Which[
      sup === None && sub === None, base,
      MatchQ[base, "\[Sum]" | "\[Product]" | "\[Integral]" | "\[Union]" | "\[Intersection]" | "lim" | "max" | "min" | "sup" | "inf"],
        Which[
          sup =!= None && sub =!= None, UnderoverscriptBox[base, sub, sup],
          sub =!= None, UnderscriptBox[base, sub],
          True, OverscriptBox[base, sup]],
      sup =!= None && sub =!= None, SubsuperscriptBox[base, sub, sup],
      sub =!= None, SubscriptBox[base, sub],
      True, SuperscriptBox[base, sup]]];

(* 引数 1 個: {group} または単一トークン *)
iDocPaperParseArg[] :=
  Module[{tk},
    iDocPaperSkipSpaces[];
    tk = iDocPaperPeek[];
    Which[
      tk === None, $Failed,
      tk === {"open"}, iDocPaperNext[]; iDocPaperRow[iDocPaperParseSeq[True]],
      True, iDocPaperParseAtom[]]];

(* 省略可能引数 [..] を読む。無ければ None *)
iDocPaperParseOptArg[] :=
  Module[{items = {}, tk},
    iDocPaperSkipSpaces[];
    If[iDocPaperPeek[] =!= {"char", "["}, Return[None]];
    iDocPaperNext[];
    While[(tk = iDocPaperPeek[]) =!= None && tk =!= {"char", "]"},
      AppendTo[items, iDocPaperParseScripts[iDocPaperParseAtom[]]]];
    If[tk === {"char", "]"}, iDocPaperNext[]];
    iDocPaperRow[items]];

(* 中括弧グループを生文字列として読む (環境名など)。無ければ "" *)
iDocPaperReadRawGroup[] :=
  Module[{tk, depth = 0, out = ""},
    iDocPaperSkipSpaces[];
    If[iDocPaperPeek[] =!= {"open"}, Return[""]];
    iDocPaperNext[]; depth = 1;
    While[depth > 0 && (tk = iDocPaperNext[]) =!= None,
      Which[
        tk === {"open"}, depth += 1,
        tk === {"close"}, depth -= 1,
        tk === {"space"}, out = out <> " ",
        MatchQ[tk, {"char" | "cmd", _}], out = out <> tk[[2]],
        True, Null]];
    StringTrim[out]];

(* 環境 \begin{name} ... \end{name}: {環境名, 中身 (GridBox 1 個のリスト or {})} *)
iDocPaperParseEnvBody[] :=
  Module[{envName, inner},
    envName = iDocPaperReadRawGroup[];
    If[StringContainsQ[envName, "array" | "tabular"], iDocPaperReadRawGroup[]];  (* 列指定 {cc} を捨てる *)
    inner = iDocPaperParseSeqUntilEnd[];
    If[iDocPaperPeek[] === {"cmd", "end"}, iDocPaperNext[]; iDocPaperReadRawGroup[]];
    {envName, inner}];

iDocPaperParseSeqUntilEnd[] :=
  Module[{items = {}, tk, rows = {}, cells = {}},
    While[(tk = iDocPaperPeek[]) =!= None && tk =!= {"cmd", "end"},
      Which[
        tk === {"amp"}, iDocPaperNext[]; AppendTo[cells, iDocPaperRow[items]]; items = {},
        tk === {"newline"}, iDocPaperNext[]; AppendTo[cells, iDocPaperRow[items]]; items = {};
          AppendTo[rows, cells]; cells = {},
        tk === {"close"}, iDocPaperNext[],
        True, AppendTo[items, iDocPaperParseScripts[iDocPaperParseAtom[]]]]];
    If[Length[items] > 0 || Length[cells] > 0, AppendTo[cells, iDocPaperRow[items]]; AppendTo[rows, cells]];
    rows = Select[rows, Length[#] > 0 &];
    If[Length[rows] === 0, {},
      With[{w = Max[Length /@ rows]}, {GridBox[Map[PadRight[#, w, ""] &, rows]]}]]];

iDocPaperParseAtom[] :=
  Module[{tk = iDocPaperNext[], name, a, b, opt},
    If[tk === None, Return[$Failed]];
    Switch[tk,
      {"open"}, iDocPaperRow[iDocPaperParseSeq[True]],
      {"close"}, "",
      {"sup"} | {"sub"}, (* 基底なし: 空基底 *)
        With[{arg = iDocPaperParseArg[]},
          If[tk === {"sup"}, SuperscriptBox["", arg], SubscriptBox["", arg]]],
      {"amp"} | {"newline"} | {"space"}, "",
      {"char", _}, tk[[2]],
      {"cmd", _},
        name = tk[[2]];
        Which[
          name === "frac" || name === "dfrac" || name === "tfrac",
            a = iDocPaperParseArg[]; b = iDocPaperParseArg[];
            If[a === $Failed || b === $Failed, $Failed, FractionBox[a, b]],
          name === "binom",
            a = iDocPaperParseArg[]; b = iDocPaperParseArg[];
            RowBox[{"(", GridBox[{{a}, {b}}], ")"}],
          name === "sqrt",
            opt = iDocPaperParseOptArg[]; a = iDocPaperParseArg[];
            If[opt === None, SqrtBox[a], RadicalBox[a, opt]],
          name === "text" || name === "mathrm" || name === "textrm" || name === "operatorname" ||
            name === "mathit" || name === "textit" || name === "mathsf" || name === "mathtt",
            (* 中身は生文字列 (空白を保つ)。{ } が無ければ通常の引数 *)
            iDocPaperSkipSpaces[];
            a = If[iDocPaperPeek[] === {"open"}, iDocPaperReadRawGroup[], iDocPaperParseArg[]];
            StyleBox[a, FontSlant -> If[name === "mathit" || name === "textit", Italic, Plain]],
          name === "mathbf" || name === "boldsymbol" || name === "textbf" || name === "bm",
            a = iDocPaperParseArg[]; StyleBox[a, FontWeight -> Bold],
          name === "mathbb",
            a = iDocPaperParseArg[];
            If[StringQ[a] && StringLength[a] === 1 && UpperCaseQ[a],
              iDocPaperNamedChar["DoubleStruckCapital" <> a], StyleBox[a, FontWeight -> Bold]],
          name === "mathcal" || name === "mathscr",
            a = iDocPaperParseArg[];
            If[StringQ[a] && StringLength[a] === 1 && UpperCaseQ[a],
              iDocPaperNamedChar["ScriptCapital" <> a], StyleBox[a, FontSlant -> Italic]],
          name === "mathfrak",
            a = iDocPaperParseArg[];
            If[StringQ[a] && StringLength[a] === 1 && UpperCaseQ[a],
              iDocPaperNamedChar["GothicCapital" <> a], a],
          KeyExistsQ[$iDocPaperTeXAccents, name],
            a = iDocPaperParseArg[]; OverscriptBox[a, $iDocPaperTeXAccents[name]],
          name === "underline",
            a = iDocPaperParseArg[]; UnderscriptBox[a, "_"],
          name === "overset",
            a = iDocPaperParseArg[]; b = iDocPaperParseArg[]; OverscriptBox[b, a],
          name === "underset",
            a = iDocPaperParseArg[]; b = iDocPaperParseArg[]; UnderscriptBox[b, a],
          name === "stackrel",
            a = iDocPaperParseArg[]; b = iDocPaperParseArg[]; OverscriptBox[b, a],
          name === "begin",
            With[{env = iDocPaperParseEnvBody[]},
              Module[{envName = env[[1]], body = iDocPaperRow[env[[2]]]},
                Which[
                  StringQ[envName] && StringContainsQ[envName, "pmatrix"], RowBox[{"(", body, ")"}],
                  StringQ[envName] && StringContainsQ[envName, "bmatrix"], RowBox[{"[", body, "]"}],
                  StringQ[envName] && StringContainsQ[envName, "vmatrix"], RowBox[{"|", body, "|"}],
                  StringQ[envName] && StringContainsQ[envName, "Bmatrix"], RowBox[{"{", body, "}"}],
                  StringQ[envName] && StringContainsQ[envName, "cases"], RowBox[{"{", body}],
                  True, body]]],
          name === "end", "",
          name === "left" || name === "right", "",
          name === "hspace" || name === "vspace" || name === "phantom" || name === "hphantom",
            iDocPaperParseArg[]; " ",
          name === "not",
            a = iDocPaperParseArg[]; OverscriptBox[a, "/"],
          KeyExistsQ[$iDocPaperTeXSymbols, name], $iDocPaperTeXSymbols[name],
          True, name],
      _, ""]];

(* --- 公開: LaTeX → ボックス ---
   簡易パーサ (字面に忠実。項の並べ替えをしない) を先に、TeXForm パーサを後に試す。
   TeXForm 経路は式を評価して項を並べ替えたり \mathbb を落としたりするので補助扱い。 *)
iDocPaperGoodBoxesQ[b_] :=
  b =!= $Failed && FreeQ[b, $Failed] && !MatchQ[b, "" | Null | {}] &&
  FreeQ[b, _Cell | _InterpretationBox];

DocPaperTeXToBoxes[tex_String] :=
  Module[{t = iDocPaperNormalizeTeX[tex], b},
    If[t === "", Return[$Failed]];
    b = Quiet @ Check[iDocPaperTeXParse[t], $Failed];
    If[iDocPaperGoodBoxesQ[b], Return[b]];
    b = iDocPaperTeXViaTeXForm[t];
    If[iDocPaperGoodBoxesQ[b], Return[b]];
    $Failed];

DocPaperTeXToBoxes[_] := $Failed;

(* ============================================================
   本文文字列 → TextData (インライン数式埋め込み)
   ============================================================ *)

iDocPaperInlineMathCell[tex_String] :=
  Module[{b = DocPaperTeXToBoxes[tex]},
    If[b === $Failed,
      (* 変換不能: 元の LaTeX を等幅で残す *)
      StyleBox[tex, FontFamily -> "Courier New"],
      Cell[BoxData[FormBox[b, TraditionalForm]], FormatType -> TraditionalForm]]];

DocPaperTextToTextData[s_String] :=
  Module[{t = StringReplace[s, "$$" -> "$"], parts},
    If[!StringContainsQ[t, "$"] && !StringContainsQ[t, "\\("], Return[t]];
    parts = StringSplit[t, {
      "$" ~~ Shortest[x__] ~~ "$" :> iDocPaperMathTag[x],
      "\\(" ~~ Shortest[x__] ~~ "\\)" :> iDocPaperMathTag[x]}];
    parts = Map[If[MatchQ[#, iDocPaperMathTag[_]],
      With[{tex = StringTrim[First[#]]},
        If[tex === "", Nothing, iDocPaperInlineMathCell[tex]]],
      #] &, parts];
    parts = DeleteCases[parts, ""];
    Which[
      Length[parts] === 0, "",
      Length[parts] === 1 && StringQ[First[parts]], First[parts],
      True, TextData[parts]]];

DocPaperTextToTextData[x_] := iDocPaperStr[x];

(* ============================================================
   セル構築
   ============================================================ *)

iDocPaperTags[rules_List] :=
  TaggingRules -> {$iDocTagRoot -> DeleteCases[rules, _ -> None]};

iDocPaperRefSources[pdf_String, pages_List] := {{pdf, pages}};

(* 本文セル。translation が空か原文と同じなら原文のみ *)
iDocPaperTextCell[b_Association, pdf_String, style_String, extraRules_List] :=
  Module[{text = StringTrim[b["text"]], tr = StringTrim[b["translation"]], content, rules, cellOpts},
    If[tr =!= "" && tr =!= text,
      content = DocPaperTextToTextData[tr];
      rules = Join[{
        "mode" -> "translated",
        "translation" -> tr,
        "translationSrc" -> text,
        "showTranslation" -> True,
        "cleanText" -> tr}, extraRules];
      cellOpts = $iDocTranslationCellOpts,
      content = DocPaperTextToTextData[text];
      rules = Join[{"cleanText" -> text}, extraRules];
      cellOpts = {}];
    rules = Join[rules, {"refSources" -> iDocPaperRefSources[pdf, b["Pages"]], "paperType" -> b["type"]}];
    Cell[content, style, Sequence @@ cellOpts, iDocPaperTags[rules]]];

iDocPaperHeadingCell[b_Association, pdf_String, styles_List] :=
  Module[{lvl = Clip[b["level"], {1, 3}], style},
    style = styles[[lvl + 1]];
    Cell[iDocPaperPlainMath[b["text"]], style,
      iDocPaperTags[{"refSources" -> iDocPaperRefSources[pdf, b["Pages"]], "paperType" -> "heading",
        "translation" -> If[StringTrim[b["translation"]] === "", None, b["translation"]]}]]];

(* 見出し等は文字列のまま。$..$ は内容だけ残す *)
iDocPaperPlainMath[s_String] :=
  StringReplace[s, {"$$" -> "", "$" -> "", "\\(" -> "", "\\)" -> ""}];

(* 別行立て数式 *)
iDocPaperDisplayMathCell[b_Association, pdf_String, cfg_Association] :=
  Module[{latex = StringTrim[b["latex"]], label = StringTrim[b["label"]], boxes, img, rules, inner},
    If[latex === "", latex = iDocPaperPlainMath[b["text"]]];
    rules = {"paperLatex" -> latex, "paperLabel" -> If[label === "", None, label],
      "refSources" -> iDocPaperRefSources[pdf, b["Pages"]], "paperType" -> "display_math"};
    boxes = If[cfg["MathMode"] === "Image", $Failed, DocPaperTeXToBoxes[latex]];
    If[boxes =!= $Failed,
      inner = If[label === "", boxes, RowBox[{boxes, "      ", label}]];
      Return[Cell[BoxData[FormBox[inner, TraditionalForm]], "DisplayFormula", iDocPaperTags[rules]]]];
    (* 変換できない: ページ画像から切り出す *)
    If[cfg["MathMode"] =!= "Text",
      img = iDocPaperCropElement[b, None, False, cfg["ImageResolution"], {}];
      If[ImageQ[img],
        Return[Cell[BoxData[ToBoxes[img]], "Text", iDocPaperTags[Append[rules, "paperImage" -> True]]]]]];
    Cell[latex <> If[label === "", "", "    " <> label], "Text",
      FontFamily -> "Courier New", iDocPaperTags[rules]]];

(* 図・表 (画像切り出し) *)
iDocPaperFigureLabelKey[label_String, caption_String, counter_Integer] :=
  Module[{src = If[label =!= "", label, caption], m},
    m = StringCases[src, RegularExpression["(?i)^\\s*(fig(?:ure)?\\.?|table|tab\\.?)\\s*(\\d+[a-z]?)"] :> {"$1", "$2"}, 1];
    If[m =!= {},
      With[{kind = ToLowerCase[m[[1, 1]]], num = m[[1, 2]]},
        If[StringStartsQ[kind, "t"], "table" <> num, "fig" <> num]],
      "fig" <> ToString[counter]]];

iDocPaperFigureCells[b_Association, caption_, captionBefore_, pdf_String, cfg_Association, counter_Integer,
                     boundaryIds_List] :=
  Module[{img, capText, capTr, key, cells = {}, rules, capCell},
    capText = If[AssociationQ[caption], StringTrim[caption["text"]], ""];
    capTr = If[AssociationQ[caption], StringTrim[caption["translation"]], ""];
    key = iDocPaperFigureLabelKey[StringTrim[b["label"]], capText, counter];
    rules = {"figLabel" -> key, "figCaption" -> If[capText === "", None, iDocPaperPlainMath[capText]],
      "refSources" -> iDocPaperRefSources[pdf, b["Pages"]], "paperType" -> b["type"]};
    img = iDocPaperCropElement[b, caption, captionBefore, cfg["ImageResolution"], boundaryIds];
    If[!ImageQ[img] && ImageQ[b["PageImage"]],
      (* 領域が決まらない: ページ全体を貼る *)
      img = b["PageImage"]; rules = Append[rules, "paperCropFailed" -> True]];
    capCell = If[AssociationQ[caption],
      iDocPaperTextCell[caption, pdf, "Text", {"paperCaptionFor" -> key}], None];
    If[TrueQ[captionBefore] && capCell =!= None, AppendTo[cells, capCell]];
    If[ImageQ[img],
      AppendTo[cells, Cell[BoxData[ToBoxes[img]], "Text", iDocPaperTags[rules]]],
      AppendTo[cells, Cell["[" <> b["type"] <> " " <> key <> ": " <>
        iL["画像を切り出せませんでした", "image could not be cropped"] <> "]", "Text", iDocPaperTags[rules]]]];
    If[!TrueQ[captionBefore] && capCell =!= None, AppendTo[cells, capCell]];
    cells];

(* 参考文献: Text セル 1 個 + Bibliography メタセル *)
iDocPaperReferenceCells[refs_List, pdf_String] :=
  Module[{texts, bibs, pages, q, bibCell, header},
    If[Length[refs] === 0, Return[{}]];
    texts = Map[iDocPaperPlainMath[StringTrim[#["text"]]] &, refs];
    pages = DeleteDuplicates[Flatten[#["Pages"] & /@ refs]];
    header = Cell["References", "Subsection",
      iDocPaperTags[{"refSources" -> iDocPaperRefSources[pdf, pages], "paperType" -> "heading"}]];
    bibs = Select[Map[#["bib"] &, refs], AssociationQ];
    q = Function[s, "\"" <> StringReplace[iDocPaperStr[s], "\"" -> "\\\""] <> "\""];
    bibCell = If[Length[bibs] === 0, Nothing,
      Cell["{{<<Key>>, <<Author>>, <<Year>>, <<Title>>}" <>
        StringJoin[Map[Function[e,
          ", {" <> q[iDocPaperAsciiKey[Lookup[e, "key", ""]]] <> ", " <> q[Lookup[e, "author", ""]] <> ", " <>
            q[Lookup[e, "year", ""]] <> ", " <> q[Lookup[e, "title", ""]] <> "}"], bibs]] <> "}",
        "Bibliography", Sequence @@ $iDocBibliographyCellOpts]];
    {header,
     Cell[StringRiffle[texts, "\n"], "Text",
       iDocPaperTags[{"refSources" -> iDocPaperRefSources[pdf, pages], "paperType" -> "references"}]],
     bibCell}];

iDocPaperAsciiKey[s_] :=
  Module[{k = ToLowerCase[RemoveDiacritics[iDocPaperStr[s]]]},
    k = StringReplace[k, Except[LetterCharacter | DigitCharacter] -> ""];
    If[k === "", "ref", k]];

(* Input セル (コード文字列 → ボックス。FE が無ければ文字列セル) *)
iDocPaperCodeCell[code_String, rules_List] :=
  Module[{boxes},
    boxes = If[$FrontEnd === Null, $Failed,
      Quiet @ Check[MathLink`CallFrontEnd[FrontEnd`ReparseBoxStructurePacket[code]], $Failed]];
    If[MatchQ[boxes, BoxData[_]],
      Cell[boxes, "Input", iDocPaperTags[rules]],
      Cell[code, "Input", iDocPaperTags[rules]]]];

(* ============================================================
   ブロック列 → セル列 (第一部)
   ============================================================ *)

iDocPaperBlocksToCells[blocks_List, pdf_String, cfg_Association] :=
  Module[{cells = {}, i = 1, n = Length[blocks], b, styles = cfg["HeadingStyles"], refs = {},
          figCounter = 0, authors = {}, flushAuthors, next, prev, bnd},
    (* 図表の切り出し境界候補 = そのページで LLM が要素に割り当てた全ブロック id
       (要素自身とキャプションの id は iDocPaperElementRegion 側で除く) *)
    bnd = Function[blk, Replace[Lookup[blk, "PageClaimedIds", {}], Except[_List] -> {}]];
    flushAuthors := If[Length[authors] > 0,
      AppendTo[cells, Cell[StringRiffle[Map[iDocPaperPlainMath[StringTrim[#["text"]]] &, authors], "\n"], "Text",
        iDocPaperTags[{"refSources" -> iDocPaperRefSources[pdf, DeleteDuplicates[Flatten[#["Pages"] & /@ authors]]],
          "paperType" -> "authors"}]]];
      authors = {}];
    While[i <= n,
      b = blocks[[i]];
      If[b["type"] =!= "authors" && b["type"] =!= "affiliation", flushAuthors];
      Switch[b["type"],
        "title",
          AppendTo[cells, Cell[iDocPaperPlainMath[StringTrim[b["text"]]], styles[[1]],
            iDocPaperTags[{"refSources" -> iDocPaperRefSources[pdf, b["Pages"]], "paperType" -> "title"}]]],
        "authors" | "affiliation",
          AppendTo[authors, b],
        "abstract",
          AppendTo[cells, iDocPaperTextCell[b, pdf, "Text", {}]],
        "keywords",
          AppendTo[cells, Cell[iDocPaperPlainMath[StringTrim[b["text"]]], "Text",
            iDocPaperTags[{"refSources" -> iDocPaperRefSources[pdf, b["Pages"]], "paperType" -> "keywords"}]]],
        "heading",
          AppendTo[cells, iDocPaperHeadingCell[b, pdf, styles]],
        "paragraph" | "list",
          AppendTo[cells, iDocPaperTextCell[b, pdf, "Text", {}]],
        "display_math",
          AppendTo[cells, iDocPaperDisplayMathCell[b, pdf, cfg]],
        "figure" | "table",
          figCounter += 1;
          next = If[i + 1 <= n, blocks[[i + 1]], None];
          prev = If[i - 1 >= 1, blocks[[i - 1]], None];
          Which[
            (* 直前のキャプションは caption 分岐で保留されている (表は先にキャプションが来ることが多い) *)
            AssociationQ[prev] && prev["type"] === "caption",
              cells = Join[cells, iDocPaperFigureCells[b, prev, True, pdf, cfg, figCounter, bnd[b]]],
            (* 直後のキャプション *)
            AssociationQ[next] && next["type"] === "caption",
              cells = Join[cells, iDocPaperFigureCells[b, next, False, pdf, cfg, figCounter, bnd[b]]];
              i += 1,
            True,
              cells = Join[cells, iDocPaperFigureCells[b, None, False, pdf, cfg, figCounter, bnd[b]]]],
        "caption",
          (* 相方の図表が直後に来るならそこで処理する。来ないなら普通の Text *)
          next = If[i + 1 <= n, blocks[[i + 1]], None];
          If[!(AssociationQ[next] && MatchQ[next["type"], "figure" | "table"]),
            AppendTo[cells, iDocPaperTextCell[b, pdf, "Text", {}]]],
        "references",
          AppendTo[refs, b],
        _,
          If[StringTrim[b["text"]] =!= "",
            AppendTo[cells, iDocPaperTextCell[b, pdf, "Text", {}]]]];
      i += 1];
    flushAuthors;
    Join[cells, iDocPaperReferenceCells[refs, pdf]]];

(* ============================================================
   第二部: 計算の再構成
   ============================================================ *)

(* ブロック列から LLM 用の本文を組む (参考文献は除く) *)
iDocPaperBodyText[blocks_List] :=
  Module[{lines = {}},
    Do[
      Switch[b["type"],
        "title", AppendTo[lines, "# " <> b["text"]],
        "heading", AppendTo[lines, StringRepeat["#", Clip[b["level"] + 1, {2, 4}]] <> " " <> b["text"]],
        "display_math", AppendTo[lines, "$$ " <> b["latex"] <> " $$ " <> b["label"]],
        "caption", AppendTo[lines, "[" <> b["text"] <> "]"],
        "references" | "authors" | "affiliation" | "keywords" | "figure" | "table", Null,
        _, AppendTo[lines, b["text"]]],
      {b, blocks}];
    StringRiffle[lines, "\n\n"]];

iDocPaperReconstructPrompt[body_String, lang_String] :=
  StringJoin[
    "Below is the text of a scientific paper (equations in LaTeX between $$ $$, captions in brackets).\n",
    "Identify every computation, algorithm, model, generator, formula or table entry that is concrete enough to reproduce, ",
    "and reconstruct it as Wolfram Language (Mathematica) code so that a reader can re-run the paper's calculations or simulations.\n\n",
    "Return ONLY a JSON object with this shape:\n",
    "{\"summary\": \"5-10 lines in ", lang, " describing what can be reproduced and the paper's parameter choices\",\n",
    " \"units\": [\n",
    "   {\"title\": \"short title in ", lang, "\",\n",
    "    \"description\": \"1-3 sentences in ", lang, ": which section / equation / table this reproduces and the assumptions made\",\n",
    "    \"code\": \"Wolfram Language definitions (named functions), symbolic where possible, matrices and vectors kept as such\",\n",
    "    \"example\": \"a few evaluatable lines that reproduce a concrete number, table row or figure from the paper with the paper's parameters; comment the expected value\"}\n",
    " ],\n",
    " \"notes\": \"open questions, typos or ambiguities found in the paper, in ", lang, "\"}\n\n",
    "Guidelines for the code:\n",
    "  - Prefer built-in functions (MatrixPower, Mod, LinearRecurrence, CellularAutomaton, NDSolve, ...) over hand-written loops.\n",
    "  - Each unit must be self-contained together with the earlier units (later units may use earlier definitions). Keep a unit under ~40 lines.\n",
    "  - Do not use Clear[\"Global`*\"], file paths, Import, Export, external packages or paclets.\n",
    "  - Keep the paper's notation in symbol names where reasonable (e.g. T for the characteristic matrix).\n",
    "  - Comments inside the code may be in ", lang, ".\n",
    "  - Output valid JSON only (escape backslashes and quotes inside code strings). No markdown fences.\n\n",
    "Paper text:\n", body];

iDocPaperFixCodePrompt[code_String, msg_String] :=
  "The following Wolfram Language code does not parse (" <> msg <> "). " <>
  "Return ONLY the corrected code, no explanation, no markdown fences.\n\n" <> code;

(* 構文検査 + 1 回だけ修正依頼 *)
iDocPaperCheckCode[code_String, cfg_Association] :=
  Module[{c = StringTrim[code], fixed, ok},
    If[c === "", Return[{"", True}]];
    ok = TrueQ[Quiet[SyntaxQ[c]]];
    If[ok, Return[{c, True}]];
    iDocPaperLog[cfg["Verbose"], "構文エラーのコードを修正依頼中: " <> StringTake[c, UpTo[60]]];
    fixed = iDocPaperQuery[{iDocPaperFixCodePrompt[c,
      "SyntaxLength = " <> ToString[Quiet[SyntaxLength[c]]]]}, cfg];
    If[StringQ[fixed],
      fixed = StringTrim[StringReplace[fixed, {
        RegularExpression["(?s)^```[A-Za-z]*[ \\t]*\\r?\\n"] -> "",
        RegularExpression["(?s)\\r?\\n```[ \\t]*$"] -> ""}]];
      If[TrueQ[Quiet[SyntaxQ[fixed]]], Return[{fixed, True}]]];
    Message[DocImportPaper::syntax, StringTake[c, UpTo[40]]];
    {c, False}];

DocPaperExtractComputations[pdf_String, opts:OptionsPattern[]] :=
  Module[{cfg, nPages, pages, txt},
    If[!FileExistsQ[pdf], Message[DocImportPaper::nofile, pdf]; Return[$Failed]];
    nPages = Quiet[Import[pdf, "PageCount"]];
    If[!IntegerQ[nPages], Message[DocImportPaper::nopages, pdf]; Return[$Failed]];
    cfg = iDocPaperConfig[{opts}, Options[DocPaperExtractComputations]];
    pages = iDocPaperResolvePages[cfg["Pages"], nPages];
    txt = StringRiffle[Map[iDocPaperPagePlainText[pdf, #] &, pages], "\n\n"];
    iDocPaperExtractComputationsImpl[txt, cfg]];

DocPaperExtractComputations[pdf_String, blocks_List, opts:OptionsPattern[]] :=
  Module[{cfg = iDocPaperConfig[{opts}, Options[DocPaperExtractComputations]]},
    iDocPaperExtractComputationsImpl[iDocPaperBodyText[Select[blocks, AssociationQ]], cfg]];

iDocPaperExtractComputationsImpl[body_String, cfg_Association] :=
  Module[{prompt, resp, parsed, units, out},
    If[StringTrim[body] === "", Return[$Failed]];
    iDocPaperLog[cfg["Verbose"], "論文全文 (" <> ToString[StringLength[body]] <> " 文字) から計算を再構成中..."];
    prompt = iDocPaperReconstructPrompt[StringTake[body, UpTo[150000]], cfg["TargetLanguage"]];
    resp = iDocPaperQuery[{prompt}, cfg];
    If[resp === $Failed, Return[$Failed]];
    parsed = iDocPaperParseJSON[resp];
    If[parsed === $Failed,
      iDocPaperLog[cfg["Verbose"], "JSON を読めません。JSON のみで再依頼します。"];
      resp = iDocPaperQuery[{prompt <> "\n\nYour previous answer was not valid JSON. Return the JSON object only."}, cfg];
      parsed = If[resp === $Failed, $Failed, iDocPaperParseJSON[resp]]];
    If[!AssociationQ[parsed], Message[DocImportPaper::json, "computations"]; Return[$Failed]];
    units = Lookup[parsed, "units", {}];
    If[!ListQ[units], units = {}];
    units = Map[Function[u,
      If[!AssociationQ[u], Nothing,
        Module[{code, ok, ex, exOk},
          {code, ok} = iDocPaperCheckCode[iDocPaperStr[Lookup[u, "code", ""]], cfg];
          {ex, exOk} = iDocPaperCheckCode[iDocPaperStr[Lookup[u, "example", ""]], cfg];
          <|"title" -> iDocPaperStr[Lookup[u, "title", ""]],
            "description" -> iDocPaperStr[Lookup[u, "description", ""]],
            "code" -> code, "syntaxOK" -> ok,
            "example" -> ex, "exampleSyntaxOK" -> exOk|>]]], units];
    out = <|"summary" -> iDocPaperStr[Lookup[parsed, "summary", ""]],
            "units" -> units,
            "notes" -> iDocPaperStr[Lookup[parsed, "notes", ""]]|>;
    $DocPaperLastAnalysis = Append[$DocPaperLastAnalysis, "Computations" -> out];
    out];

iDocPaperComputationCells[comp_Association, pdf_String, lang_String] :=
  Module[{cells = {}, jp = StringMatchQ[lang, "Japanese", IgnoreCase -> True]},
    AppendTo[cells, Cell[If[jp, "第二部: 計算の再構成", "Part II: Computational reconstruction"], "Section",
      iDocPaperTags[{"paperType" -> "part2"}]]];
    If[StringTrim[comp["summary"]] =!= "",
      AppendTo[cells, Cell[DocPaperTextToTextData[comp["summary"]], "Text",
        iDocPaperTags[{"paperType" -> "summary", "refSources" -> {{pdf, All}}}]]]];
    Do[
      AppendTo[cells, Cell[u["title"], "Subsubsection", iDocPaperTags[{"paperType" -> "codeTitle"}]]];
      If[StringTrim[u["description"]] =!= "",
        AppendTo[cells, Cell[DocPaperTextToTextData[u["description"]], "Text",
          iDocPaperTags[{"paperType" -> "codeDescription", "refSources" -> {{pdf, All}}}]]]];
      If[!TrueQ[u["syntaxOK"]],
        AppendTo[cells, Cell[If[jp, "注意: 以下のコードは構文検査を通っていません。",
          "Warning: the following code did not pass the syntax check."], "Text", FontColor -> RGBColor[0.7, 0.2, 0.2]]]];
      If[StringTrim[u["code"]] =!= "",
        AppendTo[cells, iDocPaperCodeCell[u["code"], {"paperType" -> "code", "refSources" -> {{pdf, All}}}]]];
      If[StringTrim[u["example"]] =!= "",
        AppendTo[cells, iDocPaperCodeCell[u["example"], {"paperType" -> "example", "refSources" -> {{pdf, All}}}]]],
      {u, comp["units"]}];
    If[StringTrim[comp["notes"]] =!= "",
      AppendTo[cells, Cell[If[jp, "注意点・疑問点", "Notes and open questions"], "Subsubsection"]];
      AppendTo[cells, Cell[DocPaperTextToTextData[comp["notes"]], "Text", iDocPaperTags[{"paperType" -> "notes"}]]]];
    cells];

(* ============================================================
   公開: 変換本体
   ============================================================ *)

iDocPaperOutputPath[pdf_String, opt_] :=
  Module[{base, dir, cand, k = 1},
    If[StringQ[opt] && opt =!= "", Return[opt]];
    dir = DirectoryName[pdf];
    base = FileBaseName[pdf];
    cand = FileNameJoin[{dir, base <> ".nb"}];
    While[FileExistsQ[cand],
      k += 1;
      cand = FileNameJoin[{dir, base <> "_" <> ToString[k] <> ".nb"}]];
    cand];

iDocPaperMetaCells[cfg_Association] :=
  {Cell[cfg["Directive"], "Directive", Sequence @@ $iDocDirectiveCellOpts],
   Cell[iDocPaperDictionaryCellText[cfg["Dictionary"], cfg["TargetLanguage"]], "Dictionary",
     Sequence @@ $iDocDictionaryCellOpts]};

DocImportPaper[pdfIn_String, opts:OptionsPattern[]] :=
  Module[{pdf, cfg, nPages, pages, pageResults = {}, blocks, cells, comp = None, nbExpr, outPath,
          nb, t0 = AbsoluteTime[], failedPages = {}},
    pdf = AbsoluteFileName[pdfIn];
    If[!StringQ[pdf] || !FileExistsQ[pdf], Message[DocImportPaper::nofile, pdfIn]; Return[$Failed]];
    nPages = Quiet[Import[pdf, "PageCount"]];
    If[!IntegerQ[nPages] || nPages < 1, Message[DocImportPaper::nopages, pdf]; Return[$Failed]];
    cfg = iDocPaperConfig[{opts}, Options[DocImportPaper]];
    pages = iDocPaperResolvePages[cfg["Pages"], nPages];
    iDocPaperLog[cfg["Verbose"], FileNameTake[pdf] <> ": " <> ToString[Length[pages]] <> " ページを変換します (訳: " <>
      cfg["TargetLanguage"] <> ", 数式: " <> cfg["MathMode"] <> ")"];
    $DocPaperLastAnalysis = <|"PDF" -> pdf, "Pages" -> pages|>;

    (* --- 第一部: ページごとの構造解析 --- *)
    Do[
      Module[{r = iDocPaperAnalyzePageImpl[pdf, p, nPages, cfg]},
        If[ListQ[r], AppendTo[pageResults, r], AppendTo[failedPages, p]]],
      {p, pages}];
    If[Length[failedPages] > 0,
      iDocPaperLog[True, "解析に失敗したページ: " <> ToString[failedPages]]];
    blocks = iDocPaperMergeAllPages[pageResults, cfg["TargetLanguage"]];
    $DocPaperLastAnalysis["Blocks"] = blocks;
    iDocPaperLog[cfg["Verbose"], ToString[Length[blocks]] <> " ブロックをセルに変換中..."];
    cells = iDocPaperBlocksToCells[blocks, pdf, cfg];

    (* --- 第二部: 計算の再構成 --- *)
    If[TrueQ[cfg["Reconstruct"]] && Length[blocks] > 0,
      comp = iDocPaperExtractComputationsImpl[iDocPaperBodyText[blocks], cfg];
      If[AssociationQ[comp],
        cells = Join[cells, iDocPaperComputationCells[comp, pdf, cfg["TargetLanguage"]]],
        iDocPaperLog[True, "計算の再構成に失敗しました (第一部のみ出力します)。"]]];

    cells = Join[iDocPaperMetaCells[cfg], cells];
    (* 画像・ページブロック等の重い中間データを $DocPaperLastAnalysis から落とす *)
    $DocPaperLastAnalysis["Blocks"] = Map[KeyDrop[#, {"PageBlocks", "PageImage", "PageClaimedIds"}] &, blocks];
    $DocPaperLastAnalysis["Cells"] = Length[cells];

    nbExpr = Notebook[cells,
      WindowSize -> {900, 800},
      TaggingRules -> {$iDocTagRoot -> {
        "paperSource" -> pdf,
        "paperImportedAt" -> DateString["ISODateTime"],
        "paperTargetLanguage" -> cfg["TargetLanguage"],
        "paperFailedPages" -> failedPages}}];

    outPath = iDocPaperOutputPath[pdf, cfg["OutputPath"]];
    nb = None;
    Which[
      $FrontEnd =!= Null && TrueQ[cfg["Open"]],
        nb = NotebookPut[nbExpr];
        If[TrueQ[cfg["Save"]], Quiet[NotebookSave[nb, outPath]]],
      TrueQ[cfg["Save"]],
        Quiet[Export[outPath, nbExpr, "NB"]]];
    If[TrueQ[cfg["Save"]] && !FileExistsQ[outPath], iDocPaperLog[True, "保存に失敗: " <> outPath]];
    If[TrueQ[cfg["Save"]] && FileExistsQ[outPath],
      If[MemberQ[{True, False}, cfg["CloudPublishable"]],
        Quiet @ Check[NBAccess`NBSetCloudPublishable[outPath, cfg["CloudPublishable"]], Null]]];
    If[Head[nb] === NotebookObject,
      Quiet @ Check[NBAccess`NBHistoryAddAttachment[nb, "history", pdf], Null]];
    iDocPaperLog[cfg["Verbose"], "完了: " <> ToString[Length[cells]] <> " セル, " <>
      ToString[Round[AbsoluteTime[] - t0]] <> " 秒" <>
      If[TrueQ[cfg["Save"]] && FileExistsQ[outPath], " -> " <> outPath, ""]];
    Which[
      Head[nb] === NotebookObject, nb,
      TrueQ[cfg["Save"]] && FileExistsQ[outPath], outPath,
      True, nbExpr]];

(* ============================================================
   パレット用アクション (documentation.wl のパレットから呼ばれる)
   ============================================================ *)

iDocImportPaperAction[] :=
  Module[{path},
    path = SystemDialogInput["FileOpen", {"", {iL["PDF ファイル", "PDF files"] -> {"*.pdf"}}},
      WindowTitle -> iL["論文 PDF を選択", "Choose a paper PDF"]];
    If[!StringQ[path] || !FileExistsQ[path], Return[$Canceled]];
    DocImportPaper[path, Fallback -> TrueQ[Quiet[ClaudeCode`GetPaletteFallback[]]]]];

End[];
EndPackage[];
