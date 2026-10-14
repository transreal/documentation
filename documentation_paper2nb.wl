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

   == 翻訳するかどうか (2026-10-12) ==
     "Translate" -> Automatic (既定) は原文の言語を判定し (DocPaperDetectLanguage: 文字種 +
     英語の機能語 + LanguageIdentify)、"TargetLanguage" ($Language) と違うときだけ翻訳する。
     同じ言語なら翻訳せず構造化だけ行う (翻訳ノートブック = 多言語の利用者がそれぞれの $Language で作る)。

   == Web ページ (DocImportWebPage, 2026-10-12) ==
     保存済みの HTML / テキスト / Markdown を同じ規約のノートブックにする。LLM には構造解析を
     させず、HTML の構造 (article / main / 見出し / 段落 / 箇条書き / 表 / 図 / MathML 等) から
     決定的にブロックを取り出し、翻訳だけを LLM に頼む (項目を JSON でまとめて渡す)。
     画像は URL から取得して埋め込む。SourceVault の web ソースは SourceVaultMakePaperNotebook がこれを呼ぶ。

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
  "DocImportPaper[\"src-...\" | \"sv://...\" | \"arxiv:...\"] は SourceVault 取り込み済みの論文を元ソースの PrivacyLevel を継承して変換・登録する (SourceVaultMakePaperNotebook へ委譲: PL < 0.5 は cloud 経路 + CloudPublishable 宣言、PL >= 0.5 は $ClaudePrivateModel のみ)。\n" <>
  "DocImportPaper[pdfPath] は論文 PDF を documentation 規約のノートブックへ逆変換する (HTML / テキスト / Markdown のパスなら DocImportWebPage へ委譲)。\n" <>
  "原文の言語が TargetLanguage ($Language) と違うときだけ翻訳する (\"Translate\" -> Automatic)。\n" <>
  "第一部: 見出し・段落 (翻訳 + 原文保持, mode=\"translated\")・インライン数式 (LaTeX → TraditionalForm)・\n" <>
  "別行立て数式 (DisplayFormula, 失敗時はページ画像の切り出し)・図表 (ページ画像の切り出し + キャプション)・参考文献。\n" <>
  "第二部: 論文中の計算・アルゴリズム・数式を Wolfram Language の定義と実行例に再構成する。\n" <>
  "出力: 既定では PDF と同じフォルダに <名前>.nb を保存し、開いた NotebookObject を返す (ヘッドレスならパス)。\n" <>
  "Options:\n" <>
  "  \"TargetLanguage\" -> Automatic ($Language), \"Translate\" -> Automatic (原文が別の言語のときだけ) | True | False, \"Reconstruct\" -> True,\n" <>
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

DocImportWebPage::usage =
  "DocImportWebPage[path] は保存済みの Web ページ (HTML / テキスト / Markdown) を documentation 規約の翻訳ノートブックへ変換する。\n" <>
  "本文 (article / main / 本文らしい要素) から見出し・段落・箇条書き・引用・コード・表・図 (画像は取得して埋め込む)・\n" <>
  "数式 (MathML / LaTeXML の alttext / MathJax / KaTeX の TeX) を取り出し、原文の言語が \"TargetLanguage\" ($Language) と\n" <>
  "違えば LLM で翻訳する (原文は TaggingRules の translationSrc に保持、mode=\"translated\")。同じ言語なら翻訳せず構造化だけ。\n" <>
  "SourceVault の web ソースは SourceVaultMakePaperNotebook[\"src-...\"] が元ソースの PL を継承してこれを呼ぶ。\n" <>
  "Options:\n" <>
  "  \"BaseURL\" -> Automatic (ページの URL。画像・相対リンクの解決と出典表示。Automatic = og:url / canonical), \"Title\" -> Automatic,\n" <>
  "  \"TargetLanguage\" -> Automatic ($Language), \"Translate\" -> Automatic | True | False,\n" <>
  "  \"Images\" -> True (False は画像を取得せずリンクだけ), \"MaxImages\" -> 30, \"Reconstruct\" -> False (True で第二部 = 計算の再構成),\n" <>
  "  \"OutputPath\" -> Automatic, \"Open\" -> True, \"Save\" -> True, \"CloudPublishable\" -> None,\n" <>
  "  \"Directive\" -> Automatic, \"Dictionary\" -> {}, \"HeadingStyles\" -> Automatic, \"Verbose\" -> True,\n" <>
  "  Fallback -> False, Model -> Automatic, Timeout -> Automatic\n" <>
  "例: DocImportWebPage[\"C:/clip/page.html\", \"BaseURL\" -> \"https://example.org/post\"]";

DocPaperDetectLanguage::usage =
  "DocPaperDetectLanguage[text] は文章の言語名 (\"Japanese\", \"English\", \"Chinese\", \"Korean\", \"French\", ...) を返す。判定できなければ Missing[\"Unknown\"]。\n" <>
  "文字種 (かな・漢字・ハングル・キリル文字等) で決め、ラテン文字は英語の機能語の割合、それ以外は LanguageIdentify で決める。\n" <>
  "DocImportPaper / DocImportWebPage の \"Translate\" -> Automatic (原文が TargetLanguage と違うときだけ翻訳) が使う。";

$DocPaperLastAnalysis::usage =
  "$DocPaperLastAnalysis は直近の DocImportPaper / DocImportWebPage / DocPaperAnalyzePage / DocPaperExtractComputations の中間結果\n" <>
  "(<|\"PDF\", \"Pages\", \"Blocks\", \"Computations\", \"Cells\", \"SourceLanguage\", \"TargetLanguage\", \"Translated\"|>)。デバッグと再利用のために保持する。";

Options[DocImportPaper] = {
  "TargetLanguage" -> Automatic,
  "Translate" -> Automatic,
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
  "Translate" -> Automatic,
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

Options[DocImportWebPage] = {
  "BaseURL" -> Automatic,
  "Title" -> Automatic,
  "TargetLanguage" -> Automatic,
  "Translate" -> Automatic,
  "Images" -> True,
  "MaxImages" -> 30,
  "Reconstruct" -> False,
  "OutputPath" -> Automatic,
  "Open" -> True,
  "Save" -> True,
  "CloudPublishable" -> None,
  "Directive" -> Automatic,
  "Dictionary" -> {},
  "HeadingStyles" -> Automatic,
  "Verbose" -> True,
  Fallback -> False,
  Model -> Automatic,
  Timeout -> Automatic
};

DocImportWebPage::nofile = "ファイルが見つかりません: `1`";
DocImportWebPage::format = "Web ページとして読めない形式です (HTML / テキスト / Markdown のみ): `1`";
DocImportWebPage::empty = "本文を取り出せませんでした: `1`";

DocImportPaper::nofile = "PDF ファイルが見つかりません: `1`";
DocImportPaper::nopages = "PDF のページ数を取得できません: `1`";
DocImportPaper::llm = "LLM 呼び出しに失敗しました: `1`";
DocImportPaper::abort = "LLM サーバに接続できないため中断します (`1` ページ連続で接続失敗): `2`";
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
   原文の言語判定 ("Translate" -> Automatic: 原文が TargetLanguage と違うときだけ翻訳する)
   ============================================================ *)

(* 言語名の比較キー。$Language の値 (ChineseSimplified 等) と判定結果 (Chinese) と
   LanguageIdentify の正規名 (ChineseMandarin 等) を同じ土俵で比べる。
   簡体字と繁体字は区別しない (どちらも翻訳しない) *)
iDocLangKey[s_String] :=
  Module[{l = ToLowerCase[StringDelete[s, WhitespaceCharacter | "-" | "_"]]},
    Which[
      StringContainsQ[l, "chinese" | "mandarin"], "chinese",
      StringContainsQ[l, "english"], "english",
      StringContainsQ[l, "portuguese"], "portuguese",
      StringContainsQ[l, "spanish"], "spanish",
      True, l]];
iDocLangKey[_] := "";
iDocLangSameQ[a_String, b_String] := iDocLangKey[a] =!= "" && iDocLangKey[a] === iDocLangKey[b];
iDocLangSameQ[___] := False;

(* プロンプト用の言語名 *)
iDocLangPromptName[lang_String] :=
  Switch[lang,
    "ChineseSimplified", "Simplified Chinese",
    "ChineseTraditional", "Traditional Chinese",
    _, lang];

$iDocEnglishStopwords = {"the", "and", "of", "to", "is", "in", "that", "for", "with", "are", "this", "on", "it", "as", "be"};

iDocCountRange[codes_List, lo_Integer, hi_Integer] :=
  If[codes === {}, 0, Total[UnitStep[codes - lo] UnitStep[hi - codes]]];

iDocLanguageIdentify[t_String, default_] :=
  Module[{r = Quiet[TimeConstrained[LanguageIdentify[StringTake[t, UpTo[3000]]], 30, $Failed]]},
    If[MatchQ[r, Entity["Language", _String]], r[[2]], default]];

(* 文字種で決め、ラテン文字は英語の機能語の割合 (LanguageIdentify は初回にリソース取得が要るので後回し)。
   かな・漢字 1 字はラテン文字 4 字ぶんと数える (英単語混じりの日本語技術文を日本語と判定するため)。
   数式 $..$・コード `..`・URL は判定から外す *)
DocPaperDetectLanguage[text_String] :=
  Module[{t, codes, kana, han, hangul, cyr, greek, arab, hebr, thai, deva, latin, wL, cjk, words, stop},
    t = StringReplace[StringTake[text, UpTo[20000]], {
      "$" ~~ Shortest[__] ~~ "$" -> " ",
      "`" ~~ Shortest[__] ~~ "`" -> " ",
      ("http://" | "https://") ~~ Except[WhitespaceCharacter] .. -> " "}];
    codes = ToCharacterCode[t];
    If[codes === {}, Return[Missing["Unknown"]]];
    kana = iDocCountRange[codes, 12352, 12543] + iDocCountRange[codes, 65382, 65439];
    han = iDocCountRange[codes, 19968, 40959] + iDocCountRange[codes, 13312, 19903];
    hangul = iDocCountRange[codes, 44032, 55215] + iDocCountRange[codes, 4352, 4607] + iDocCountRange[codes, 12592, 12687];
    cyr = iDocCountRange[codes, 1024, 1279];
    greek = iDocCountRange[codes, 880, 1023];
    arab = iDocCountRange[codes, 1536, 1791];
    hebr = iDocCountRange[codes, 1424, 1535];
    thai = iDocCountRange[codes, 3584, 3711];
    deva = iDocCountRange[codes, 2304, 2431];
    latin = iDocCountRange[codes, 65, 90] + iDocCountRange[codes, 97, 122] + iDocCountRange[codes, 192, 591];
    wL = latin / 4.;
    cjk = kana + han;
    Which[
      kana >= Max[5, 0.03 cjk] && cjk >= wL, "Japanese",
      han >= 5 && cjk >= wL, "Chinese",
      hangul >= 5 && hangul >= wL, "Korean",
      cyr >= 20 && cyr >= latin, iDocLanguageIdentify[t, "Russian"],
      greek >= 20 && greek >= latin, "Greek",
      arab >= 20 && arab >= latin, iDocLanguageIdentify[t, "Arabic"],
      hebr >= 20 && hebr >= latin, "Hebrew",
      thai >= 20 && thai >= latin, "Thai",
      deva >= 20 && deva >= latin, iDocLanguageIdentify[t, "Hindi"],
      latin >= 20,
        words = ToLowerCase[StringCases[t, LetterCharacter ..]];
        stop = If[words === {}, 0., N[Count[words, Alternatives @@ $iDocEnglishStopwords] / Length[words]]];
        If[stop >= 0.08, "English", iDocLanguageIdentify[t, Missing["Unknown"]]],
      True, Missing["Unknown"]]];
DocPaperDetectLanguage[_] := Missing["Unknown"];

(* "Translate" -> Automatic を真偽値に解決する。判定できなければ翻訳する (従来どおり) *)
iDocPaperResolveTranslate[cfg_Association, sample_String] :=
  Module[{src = DocPaperDetectLanguage[sample], tr = cfg["Translate"]},
    src = If[StringQ[src], src, ""];
    tr = Which[
      tr === True || tr === False, tr,
      src =!= "" && iDocLangSameQ[src, cfg["TargetLanguage"]], False,
      True, True];
    Join[cfg, <|"Translate" -> tr, "SourceLanguage" -> src|>]];

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

(* 直近の失敗理由 (DocImportPaper が「接続失敗が続いたら中断」の判定に使う) *)
If[!StringQ[$iDocPaperLastError], $iDocPaperLastError = ""];
iDocPaperConnectionErrorQ[s_String] :=
  StringContainsQ[s, "接続失敗" | "connection failed" | "接続拒否" | "Connection refused" |
    "接続できません", IgnoreCase -> True];
iDocPaperConnectionErrorQ[_] := False;

(* 返り値: 応答文字列。失敗は $Failed (メッセージ付き)。 *)
iDocPaperQuery[items_List, cfg_Association] :=
  Module[{res = iDocPaperQueryRaw[items, cfg]},
    Which[
      !StringQ[res],
        $iDocPaperLastError = ToString[Head[res]];
        Message[DocImportPaper::llm, ToString[Head[res]]]; $Failed,
      iDocPaperErrorStringQ[res],
        $iDocPaperLastError = StringTrim[res];
        Message[DocImportPaper::llm, StringTake[StringTrim[res], UpTo[300]]]; $Failed,
      True, $iDocPaperLastError = ""; res]];

(* 画像入力に対応しないモデル (claudecode.wl が "NoVision" を含むエラーで知らせる) を
   このセッションで覚えておき、以後のページでは画像付き試行を最初から省く。
   llama.cpp 系サーバが --mmproj 無しで起動されていると 500 "image input is not supported"
   が返る。claudecode.wl (2026-09-11) がこれを NoVision へ正規化するが、古い claudecode.wl や
   別経路で生のまま届いた場合に備えて本文でも判定する。 *)
If[!ListQ[$iDocPaperNoVisionModels], $iDocPaperNoVisionModels = {}];
iDocPaperModelKey[cfg_Association] := ToString[{cfg["Model"], ClaudeCode`$ClaudeModel}, InputForm];
iDocPaperNoVisionQ[res_String] :=
  StringContainsQ[res, "NoVision"] ||
  StringContainsQ[res, "image input is not supported", IgnoreCase -> True];
iDocPaperNoVisionQ[_] := False;

(* 画像付きで問い、失敗したらテキストのみで再試行する。
   画像付きの試行は "VisionTimeout" (既定 600 秒) で打ち切る: 長いプロンプト + 画像で CLI が
   応答しないまま固まる事例があり、既定の Timeout (1200 秒) をページ毎に浪費しないため。 *)
iDocPaperQueryMaybeVision[prompt_String, img_, cfg_Association] :=
  Module[{res = $Failed, key = iDocPaperModelKey[cfg]},
    If[TrueQ[cfg["Vision"]] && ImageQ[img] && !MemberQ[$iDocPaperNoVisionModels, key],
      res = iDocPaperQueryRaw[{prompt, img}, Append[cfg, "Timeout" -> cfg["VisionTimeout"]]];
      Which[
        iDocPaperNoVisionQ[res],
          AppendTo[$iDocPaperNoVisionModels, key];
          iDocPaperLog[cfg["Verbose"],
            "このモデル/サーバは画像入力を受け付けないため、以後はテキストのみで解析します (" <>
            StringTake[StringTrim[res], UpTo[400]] <> ")。"];
          res = $Failed,
        !StringQ[res] || iDocPaperErrorStringQ[res],
          iDocPaperLog[cfg["Verbose"], "画像付き問い合わせに失敗 (" <>
            If[StringQ[res], StringTake[StringTrim[res], UpTo[240]], ToString[Head[res]]] <>
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
    cfg = iDocPaperResolveTranslate[cfg, iDocPaperPagePlainText[pdf, p]];
    iDocPaperAnalyzePageImpl[pdf, p, nPages, cfg]];

(* オプション → 設定 Association。opts が先、defaults が後 (Lookup は最初の一致を返す) *)
$iDocPaperAllDefaults = {
  "TargetLanguage" -> Automatic, "Translate" -> Automatic, "Reconstruct" -> True, "Pages" -> All,
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
      (* Automatic は呼び出し側が原文の言語を見て iDocPaperResolveTranslate で真偽値にする *)
      "Translate" -> Replace[get["Translate"], Except[True | False] -> Automatic],
      "SourceLanguage" -> "",
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
      TrueQ[cfg["Vision"]] && ImageQ[img], TrueQ[cfg["Translate"]], lang,
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

(* 取り込み済み論文の参照 (src-ID / sv://URI / arxiv:ID / URL) は SourceVault_papernb.wl に委ねる:
   元ソースの PrivacyLevel を継承して LLM 経路と CloudPublishable 宣言を決め、生成物を登録簿に載せる。
   (ローカルの PDF パスを直接渡す従来の呼び方は PL を継承しない = 宣言なし) *)
DocImportPaper[ref_String, opts:OptionsPattern[]] /;
    ! FileExistsQ[ref] && iDocPaperSourceRefQ[ref] &&
    Length[DownValues[SourceVault`SourceVaultMakePaperNotebook]] > 0 :=
  SourceVault`SourceVaultMakePaperNotebook[ref, opts];

iDocPaperSourceRefQ[s_String] := StringStartsQ[s, "src-"] || StringStartsQ[s, "sv://"] ||
  StringStartsQ[s, "arxiv:", IgnoreCase -> True] || StringStartsQ[s, "http://"] || StringStartsQ[s, "https://"];

(* 保存済みの Web ページ (HTML / テキスト / Markdown) は DocImportWebPage へ *)
DocImportPaper[path_String, opts:OptionsPattern[]] /;
    FileExistsQ[path] && iDocWebFormat[path] =!= None :=
  DocImportWebPage[path, opts];

(* 翻訳の有無 (ログと Web ページの出典セル) *)
iDocPaperTranslateNote[cfg_Association] :=
  If[TrueQ[cfg["Translate"]],
    iL["訳: ", "translated: "] <> If[cfg["SourceLanguage"] =!= "", cfg["SourceLanguage"] <> " → ", ""] <> cfg["TargetLanguage"],
    iL["翻訳なし (原文が ", "not translated (the source is in "] <>
      If[cfg["SourceLanguage"] =!= "", cfg["SourceLanguage"], cfg["TargetLanguage"]] <> ")"];

DocImportPaper[pdfIn_String, opts:OptionsPattern[]] :=
  Module[{pdf, cfg, nPages, pages, pageResults = {}, blocks, cells, comp = None, nbExpr, outPath,
          nb, t0 = AbsoluteTime[], failedPages = {}, connFail = 0, aborted},
    pdf = AbsoluteFileName[pdfIn];
    If[!StringQ[pdf] || !FileExistsQ[pdf], Message[DocImportPaper::nofile, pdfIn]; Return[$Failed]];
    nPages = Quiet[Import[pdf, "PageCount"]];
    If[!IntegerQ[nPages] || nPages < 1, Message[DocImportPaper::nopages, pdf]; Return[$Failed]];
    cfg = iDocPaperConfig[{opts}, Options[DocImportPaper]];
    pages = iDocPaperResolvePages[cfg["Pages"], nPages];
    (* 原文の言語は対象ページの先頭 3 ページの文字層で判定する (文字層が無ければ判定不能 = 翻訳する) *)
    cfg = iDocPaperResolveTranslate[cfg,
      StringTake[StringRiffle[Map[iDocPaperPagePlainText[pdf, #] &, Take[pages, UpTo[3]]], "\n"], UpTo[8000]]];
    iDocPaperLog[cfg["Verbose"], FileNameTake[pdf] <> ": " <> ToString[Length[pages]] <> " ページを変換します (" <>
      iDocPaperTranslateNote[cfg] <> ", 数式: " <> cfg["MathMode"] <> ")"];
    $DocPaperLastAnalysis = <|"PDF" -> pdf, "Pages" -> pages, "Kind" -> "pdf",
      "SourceLanguage" -> cfg["SourceLanguage"], "TargetLanguage" -> cfg["TargetLanguage"],
      "Translated" -> cfg["Translate"], "FailedPages" -> {}|>;

    (* --- 第一部: ページごとの構造解析 ---
       LLM サーバへの接続失敗 (URL 違い / サーバ停止) が 2 ページ続いたら、残りのページを
       空回りさせず中断する (2026-09-12: 21 ページ全部が「接続失敗」で流れた事例)。 *)
    $iDocPaperLastError = "";
    aborted = Catch[
      Do[
        Module[{r = iDocPaperAnalyzePageImpl[pdf, p, nPages, cfg]},
          If[ListQ[r],
            AppendTo[pageResults, r]; connFail = 0,
            AppendTo[failedPages, p];
            connFail = If[iDocPaperConnectionErrorQ[$iDocPaperLastError], connFail + 1, 0];
            If[connFail >= 2,
              Message[DocImportPaper::abort, connFail,
                StringTake[$iDocPaperLastError, UpTo[300]]];
              Throw[True, "DocPaperAbort"]]]],
        {p, pages}];
      False, "DocPaperAbort"];
    If[TrueQ[aborted],
      iDocPaperLog[True, "LLM サーバに接続できません: " <> StringTake[$iDocPaperLastError, UpTo[300]]];
      Return[$Failed]];
    If[Length[failedPages] > 0,
      iDocPaperLog[True, "解析に失敗したページ: " <> ToString[failedPages]]];
    blocks = iDocPaperMergeAllPages[pageResults, cfg["TargetLanguage"]];
    $DocPaperLastAnalysis["Blocks"] = blocks;
    $DocPaperLastAnalysis["FailedPages"] = failedPages;
    (* 文字層で判定できなかったときは LLM が各ページについて答えた言語の多数決 *)
    If[cfg["SourceLanguage"] === "",
      With[{langs = Select[Lookup[blocks, "Language", ""], StringQ[#] && StringTrim[#] =!= "" &]},
        If[langs =!= {},
          cfg["SourceLanguage"] = First[Commonest[langs]];
          $DocPaperLastAnalysis["SourceLanguage"] = cfg["SourceLanguage"]]]];
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
        "paperSourceLanguage" -> cfg["SourceLanguage"],
        "paperTranslated" -> TrueQ[cfg["Translate"]],
        "paperFailedPages" -> failedPages}}];

    outPath = iDocPaperOutputPath[pdf, cfg["OutputPath"]];
    iDocPaperFinishNotebook[nbExpr, outPath, cfg, pdf, Length[cells], t0]];

(* 生成したノートブック式を開く / 保存する / CloudPublishable を宣言する (DocImportPaper と DocImportWebPage の共通部)。
   返り値: 開いた NotebookObject、保存したパス、どちらも無ければノートブック式 *)
iDocPaperFinishNotebook[nbExpr_Notebook, outPath_String, cfg_Association, srcFile_String, nCells_Integer, t0_] :=
  Module[{nb = None},
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
      Quiet @ Check[NBAccess`NBHistoryAddAttachment[nb, "history", srcFile], Null]];
    iDocPaperLog[cfg["Verbose"], "完了: " <> ToString[nCells] <> " セル, " <>
      ToString[Round[AbsoluteTime[] - t0]] <> " 秒" <>
      If[TrueQ[cfg["Save"]] && FileExistsQ[outPath], " -> " <> outPath, ""]];
    Which[
      Head[nb] === NotebookObject, nb,
      TrueQ[cfg["Save"]] && FileExistsQ[outPath], outPath,
      True, nbExpr]];

(* ============================================================
   Web ページ (HTML / テキスト / Markdown) → 翻訳ノートブック (DocImportWebPage)
   LLM には構造解析をさせない: HTML の構造から決定的にブロックを取り出し、翻訳だけを頼む。
   ブロック: <|"type" -> "title" | "heading" | "paragraph" | "quote" | "item" | "code" | "display_math"
                       | "image" | "table" | "caption" | "references",
               "text", "level" (見出し 1-3 / 箇条書き 0-2), "ordered", "latex", "label", "src", "alt",
               "caption", "rows", "items", "heading", "translation", "captionTranslation", "rowsTranslation", "Image"|>
   本文中の数式は $...$ (TeX)、インラインコードは `...`、地の文のドル記号は \$ で表す
   (LaTeX と同じ書き方。翻訳中もそのまま保たせ、セルにするときに戻す)。
   MathJax / KaTeX を使うページだけは地の文の $...$ / \(...\) を数式として扱う。
   ============================================================ *)

iDocWebFormat[path_String] :=
  Switch[ToLowerCase[FileExtension[path]],
    "html" | "htm" | "xhtml" | "shtml", "html",
    "md" | "markdown", "markdown",
    "txt" | "text", "text",
    _, None];
iDocWebFormat[_] := None;

(* ---- XMLObject の小道具 (HTML の Import は名前空間付きのタグ {ns, name} もありうる) ---- *)
iDocWebTagName[t_] := ToLowerCase[If[ListQ[t], ToString[Last[t]], ToString[t]]];
iDocWebTag[XMLElement[t_, _, _]] := iDocWebTagName[t];
iDocWebTag[_] := "";

iDocWebAttr[attrs_List, name_String] :=
  Module[{r = SelectFirst[attrs, MatchQ[#, (k_ -> _) /; iDocWebTagName[k] === name] &, None]},
    If[r === None, "", ToString[r[[2]]]]];
iDocWebAttr[_, _] := "";
iDocWebHasAttrQ[attrs_List, name_String] := AnyTrue[attrs, MatchQ[#, (k_ -> _) /; iDocWebTagName[k] === name] &];

iDocWebClasses[attrs_] := ToLowerCase /@ StringSplit[iDocWebAttr[attrs, "class"]];
(* class と id を - _ 空白で細かく切った語 (share-buttons → share, buttons) *)
iDocWebTokens[attrs_] := DeleteDuplicates[ToLowerCase /@
  StringSplit[iDocWebAttr[attrs, "class"] <> " " <> iDocWebAttr[attrs, "id"], WhitespaceCharacter | "-" | "_"]];

iDocWebNum[s_String] := With[{d = StringCases[s, DigitCharacter ..]}, If[d === {}, 0, FromDigits[First[d]]]];

(* 本文量の目安 (文字数)。aside は本文の候補選びでは数えない *)
iDocWebLen[s_String] := StringLength[StringTrim[s]];
iDocWebLen[e:XMLElement[_, _, c_List]] := If[iDocWebTag[e] === "aside", 0, Total[iDocWebLen /@ c]];
iDocWebLen[_] := 0;

(* pre 等の生テキスト (空白を保つ) *)
iDocWebRawText[c_List] := StringJoin[Map[iDocWebRawText1, c]];
iDocWebRawText[_] := "";
iDocWebRawText1[s_String] := s;
iDocWebRawText1[e:XMLElement[_, _, c_List]] := Switch[iDocWebTag[e], "br", "\n", "rt" | "rp", "", _, iDocWebRawText[c]];
iDocWebRawText1[_] := "";

SetAttributes[iDocWebReapBlocks, HoldFirst];
iDocWebReapBlocks[expr_] := With[{r = Reap[expr, "block"][[2]]}, If[r === {}, {}, First[r]]];

iDocWebEscape[s_String, mathMode_] := If[TrueQ[mathMode], s, StringReplace[s, "$" -> "\\$"]];

(* ---- URL の解決 (画像の src を絶対 URL に) ---- *)
iDocWebNormPath[p_String] :=
  Module[{pos = StringPosition[p, "?" | "#", 1], path, query, segs, out = {}},
    {path, query} = If[pos === {}, {p, ""}, {StringTake[p, pos[[1, 1]] - 1], StringDrop[p, pos[[1, 1]] - 1]}];
    segs = StringSplit[path, "/", All];
    Do[Which[s === ".", Null, s === "..", If[Length[out] > 1, out = Most[out]], True, AppendTo[out, s]], {s, segs}];
    If[segs =!= {} && MemberQ[{".", ".."}, Last[segs]], AppendTo[out, ""]];
    StringRiffle[out, "/"] <> query];

iDocWebResolveURL[base_String, refIn_String] :=
  Module[{ref = StringTrim[refIn], origin, path, dir},
    Which[
      ref === "", "",
      StringMatchQ[ref, RegularExpression["(?i)[a-z][a-z0-9+.-]*:.*"]], ref,
      ! StringMatchQ[base, RegularExpression["(?i)https?://.+"]], ref,
      StringStartsQ[ref, "//"], First[StringSplit[base, ":"]] <> ":" <> ref,
      True,
        origin = First[StringCases[base, RegularExpression["(?i)^https?://[^/?#]+"]]];
        path = StringReplace[StringDrop[base, StringLength[origin]], RegularExpression["[?#].*$"] -> ""];
        Which[
          StringStartsQ[ref, "/"], origin <> iDocWebNormPath[ref],
          StringStartsQ[ref, "?"] || StringStartsQ[ref, "#"], origin <> If[path === "", "/", path] <> ref,
          True,
            dir = If[path === "", "/", StringReplace[path, RegularExpression["[^/]*$"] -> ""]];
            origin <> iDocWebNormPath[dir <> ref]]]];
iDocWebResolveURL[_, ref_String] := ref;

(* ---- 本文でないものを落とす ---- *)
$iDocWebSkipTags = {"script", "style", "noscript", "template", "svg", "canvas", "iframe", "object", "embed",
  "form", "button", "select", "input", "textarea", "option", "nav", "footer", "head", "link", "meta",
  "dialog", "video", "audio", "map", "area", "track", "param"};
$iDocWebKeepTags = {"html", "body", "main", "article", "math", "x-tex"};
$iDocWebSkipTokens = {"share", "sharing", "social", "breadcrumb", "breadcrumbs", "sidebar", "related",
  "recommend", "recommended", "recommendation", "comments", "comment", "advert", "advertisement", "ads",
  "cookie", "cookies", "newsletter", "subscribe", "subscription", "promo", "footer", "navbar", "navigation",
  "nav", "menu", "toolbar", "skip", "banner", "popup", "modal"};
$iDocWebSkipClasses = {"sr-only", "visually-hidden", "visuallyhidden", "screen-reader-text", "ltx_error",
  "mw-editsection", "noprint", "ltx_page_footer"};
$iDocWebSkipRoles = {"navigation", "banner", "contentinfo", "complementary", "search", "dialog", "alertdialog",
  "menu", "menubar", "toolbar"};

iDocWebSkipQ[e:XMLElement[_, attrs_, c_], bodyLen_] :=
  Module[{tag = iDocWebTag[e], soft},
    Which[
      MemberQ[$iDocWebSkipTags, tag], True,
      MemberQ[$iDocWebKeepTags, tag], False,
      IntersectingQ[iDocWebClasses[attrs], $iDocWebSkipClasses], True,
      (* LaTeXML が変換に失敗した前置きの段落 (\newfloat 等が ltx_ERROR として並ぶ) *)
      tag === "p" && Count[c, XMLElement[_, a_, _] /; MemberQ[iDocWebClasses[a], "ltx_error"]] >= 2, True,
      True,
        soft = iDocWebHasAttrQ[attrs, "hidden"] ||
          ToLowerCase[iDocWebAttr[attrs, "aria-hidden"]] === "true" ||
          StringContainsQ[ToLowerCase[StringDelete[iDocWebAttr[attrs, "style"], WhitespaceCharacter]],
            "display:none" | "visibility:hidden"] ||
          MemberQ[$iDocWebSkipRoles, ToLowerCase[iDocWebAttr[attrs, "role"]]] ||
          IntersectingQ[iDocWebTokens[attrs], $iDocWebSkipTokens];
        (* 本文の大半を抱える要素は名前が紛らわしくても落とさない (class="content comments-on" 等) *)
        soft && iDocWebLen[e] < 0.4 bodyLen]];

iDocWebPrune[e:XMLElement[t_, attrs_, c_List], bodyLen_] :=
  If[iDocWebSkipQ[e, bodyLen], Nothing,
    XMLElement[t, attrs, Map[Which[StringQ[#], #, MatchQ[#, _XMLElement], iDocWebPrune[#, bodyLen], True, Nothing] &, c]]];

(* 数式の前処理: MathJax の <script type="math/tex"> と KaTeX の描画 (annotation に TeX がある) を
   x-tex 要素に置き換える (script は後で落とされ、KaTeX の描画部は aria-hidden なので) *)
iDocWebTeXAnnotation[e_] :=
  FirstCase[e, (XMLElement[t_, a_, c_] /; iDocWebTagName[t] === "annotation" &&
      StringContainsQ[ToLowerCase[iDocWebAttr[a, "encoding"]], "tex"]) :> StringTrim[iDocWebRawText[c]],
    Missing["NoTeX"], Infinity];

iDocWebPre[e:XMLElement[t_, attrs_, c_List]] :=
  Module[{tag = iDocWebTag[e], type = ToLowerCase[iDocWebAttr[attrs, "type"]], cls = iDocWebClasses[attrs], tex},
    Which[
      tag === "script" && StringStartsQ[type, "math/tex"],
        XMLElement["x-tex", {"display" -> If[StringContainsQ[type, "display"], "block", "inline"]}, {iDocWebRawText[c]}],
      MemberQ[cls, "katex-display"] || MemberQ[cls, "katex"],
        tex = iDocWebTeXAnnotation[e];
        If[StringQ[tex] && tex =!= "",
          XMLElement["x-tex", {"display" -> If[MemberQ[cls, "katex-display"], "block", "inline"]}, {tex}],
          XMLElement[t, attrs, iDocWebPre /@ c]],
      True, XMLElement[t, attrs, iDocWebPre /@ c]]];
iDocWebPre[x_] := x;

iDocWebMathJaxQ[x_] :=
  AnyTrue[Cases[x, (XMLElement[t_, a_, c_] /; MemberQ[{"script", "link"}, iDocWebTagName[t]]) :>
      iDocWebAttr[a, "src"] <> " " <> iDocWebAttr[a, "href"] <> " " <> iDocWebAttr[a, "type"] <> " " <>
        StringTake[iDocWebRawText[c], UpTo[3000]], Infinity],
    StringContainsQ[#, "mathjax" | "katex" | "math/tex", IgnoreCase -> True] &];

(* ---- 本文の容器を選ぶ: 最大の article → main → 本文の 7 割以上を持つ子へ降りていく ---- *)
iDocWebMain[body_XMLElement] :=
  Module[{total = iDocWebLen[body], pick, node, kids, k},
    pick = Function[cands, If[cands === {}, None,
      With[{b = First[MaximalBy[cands, iDocWebLen]]}, If[iDocWebLen[b] >= 0.3 total, b, None]]]];
    node = pick[Cases[body, e_XMLElement /; iDocWebTag[e] === "article", Infinity]];
    If[node =!= None, Return[node]];
    node = pick[Cases[body, (e:XMLElement[_, a_, _] /;
      iDocWebTag[e] === "main" || ToLowerCase[iDocWebAttr[a, "role"]] === "main"), Infinity]];
    If[node =!= None, Return[node]];
    node = body;
    While[True,
      kids = Cases[node[[3]], _XMLElement];
      If[kids === {}, Break[]];
      k = First[MaximalBy[kids, iDocWebLen]];
      If[iDocWebLen[k] > 0 && iDocWebLen[k] >= 0.7 iDocWebLen[node], node = k, Break[]]];
    node];

(* ---- 本文を歩いてブロックを Sow する ---- *)
$iDocWebInlineTags = {"a", "abbr", "b", "bdi", "bdo", "big", "br", "cite", "code", "data", "del", "dfn", "em",
  "font", "i", "img", "ins", "kbd", "label", "mark", "math", "x-tex", "nobr", "picture", "q", "rp", "rt", "ruby",
  "s", "samp", "small", "source", "span", "strike", "strong", "sub", "sup", "time", "tt", "u", "var", "wbr"};
iDocWebInlineQ[e_XMLElement] := MemberQ[$iDocWebInlineTags, iDocWebTag[e]];
iDocWebInlineQ[_] := False;

iDocWebInlineString[s_String, ctx_Association] :=
  iDocWebEscape[StringReplace[StringDelete[s, "\:200b" | "\:200c" | "\:200d" | "\:feff" | "\:00ad"],
    (WhitespaceCharacter | "\[NonBreakingSpace]") .. -> " "], ctx["MathMode"]];

iDocWebMathTeX[e:XMLElement[_, attrs_, c_]] :=
  Module[{tex = StringTrim[iDocWebAttr[attrs, "alttext"]]},
    If[tex === "", tex = Replace[iDocWebTeXAnnotation[e], Except[_String] -> ""]];
    If[tex === "", tex = StringTrim[StringReplace[iDocWebRawText[c], WhitespaceCharacter .. -> " "]]];
    tex];

iDocWebTeXSegment[tex_String, display_] :=
  Which[
    (* 所属ロゴ等の画像を数式として書いたもの (\raisebox{..}{\includegraphics..}) は捨てる *)
    tex === "" || StringContainsQ[tex, "\\includegraphics"], {},
    TrueQ[display], {<|"type" -> "display_math", "latex" -> tex, "label" -> ""|>},
    True, {"$" <> tex <> "$"}];

iDocWebCodeSegment[raw_String] :=
  Module[{t = StringTrim[raw, ("\n" | "\r") ..]},
    Which[
      StringTrim[t] === "", {},
      StringContainsQ[t, "\n"], {<|"type" -> "code", "text" -> iDocWebTrimCode[t]|>},
      True, {"`" <> StringReplace[StringTrim[t], "`" -> "'"] <> "`"}]];

iDocWebTrimCode[t_String] :=
  StringTrim[StringReplace[t, {"\r\n" -> "\n", "\r" -> "\n", "\[NonBreakingSpace]" -> " "}], "\n" ..];

(* 遅延読み込み (data-src 等) と srcset。透明 GIF / SVG のプレースホルダは使わない *)
iDocWebPlaceholderQ[s_String] :=
  StringStartsQ[s, "data:image/svg", IgnoreCase -> True] ||
  (StringStartsQ[s, "data:image/gif", IgnoreCase -> True] && StringLength[s] < 300);
iDocWebSrcsetFirst[s_String] :=
  Module[{parts = Select[StringTrim /@ StringSplit[s, ","], # =!= "" &]},
    If[parts === {}, "", First[StringSplit[First[parts]]]]];
iDocWebImgSrc[attrs_List, base_String] :=
  Module[{cands, s},
    cands = Select[iDocWebAttr[attrs, #] & /@ {"data-src", "data-original", "data-lazy-src", "data-actualsrc", "src"},
      StringTrim[#] =!= "" && ! iDocWebPlaceholderQ[#] &];
    s = If[cands =!= {}, First[cands],
      iDocWebSrcsetFirst[iDocWebAttr[attrs, "data-srcset"] <> "," <> iDocWebAttr[attrs, "srcset"]]];
    If[StringTrim[s] === "", "", iDocWebResolveURL[base, s]]];

(* アイコン・絵文字・バッジ・トラッキング画素は図にしない (短い alt だけ本文に残す) *)
iDocWebImgSegment[attrs_List, ctx_] :=
  Module[{src = iDocWebImgSrc[attrs, Lookup[ctx, "Base", ""]], alt = StringTrim[iDocWebAttr[attrs, "alt"]],
          w = iDocWebNum[iDocWebAttr[attrs, "width"]], h = iDocWebNum[iDocWebAttr[attrs, "height"]], small},
    small = (0 < w < 48) || (0 < h < 48) ||
      IntersectingQ[iDocWebTokens[attrs], {"emoji", "icon", "avatar", "logo", "badge"}] ||
      (* GitHub は画像を camo 経由にし、元の URL を data-canonical-src に残す *)
      StringContainsQ[src <> " " <> iDocWebAttr[attrs, "data-canonical-src"], "shields.io" | "badgen.net" | "/badge",
        IgnoreCase -> True];
    Which[
      w === 1 || h === 1, {},
      src === "" || small, If[alt =!= "" && StringLength[alt] <= 4, {alt}, {}],
      True, {<|"type" -> "image", "src" -> src, "alt" -> alt, "caption" -> ""|>}]];

iDocWebInline[e:XMLElement[_, attrs_, c_List], ctx_] :=
  Switch[iDocWebTag[e],
    "br", {"\n"},
    "wbr" | "rt" | "rp" | "source", {},
    "img", iDocWebImgSegment[attrs, ctx],
    "math", iDocWebTeXSegment[iDocWebMathTeX[e], ToLowerCase[iDocWebAttr[attrs, "display"]] === "block"],
    "x-tex", iDocWebTeXSegment[StringTrim[iDocWebRawText[c]], iDocWebAttr[attrs, "display"] === "block"],
    "code", iDocWebCodeSegment[iDocWebRawText[c]],
    _, Join @@ Map[iDocWebInlineChild[#, ctx] &, c]];
iDocWebInline[_, _] := {};

iDocWebInlineChild[s_String, ctx_] := {iDocWebInlineString[s, ctx]};
iDocWebInlineChild[e_XMLElement, ctx_] :=
  If[iDocWebInlineQ[e], iDocWebInline[e, ctx],
    (* インライン要素の中のブロック要素 (a の中の div 等) はブロックとして取り出し、段落を切る *)
    iDocWebReapBlocks[iDocWebBlock[e, ctx]]];
iDocWebInlineChild[_, _] := {};

(* 行ごとに空白を詰め、空行を除く (br は改行として残る) *)
iDocWebCleanInline[raw_String] :=
  StringRiffle[Select[StringTrim[StringReplace[#, " " .. -> " "]] & /@ StringSplit[raw, "\n", All], # =!= "" &], "\n"];

iDocWebSowText[raw_String, ctx_Association] :=
  Module[{t = iDocWebCleanInline[raw], m},
    If[t === "", Return[Null]];
    (* MathJax のページで段落全体が $$...$$ / \[...\] なら別行立て数式 *)
    If[TrueQ[ctx["MathMode"]],
      m = StringCases[t, RegularExpression["(?s)^\\$\\$(.+)\\$\\$$|^\\\\\\[(.+)\\\\\\]$"] -> "$1$2"];
      If[m =!= {} && StringTrim[First[m]] =!= "",
        Sow[<|"type" -> "display_math", "latex" -> StringTrim[First[m]], "label" -> ""|>, "block"];
        Return[Null]]];
    Sow[<|"type" -> Lookup[ctx, "ParaType", "paragraph"], "text" -> t|>, "block"]];

(* 容器の子: インラインの連なりは段落にまとめ、ブロック要素は再帰する *)
iDocWebEmit[children_List, ctx_Association] :=
  Module[{buf = {}, flush},
    flush[] := (iDocWebSowText[StringJoin[buf], ctx]; buf = {});
    Do[
      Which[
        StringQ[ch], AppendTo[buf, iDocWebInlineString[ch, ctx]],
        iDocWebInlineQ[ch],
          Do[If[StringQ[seg], AppendTo[buf, seg], flush[]; Sow[seg, "block"]], {seg, iDocWebInline[ch, ctx]}],
        MatchQ[ch, _XMLElement], flush[]; iDocWebBlock[ch, ctx],
        True, Null],
      {ch, children}];
    flush[]];

(* 見出し・表のセル・キャプション用: 中身を 1 つの文字列に (ブロック要素の境は改行) *)
iDocWebFlatText[c_List, ctx_] := iDocWebCleanInline[StringJoin[Map[iDocWebFlat[#, ctx] &, c]]];
iDocWebFlatText[_, _] := "";
iDocWebFlat[s_String, ctx_] := iDocWebInlineString[s, ctx];
iDocWebFlat[e:XMLElement[_, attrs_, c_List], ctx_] :=
  Switch[iDocWebTag[e],
    "br", "\n",
    "img", With[{a = StringTrim[iDocWebAttr[attrs, "alt"]]}, If[StringLength[a] <= 4, a, ""]],
    "math", With[{tex = iDocWebMathTeX[e]}, If[tex === "" || StringContainsQ[tex, "\\includegraphics"], "", "$" <> tex <> "$"]],
    "x-tex", With[{tex = StringTrim[iDocWebRawText[c]]}, If[tex === "", "", "$" <> tex <> "$"]],
    "code", With[{t = StringTrim[StringReplace[iDocWebRawText[c], {"`" -> "'", "\n" -> " "}]]}, If[t === "", "", "`" <> t <> "`"]],
    "rt" | "rp" | "source" | "wbr", "",
    _, With[{inner = StringJoin[Map[iDocWebFlat[#, ctx] &, c]]}, If[iDocWebInlineQ[e], inner, "\n" <> inner <> "\n"]]];
iDocWebFlat[_, _] := "";

iDocWebHeadingTagQ[tag_String] := StringMatchQ[tag, "h" ~~ DigitCharacter];

iDocWebBiblioQ[e:XMLElement[_, attrs_, _], ctx_] :=
  MemberQ[{"section", "div", "ol", "ul", "dl", "aside"}, iDocWebTag[e]] &&
  IntersectingQ[iDocWebTokens[attrs], {"bibliography", "references", "reflist", "biblist"}] &&
  iDocWebLen[e] < 0.5 Lookup[ctx, "TotalLen", Infinity];

iDocWebBlock[e:XMLElement[_, attrs_, c_List], ctx_Association] :=
  Module[{tag = iDocWebTag[e]},
    Which[
      iDocWebHeadingTagQ[tag],
        With[{t = StringReplace[StringReplace[iDocWebFlatText[c, ctx], "\n" -> " "],
            (WhitespaceCharacter | "\[Paragraph]" | "#") .. ~~ EndOfString -> ""]},
          If[t =!= "", Sow[<|"type" -> "heading", "tagLevel" -> FromDigits[StringDrop[tag, 1]], "text" -> t|>, "block"]]],
      iDocWebBiblioQ[e, ctx], iDocWebReferences[e, ctx],
      MemberQ[{"ul", "ol", "menu"}, tag], iDocWebList[e, ctx, 0],
      tag === "pre",
        With[{t = iDocWebTrimCode[iDocWebRawText[c]]},
          If[StringTrim[t] =!= "", Sow[<|"type" -> "code", "text" -> t|>, "block"]]],
      tag === "blockquote", iDocWebEmit[c, Append[ctx, "ParaType" -> "quote"]],
      tag === "table", iDocWebTable[e, ctx],
      tag === "figure", iDocWebFigure[e, ctx],
      tag === "hr", Null,
      True, iDocWebEmit[c, ctx]]];
iDocWebBlock[_, _] := Null;

(* 箇条書き: li ごとに 1 ブロック (入れ子は level + 1)。li の中のコード・図は項目の後に出す *)
iDocWebList[e:XMLElement[_, _, c_List], ctx_, depth_Integer] :=
  Module[{ordered = iDocWebTag[e] === "ol"},
    Do[
      Which[
        ! MatchQ[ch, _XMLElement], Null,
        iDocWebTag[ch] === "li", iDocWebListItem[ch, ctx, depth, ordered],
        MemberQ[{"ul", "ol"}, iDocWebTag[ch]], iDocWebList[ch, ctx, depth + 1],
        True, iDocWebBlock[ch, ctx]],
      {ch, c}]];

iDocWebListItem[XMLElement[_, _, c_List], ctx_, depth_Integer, ordered_] :=
  Module[{listQ, nested, blocks, paras, text},
    listQ = Function[x, MatchQ[x, _XMLElement] && MemberQ[{"ul", "ol"}, iDocWebTag[x]]];
    nested = Select[c, listQ];
    blocks = iDocWebReapBlocks[iDocWebEmit[Select[c, ! listQ[#] &], ctx]];
    paras = Select[blocks, MemberQ[{"paragraph", "quote"}, #["type"]] &];
    text = StringRiffle[Lookup[paras, "text", {}], "\n"];
    If[text =!= "", Sow[<|"type" -> "item", "text" -> text, "level" -> Min[depth, 2], "ordered" -> ordered|>, "block"]];
    Scan[Sow[#, "block"] &, Select[blocks, ! MemberQ[{"paragraph", "quote"}, #["type"]] &]];
    Scan[iDocWebList[#, ctx, depth + 1] &, nested]];

iDocWebRows[XMLElement[_, _, c_List]] :=
  Flatten[Map[Function[x, Which[
      ! MatchQ[x, _XMLElement], {},
      iDocWebTag[x] === "tr", {x},
      MemberQ[{"thead", "tbody", "tfoot"}, iDocWebTag[x]], Select[x[[3]], MatchQ[#, _XMLElement] && iDocWebTag[#] === "tr" &],
      True, {}]], c], 1];

(* 表: LaTeXML の数式表 (class が ltx_equation で始まる) は別行立て数式。レイアウト用の表 (1 列 / 入れ子 / 段落だらけ) は中身を本文として読む *)
iDocWebTable[e:XMLElement[_, attrs_, c_List], ctx_] :=
  Module[{cls = iDocWebClasses[attrs], trs = iDocWebRows[e], tex, label, cellsOf, rows, cap},
    cellsOf = Function[tr, Select[tr[[3]], MatchQ[#, _XMLElement] && MemberQ[{"td", "th"}, iDocWebTag[#]] &]];
    If[AnyTrue[cls, StringStartsQ[#, "ltx_equation"] || # === "ltx_eqn_table" &],
      tex = Select[Map[Function[tr, StringRiffle[Select[iDocWebMathTeX /@
          Cases[tr, x_XMLElement /; iDocWebTag[x] === "math", Infinity], # =!= "" &], " "]], trs], # =!= "" &];
      label = FirstCase[e, (XMLElement[_, a_, xc_] /; MemberQ[iDocWebClasses[a], "ltx_tag_equation"]) :>
        iDocWebFlatText[xc, ctx], "", Infinity];
      If[tex =!= {},
        Sow[<|"type" -> "display_math", "latex" -> StringRiffle[tex, " \\\\ "], "label" -> StringTrim[label]|>, "block"]];
      Return[Null]];
    If[trs === {} || Max[Length[cellsOf[#]] & /@ trs] <= 1 ||
       Cases[c, x_XMLElement /; iDocWebTag[x] === "table", Infinity] =!= {} ||
       Length[Cases[c, x_XMLElement /; MemberQ[{"p", "h1", "h2", "h3", "pre"}, iDocWebTag[x]], Infinity]] >= 3,
      Scan[iDocWebEmit[#[[3]], ctx] &, Flatten[cellsOf /@ trs]];
      Return[Null]];
    rows = Map[Function[tr, StringReplace[iDocWebFlatText[#[[3]], ctx], "\n" -> " "] & /@ cellsOf[tr]], trs];
    rows = Select[rows, # =!= {} && AnyTrue[#, # =!= "" &] &];
    cap = FirstCase[c, x_XMLElement /; iDocWebTag[x] === "caption" :> iDocWebFlatText[x[[3]], ctx], ""];
    If[rows =!= {}, Sow[<|"type" -> "table", "rows" -> rows, "caption" -> StringReplace[cap, "\n" -> " "]|>, "block"]]];

(* figure: 中の画像・表にキャプション (figcaption) を付ける。どちらも無ければキャプションだけ段落に *)
iDocWebFigure[XMLElement[_, _, c_List], ctx_] :=
  Module[{capEl, cap, blocks, idx},
    capEl = SelectFirst[c, MatchQ[#, _XMLElement] && iDocWebTag[#] === "figcaption" &, None];
    cap = If[capEl === None, "", StringReplace[iDocWebFlatText[capEl[[3]], ctx], "\n" -> " "]];
    blocks = iDocWebReapBlocks[iDocWebEmit[DeleteCases[c, x_ /; x === capEl], ctx]];
    idx = Flatten[Position[Lookup[blocks, "type", {}], "image" | "table", {1}]];
    Which[
      cap === "", Null,
      idx =!= {}, blocks[[Last[idx], "caption"]] = cap,
      True, AppendTo[blocks, <|"type" -> "caption", "text" -> cap|>]];
    Scan[Sow[#, "block"] &, blocks]];

(* 参考文献: 訳さない。見出しがあればそれを使う *)
iDocWebReferences[e:XMLElement[_, _, c_List], ctx_] :=
  Module[{head, items},
    head = FirstCase[e, x_XMLElement /; iDocWebHeadingTagQ[iDocWebTag[x]] :> iDocWebFlatText[x[[3]], ctx], "", Infinity];
    items = Cases[e, x_XMLElement /; iDocWebTag[x] === "li" :> iDocWebFlatText[x[[3]], ctx], Infinity];
    If[items === {},
      items = Lookup[Select[iDocWebReapBlocks[iDocWebEmit[c, ctx]], MemberQ[{"paragraph", "item"}, #["type"]] &], "text", {}]];
    items = Select[StringReplace[items, "\n" -> " "], # =!= "" && # =!= head &];
    If[items =!= {},
      Sow[<|"type" -> "references", "heading" -> StringReplace[head, "\n" -> " "], "items" -> items|>, "block"]]];

iDocWebTextLen[blocks_List] := Total[StringLength /@ Select[Lookup[blocks, "text", ""], StringQ]];

iDocWebPlainBlocks[plain_String, mathMode_] :=
  Map[<|"type" -> "paragraph", "text" -> iDocWebEscape[iDocWebCleanInline[#], mathMode]|> &,
    Select[StringSplit[StringReplace[plain, {"\r\n" -> "\n", "\r" -> "\n"}], RegularExpression["\\n[ \\t]*\\n"]],
      StringTrim[#] =!= "" &]];

iDocWebParseHTML[file_String, baseOpt_] :=
  Module[{x, metas, meta, pageURL, baseHref, resBase, title, mathMode, bodyPos, body, bodyLen, main, blocks, desc, plain},
    x = Quiet[Import[file, {"HTML", "XMLObject"}]];
    If[! MatchQ[x, XMLObject[_][___]], Return[$Failed]];
    metas = Cases[x, (XMLElement[t_, a_, _] /; iDocWebTagName[t] === "meta") :> a, Infinity];
    meta = Function[name, SelectFirst[Map[Function[a,
        If[ToLowerCase[iDocWebAttr[a, "property"]] === name || ToLowerCase[iDocWebAttr[a, "name"]] === name,
          StringTrim[iDocWebAttr[a, "content"]], ""]], metas], # =!= "" &, ""]];
    pageURL = Which[
      StringQ[baseOpt] && StringMatchQ[baseOpt, RegularExpression["(?i)https?://.+"]], baseOpt,
      meta["og:url"] =!= "", meta["og:url"],
      True, FirstCase[x, (XMLElement[t_, a_, _] /; iDocWebTagName[t] === "link" &&
        ToLowerCase[iDocWebAttr[a, "rel"]] === "canonical") :> iDocWebAttr[a, "href"], "", Infinity]];
    baseHref = FirstCase[x, (XMLElement[t_, a_, _] /; iDocWebTagName[t] === "base") :> iDocWebAttr[a, "href"], "", Infinity];
    resBase = If[StringTrim[baseHref] =!= "", iDocWebResolveURL[pageURL, baseHref], pageURL];
    title = If[meta["og:title"] =!= "", meta["og:title"],
      FirstCase[x, (XMLElement[t_, _, c_] /; iDocWebTagName[t] === "title") :>
        StringTrim[StringReplace[iDocWebRawText[c], WhitespaceCharacter .. -> " "]], "", Infinity]];
    mathMode = iDocWebMathJaxQ[x];
    (* HTML の Import は壊れた入れ子で html の下に {head, body, head, body} を作ることがある
       (theconversation.com: 本文は 2 つ目の body)。入れ子でない body をすべてつなぐ *)
    bodyPos = Position[x, e_XMLElement /; iDocWebTag[e] === "body"];
    bodyPos = Select[bodyPos, Function[p, ! AnyTrue[bodyPos, # =!= p && Length[#] < Length[p] && Take[p, Length[#]] === # &]]];
    body = Which[
      bodyPos === {}, FirstCase[x, _XMLElement, None, Infinity],
      Length[bodyPos] === 1, Extract[x, First[bodyPos]],
      True, XMLElement["body", {}, Join @@ Map[Extract[x, #][[3]] &, bodyPos]]];
    If[body === None, Return[$Failed]];
    body = iDocWebPre[body];
    bodyLen = iDocWebLen[body];
    main = iDocWebMain[iDocWebPrune[body, bodyLen]];
    blocks = iDocWebReapBlocks[iDocWebBlock[main,
      <|"Base" -> resBase, "MathMode" -> mathMode, "ParaType" -> "paragraph", "TotalLen" -> iDocWebLen[main]|>]];
    (* 本文がほとんど取れない (JavaScript で描くページ等): 説明文 → 全文のプレーンテキスト *)
    If[iDocWebTextLen[blocks] < 200,
      desc = If[meta["og:description"] =!= "", meta["og:description"], meta["description"]];
      If[desc =!= "", AppendTo[blocks, <|"type" -> "paragraph", "text" -> iDocWebEscape[desc, mathMode]|>]]];
    If[iDocWebTextLen[blocks] < 80,
      plain = Quiet[Import[file, "Plaintext"]];
      If[StringQ[plain], blocks = Join[blocks, iDocWebPlainBlocks[plain, mathMode]]]];
    <|"Title" -> title, "BaseURL" -> pageURL, "Blocks" -> blocks, "MathMode" -> mathMode|>];

(* テキスト / Markdown: 見出し (#)・箇条書き (- * + 1.)・コード (```)・段落 (空行区切り) *)
iDocWebJoinLines[lines_List] :=
  Fold[Function[{acc, ln},
    Which[
      acc === "", ln,
      ln === "", acc,
      (* 日本語・中国語の行の継ぎ目には空白を入れない *)
      First[ToCharacterCode[StringTake[acc, -1]]] >= 12288 || First[ToCharacterCode[StringTake[ln, 1]]] >= 12288, acc <> ln,
      True, acc <> " " <> ln]], "", lines];

iDocWebParseText[file_String, fmt_String] :=
  Module[{txt, mathMode, blocks = {}, para = {}, inCode = False, code = {}, flush, md = (fmt === "markdown"), indent, rest},
    txt = Quiet[Import[file, "Text", CharacterEncoding -> "UTF-8"]];
    If[! StringQ[txt], Return[$Failed]];
    txt = StringReplace[txt, {"\r\n" -> "\n", "\r" -> "\n"}];
    mathMode = StringContainsQ[txt, "$$" | "\\(" | "\\["];
    flush[] := (
      If[para =!= {}, AppendTo[blocks, <|"type" -> "paragraph",
        "text" -> iDocWebEscape[If[md, iDocWebJoinLines[para], StringRiffle[para, "\n"]], mathMode]|>]];
      para = {});
    Do[
      indent = StringLength[ln] - StringLength[StringReplace[ln, StartOfString ~~ (" " | "\t") .. -> ""]];
      rest = StringTrim[ln];
      Which[
        md && StringStartsQ[rest, "```"],
          If[inCode,
            AppendTo[blocks, <|"type" -> "code", "text" -> StringRiffle[code, "\n"]|>]; code = {}; inCode = False,
            flush[]; inCode = True],
        inCode, AppendTo[code, ln],
        rest === "", flush[],
        md && StringMatchQ[rest, RegularExpression["#{1,6}\\s+.*"]],
          flush[];
          AppendTo[blocks, <|"type" -> "heading",
            "tagLevel" -> StringLength[rest] - StringLength[StringReplace[rest, StartOfString ~~ "#" .. -> ""]],
            "text" -> iDocWebEscape[StringTrim[StringReplace[rest, StartOfString ~~ "#" .. -> ""]], mathMode]|>],
        md && StringMatchQ[rest, RegularExpression["([-*+]|\\d+[.)])\\s+.*"]],
          flush[];
          AppendTo[blocks, <|"type" -> "item", "level" -> Min[2, Floor[indent / 2]],
            "ordered" -> StringMatchQ[rest, RegularExpression["\\d+[.)].*"]],
            "text" -> iDocWebEscape[StringTrim[StringReplace[rest, RegularExpression["^([-*+]|\\d+[.)])\\s+"] -> ""]], mathMode]|>],
        True, AppendTo[para, rest]],
      {ln, StringSplit[txt, "\n", All]}];
    If[inCode && code =!= {}, AppendTo[blocks, <|"type" -> "code", "text" -> StringRiffle[code, "\n"]|>]];
    flush[];
    <|"Title" -> FileBaseName[file], "BaseURL" -> "", "Blocks" -> blocks, "MathMode" -> mathMode|>];

iDocWebNormalizeBlock[b_Association] :=
  Join[<|"text" -> "", "translation" -> "", "caption" -> "", "captionTranslation" -> "", "rowsTranslation" -> None,
    "Image" -> None, "level" -> 1, "ordered" -> False, "latex" -> "", "label" -> "", "src" -> "", "alt" -> "",
    "rows" -> {}, "items" -> {}, "heading" -> ""|>, b];

(* 題の照合用: 空白・記号を除いて小文字に *)
iDocWebTitleKey[s_String] := ToLowerCase[StringDelete[s, Except[LetterCharacter | DigitCharacter]]];
(* 見出しがページの題 (<title> / og:title) と同じものを指すか: 包含するか、先頭が十分長く一致する
   (<title> は "記事名 | サイト名" や途中で "..." と切られていることがある) *)
iDocWebSameTitleQ[h_String, t_String] :=
  Module[{a = iDocWebTitleKey[h], b = iDocWebTitleKey[t]},
    If[StringLength[a] < 4 || StringLength[b] < 4, Return[False]];
    StringContainsQ[b, a] || StringContainsQ[a, b] ||
      StringLength[iDocWebCommonPrefix[a, b]] >= Min[12, Ceiling[0.6 Min[StringLength[a], StringLength[b]]]]];
iDocWebCommonPrefix[a_String, b_String] :=
  Module[{k = 0, n = Min[StringLength[a], StringLength[b]]},
    While[k < n && StringTake[a, {k + 1}] === StringTake[b, {k + 1}], k++];
    StringTake[a, k]];

(* 仕上げ: 連続する重複を除き、題を決め、見出しの深さを揃える。
   題 = 先頭近く (8 ブロック以内) の h1/h2 のうちページの題と同じもの。ページの題が無ければ最初の h1、
   どれも合わなければページの題を先頭に置く (カテゴリ名の h1 などは見出しのまま残る) *)
iDocWebFinalizeBlocks[blocksIn_List, title_String] :=
  Module[{blocks = Select[blocksIn, AssociationQ], t = StringTrim[title], cand, levels, base},
    blocks = First /@ Split[blocks, #1["type"] === #2["type"] && Lookup[#1, "text", 1] === Lookup[#2, "text", 2] &];
    cand = FirstPosition[Take[blocks, UpTo[8]],
      b_ /; b["type"] === "heading" && If[t === "", b["tagLevel"] === 1, b["tagLevel"] <= 2 && iDocWebSameTitleQ[b["text"], t]],
      None, {1}];
    Which[
      cand =!= None, blocks[[cand[[1]]]] = <|"type" -> "title", "text" -> blocks[[cand[[1]], "text"]]|>,
      t =!= "", PrependTo[blocks, <|"type" -> "title", "text" -> t|>]];
    levels = Cases[blocks, b_ /; b["type"] === "heading" :> b["tagLevel"]];
    base = If[levels === {}, 1, Min[levels]];
    blocks = Map[If[#["type"] === "heading", Append[#, "level" -> Clip[#["tagLevel"] - base + 1, {1, 3}]], #] &, blocks];
    Map[iDocWebNormalizeBlock, blocks]];

iDocWebLanguageSample[blocks_List] :=
  StringTake[StringRiffle[Lookup[Select[blocks, MemberQ[{"title", "heading", "paragraph", "quote", "item", "caption"}, #["type"]] &],
    "text", {}], "\n"], UpTo[8000]];

iDocWebDefaultDirective[lang_String] :=
  If[StringMatchQ[lang, "Japanese", IgnoreCase -> True],
    "Web ページの文章なので、内容に正確で自然な日本語に翻訳する (文体は原文の調子に合わせる)",
    "Translate faithfully into natural, readable " <> iDocLangPromptName[lang] <> "; keep the tone of the original."];

(* ---- 翻訳: 項目を JSON でまとめて渡す (1 回 6000 字 / 40 項目まで) ---- *)
$iDocWebTranslatable = {"title", "heading", "paragraph", "quote", "item", "caption"};

iDocWebJSON[expr_] := ByteArrayToString[ExportByteArray[expr, "RawJSON", "Compact" -> True], "UTF-8"];

iDocWebHasLettersQ[s_String] := StringContainsQ[s, LetterCharacter];
iDocWebHasLettersQ[_] := False;

(* 文字の多い表だけ訳す (数値の表は訳さない) *)
iDocWebTextTableQ[rows_List] :=
  Module[{s = StringJoin[Flatten[rows]], nL, nAll},
    nL = StringCount[s, LetterCharacter];
    nAll = StringLength[StringDelete[s, WhitespaceCharacter]];
    nL >= 20 && nAll > 0 && nL >= 0.3 nAll];

iDocWebItemSize[it_Association] :=
  10 + If[KeyExistsQ[it, "rows"], Total[StringLength /@ Flatten[it["rows"]]], StringLength[it["text"]]];

iDocWebBatches[items_List, maxChars_Integer, maxN_Integer] :=
  Module[{out = {}, cur = {}, n = 0, size},
    Do[
      size = iDocWebItemSize[it];
      If[cur =!= {} && (n + size > maxChars || Length[cur] >= maxN), AppendTo[out, cur]; cur = {}; n = 0];
      AppendTo[cur, it]; n += size,
      {it, items}];
    If[cur =!= {}, AppendTo[out, cur]];
    out];

iDocWebTranslatePrompt[items_List, cfg_Association] :=
  Module[{lang = iDocLangPromptName[cfg["TargetLanguage"]]},
    StringJoin[
      "Translate the items of a web page into ", lang,
      If[cfg["SourceLanguage"] =!= "", " (the page is written in " <> iDocLangPromptName[cfg["SourceLanguage"]] <> ")", ""], ".\n",
      "Return ONLY a JSON object {\"items\": [{\"id\": \"...\", \"text\": \"...\"}, ...]} with exactly one entry per input item and the same ids. ",
      "For an input item that has \"rows\" (a table), return \"rows\" instead of \"text\", with exactly the same number of rows and cells.\n",
      "Rules:\n",
      "  - Translate faithfully and completely. Do not summarize, merge, split, reorder or drop items.\n",
      "  - Keep inline LaTeX between $...$, code between backticks `...`, escaped dollar signs \\$, URLs, numbers, ",
      "citation markers like [3], and names of people and products unchanged.\n",
      "  - Keep the line breaks inside an item.\n",
      "  - If an item is already in ", lang, ", return it unchanged.\n",
      "  - Output valid JSON only (escape backslashes and quotes). No markdown fences, no comments.\n",
      If[StringTrim[cfg["Directive"]] =!= "", "Translation directive: " <> cfg["Directive"] <> "\n", ""],
      iDocPaperDictionaryPrompt[cfg["Dictionary"]],
      "\nItems (JSON):\n", iDocWebJSON[items]]];

(* 応答 → <|id -> 訳文 | 訳した行列|>。表は行数・セル数が一致したものだけ採る *)
iDocWebParseTranslations[parsed_, items_List] :=
  Module[{arr, byId = Association[Map[#["id"] -> # &, items]], out = <||>},
    arr = Which[
      AssociationQ[parsed], Lookup[parsed, "items", Lookup[parsed, "translations", {}]],
      ListQ[parsed], parsed,
      True, Return[$Failed, Module]];
    If[! ListQ[arr], Return[$Failed]];
    Do[
      If[AssociationQ[e],
        With[{id = iDocPaperStr[Lookup[e, "id", ""]]},
          With[{src = Lookup[byId, id, None]},
            Which[
              src === None, Null,
              KeyExistsQ[src, "rows"],
                With[{r = Lookup[e, "rows", None]},
                  If[ListQ[r] && AllTrue[r, ListQ] && Map[Length, r] === Map[Length, src["rows"]],
                    out[id] = Map[iDocPaperStr, r, {2}]]],
              True,
                With[{t = iDocPaperStr[Lookup[e, "text", ""]]}, If[StringTrim[t] =!= "", out[id] = t]]]]]],
      {e, arr}];
    out];

iDocWebTranslateBatch[items_List, cfg_Association] :=
  Module[{prompt = iDocWebTranslatePrompt[items, cfg], resp, map},
    resp = iDocPaperQuery[{prompt}, cfg];
    map = If[StringQ[resp], iDocWebParseTranslations[iDocPaperParseJSON[resp], items], $Failed];
    If[(! AssociationQ[map] || Length[map] < Length[items] / 2) && ! iDocPaperConnectionErrorQ[$iDocPaperLastError],
      iDocPaperLog[cfg["Verbose"], "翻訳の応答を読めません。JSON のみで再依頼します。"];
      resp = iDocPaperQuery[{prompt <> "\n\nYour previous answer was not valid JSON or missed items. Return the complete JSON object only."}, cfg];
      With[{m2 = If[StringQ[resp], iDocWebParseTranslations[iDocPaperParseJSON[resp], items], $Failed]},
        If[AssociationQ[m2] && (! AssociationQ[map] || Length[m2] > Length[map]), map = m2]]];
    If[AssociationQ[map], map, $Failed]];

(* 返り値: {訳を入れたブロック列, 訳せなかった項目数}。接続失敗が 2 回続いたら $Failed *)
iDocWebTranslateBlocks[blocks_List, cfg_Association] :=
  Module[{items = {}, refs = {}, k = 0, add, batches, out = blocks, nFail = 0, connFail = 0, res, ids},
    add = Function[{item, i, field}, k++;
      AppendTo[items, Append[item, "id" -> ("t" <> ToString[k])]]; AppendTo[refs, {"t" <> ToString[k], i, field}]];
    Do[
      With[{b = blocks[[i]]},
        If[MemberQ[$iDocWebTranslatable, b["type"]] && iDocWebHasLettersQ[b["text"]],
          add[<|"text" -> b["text"]|>, i, "translation"]];
        If[MemberQ[{"image", "table"}, b["type"]] && iDocWebHasLettersQ[b["caption"]],
          add[<|"text" -> b["caption"]|>, i, "captionTranslation"]];
        If[b["type"] === "table" && iDocWebTextTableQ[b["rows"]],
          add[<|"rows" -> b["rows"]|>, i, "rowsTranslation"]]],
      {i, Length[blocks]}];
    If[items === {}, Return[{blocks, 0}]];
    batches = iDocWebBatches[items, 6000, 40];
    iDocPaperLog[cfg["Verbose"], ToString[Length[items]] <> " 項目を " <> ToString[Length[batches]] <> " 回に分けて翻訳中 (" <>
      If[cfg["SourceLanguage"] =!= "", cfg["SourceLanguage"] <> " → ", ""] <> cfg["TargetLanguage"] <> ")..."];
    Do[
      iDocPaperLog[cfg["Verbose"], "翻訳 " <> ToString[j] <> "/" <> ToString[Length[batches]] <> " ..."];
      res = iDocWebTranslateBatch[batches[[j]], cfg];
      ids = Lookup[batches[[j]], "id"];
      If[AssociationQ[res],
        connFail = 0;
        Scan[Function[r,
            With[{v = Lookup[res, r[[1]], Missing[]]}, If[MissingQ[v], nFail++, out[[r[[2]], r[[3]]]] = v]]],
          Select[refs, MemberQ[ids, #[[1]]] &]],
        nFail += Length[ids];
        connFail = If[iDocPaperConnectionErrorQ[$iDocPaperLastError], connFail + 1, 0];
        If[connFail >= 2,
          Message[DocImportPaper::abort, connFail, StringTake[$iDocPaperLastError, UpTo[300]]];
          Return[$Failed, Module]]],
      {j, Length[batches]}];
    {out, nFail}];

(* ---- 画像の取得 (PNG / JPEG / GIF / WebP / BMP。SVG は Import できたときだけ) ---- *)
iDocWebFetchImage[src_String] :=
  Module[{bytes = $Failed, ct = "", resp, fmt, img},
    Which[
      StringStartsQ[src, "data:image/", IgnoreCase -> True] && StringContainsQ[src, ";base64,"],
        ct = ToLowerCase[First[StringSplit[StringDrop[src, 5], ";"]]];
        bytes = Quiet[Check[BaseDecode[Last[StringSplit[src, ";base64,", 2]]], $Failed]],
      StringMatchQ[src, RegularExpression["(?i)https?://.+"]],
        resp = Quiet[URLRead[HTTPRequest[src, <|"Headers" -> {"User-Agent" -> "Mozilla/5.0 (Windows NT 10.0; Win64; x64)"}|>],
          {"StatusCode", "ContentType", "BodyByteArray"}, TimeConstraint -> 20]];
        If[AssociationQ[resp] && resp["StatusCode"] === 200,
          bytes = resp["BodyByteArray"];
          ct = ToLowerCase[iDocPaperStr[resp["ContentType"]]]],
      True, Null];
    If[! ByteArrayQ[bytes] || Length[bytes] < 64 || Length[bytes] > 15 10^6, Return[$Failed]];
    If[StringContainsQ[ct, "html"], Return[$Failed]];
    fmt = Which[
      StringContainsQ[ct, "png"], "PNG",
      StringContainsQ[ct, "jpeg" | "jpg"], "JPEG",
      StringContainsQ[ct, "gif"], "GIF",
      StringContainsQ[ct, "webp"], "WebP",
      StringContainsQ[ct, "bmp"], "BMP",
      StringContainsQ[ct, "svg"], "SVG",
      True, Automatic];
    img = Quiet[Check[If[fmt === Automatic, ImportByteArray[bytes], ImportByteArray[bytes, fmt]], $Failed]];
    If[ListQ[img] && img =!= {}, img = First[img]];
    If[! ImageQ[img], Return[$Failed]];
    If[Max[ImageDimensions[img]] < 24, Return[$Failed]];
    If[First[ImageDimensions[img]] > 900, img = ImageResize[img, 900]];
    img];

iDocWebFetchImages[blocks_List, cfg_Association, maxN_Integer] :=
  Module[{idx = Flatten[Position[Lookup[blocks, "type"], "image", {1}]], out = blocks, todo},
    todo = Take[idx, UpTo[maxN]];
    If[todo === {}, Return[blocks]];
    iDocPaperLog[cfg["Verbose"], "画像 " <> ToString[Length[todo]] <> " 枚を取得中" <>
      If[Length[idx] > maxN, " (" <> ToString[Length[idx]] <> " 枚中。残りはリンク)", ""] <> "..."];
    Scan[(out[[#, "Image"]] = iDocWebFetchImage[out[[#, "src"]]]) &, todo];
    out];

(* ---- ブロック → セル ---- *)
(* セルの文字列: `code` は等幅、$...$ はインライン数式、\$ はドル記号に戻す *)
iDocWebTextData[s_String] :=
  Module[{t = StringReplace[s, "\\$" -> "\:e000"], parts},
    parts = StringSplit[t, "`" ~~ Shortest[c__] ~~ "`" :> iDocWebCodeTag[c]];
    parts = Flatten[Map[
      If[MatchQ[#, iDocWebCodeTag[_]], {StyleBox[First[#], FontFamily -> "Courier New"]},
        Replace[DocPaperTextToTextData[#], {TextData[l_List] :> l, x_ :> {x}}]] &, parts], 1];
    parts = DeleteCases[parts /. str_String :> StringReplace[str, "\:e000" -> "$"], ""];
    Which[
      parts === {}, "",
      Length[parts] === 1 && StringQ[First[parts]], First[parts],
      True, TextData[parts]]];

iDocWebUnescape[s_String] := StringReplace[s, {"\\$" -> "$", "`" -> ""}];

iDocWebTextCell[b_Association, file_String, style_String, extraRules_List] :=
  Module[{text = StringTrim[b["text"]], tr = StringTrim[Lookup[b, "translation", ""]], content, rules, cellOpts},
    If[tr =!= "" && tr =!= text,
      content = iDocWebTextData[tr];
      rules = Join[{"mode" -> "translated", "translation" -> tr, "translationSrc" -> text,
        "showTranslation" -> True, "cleanText" -> tr}, extraRules];
      cellOpts = $iDocTranslationCellOpts,
      content = iDocWebTextData[text];
      rules = Join[{"cleanText" -> text}, extraRules];
      cellOpts = {}];
    rules = Join[rules, {"refSources" -> {{file, All}}, "paperType" -> b["type"]}];
    Cell[content, style, Sequence @@ cellOpts, iDocPaperTags[rules]]];

iDocWebItemStyle[b_Association] :=
  {{"Item", "Subitem", "Subsubitem"}, {"ItemNumbered", "SubitemNumbered", "SubsubitemNumbered"}}[[
    If[TrueQ[b["ordered"]], 2, 1], Clip[b["level"], {0, 2}] + 1]];

iDocWebHyperlink[url_String] := ButtonBox[url, BaseStyle -> "Hyperlink", ButtonData -> {URL[url], None}, ButtonNote -> url];

iDocWebSourceCell[url_String, file_String, cfg_Association] :=
  Cell[TextData[Flatten[{iL["出典: ", "Source: "],
      If[StringStartsQ[url, "http"], iDocWebHyperlink[url], FileNameTake[file]],
      "  (" <> iDocPaperTranslateNote[cfg] <> ")"}]], "Text",
    iDocPaperTags[{"paperType" -> "source", "refSources" -> {{file, All}}}]];

iDocWebDisplayMathCell[b_Association, file_String] :=
  Module[{latex = StringTrim[b["latex"]], label = StringTrim[b["label"]], boxes, rules},
    rules = {"paperLatex" -> latex, "paperLabel" -> If[label === "", None, label],
      "refSources" -> {{file, All}}, "paperType" -> "display_math"};
    boxes = DocPaperTeXToBoxes[latex];
    If[boxes =!= $Failed,
      Cell[BoxData[FormBox[If[label === "", boxes, RowBox[{boxes, "      ", label}]], TraditionalForm]],
        "DisplayFormula", iDocPaperTags[rules]],
      Cell[latex <> If[label === "", "", "    " <> label], "Text", FontFamily -> "Courier New", iDocPaperTags[rules]]]];

iDocWebCaptionCell[b_Association, file_String, key_String] :=
  iDocWebTextCell[<|"type" -> "caption", "text" -> b["caption"], "translation" -> b["captionTranslation"]|>,
    file, "Text", {"paperCaptionFor" -> key}];

iDocWebImageCells[b_Association, file_String, key_String] :=
  Module[{img = b["Image"], cap = StringTrim[b["caption"]], src = b["src"], link, rules},
    link = StringStartsQ[src, "http"];
    rules = {"figLabel" -> key,
      "figCaption" -> If[cap === "", None,
        StringReplace[iDocPaperPlainMath[StringReplace[cap, "\\$" -> "\:e000"]], "\:e000" -> "$"]],
      "refSources" -> {{file, All}}, "paperType" -> "figure", "paperImageURL" -> If[link, src, None]};
    Join[
      {If[ImageQ[img],
        Cell[BoxData[ToBoxes[img]], "Text", iDocPaperTags[rules]],
        Cell[TextData[Flatten[{"[" <> iL["画像", "Image"] <> If[b["alt"] =!= "", ": " <> b["alt"], ""] <> "]",
            If[link, {" ", iDocWebHyperlink[src]}, {}]}]], "Text", iDocPaperTags[rules]]]},
      If[cap === "", {}, {iDocWebCaptionCell[b, file, key]}]]];

iDocWebTableCells[b_Association, file_String, key_String] :=
  Module[{rows = b["rows"], tr = b["rowsTranslation"], shown, ncol, widths, rules},
    shown = If[ListQ[tr], tr, rows];
    ncol = Max[Length /@ shown];
    shown = Map[iDocWebUnescape, PadRight[#, ncol, ""] & /@ shown, {2}];
    widths = Table[If[Max[StringLength /@ shown[[All, j]]] > 40, 24, Automatic], {j, ncol}];
    rules = {"figLabel" -> key, "refSources" -> {{file, All}}, "paperType" -> "table",
      "paperTableSrc" -> If[ListQ[tr], rows, None]};
    Join[
      If[StringTrim[b["caption"]] === "", {}, {iDocWebCaptionCell[b, file, key]}],
      {Cell[BoxData[ToBoxes[Grid[shown, Frame -> All, FrameStyle -> GrayLevel[0.75], Alignment -> {Left, Top},
          Spacings -> {1, 0.6}, ItemSize -> {widths, Automatic}, Background -> {None, {1 -> GrayLevel[0.94]}}]]],
        "Text", iDocPaperTags[rules]]}]];

iDocWebReferenceCells[b_Association, file_String] :=
  {Cell[If[StringTrim[b["heading"]] =!= "", iDocWebUnescape[b["heading"]], "References"], "Subsection",
     iDocPaperTags[{"refSources" -> {{file, All}}, "paperType" -> "heading"}]],
   Cell[StringRiffle[iDocWebUnescape /@ b["items"], "\n"], "Text",
     iDocPaperTags[{"refSources" -> {{file, All}}, "paperType" -> "references"}]]};

iDocWebBlocksToCells[blocks_List, file_String, url_String, cfg_Association] :=
  Module[{cells = {}, styles = cfg["HeadingStyles"], refs = {}, fig = 0, tab = 0, srcDone = False},
    Do[
      Switch[b["type"],
        "title",
          AppendTo[cells, iDocWebTextCell[b, file, styles[[1]], {}]];
          If[! srcDone, AppendTo[cells, iDocWebSourceCell[url, file, cfg]]; srcDone = True],
        "heading", AppendTo[cells, iDocWebTextCell[b, file, styles[[Clip[b["level"], {1, 3}] + 1]], {}]],
        "item", AppendTo[cells, iDocWebTextCell[b, file, iDocWebItemStyle[b], {}]],
        "code", AppendTo[cells, Cell[b["text"], "Program", iDocPaperTags[{"paperType" -> "code", "refSources" -> {{file, All}}}]]],
        "display_math", AppendTo[cells, iDocWebDisplayMathCell[b, file]],
        "image", fig++; cells = Join[cells, iDocWebImageCells[b, file, "fig" <> ToString[fig]]],
        "table", tab++; cells = Join[cells, iDocWebTableCells[b, file, "table" <> ToString[tab]]],
        "references", AppendTo[refs, b],
        _, If[StringTrim[b["text"]] =!= "", AppendTo[cells, iDocWebTextCell[b, file, "Text", {}]]]],
      {b, blocks}];
    If[! srcDone, PrependTo[cells, iDocWebSourceCell[url, file, cfg]]];
    Join[cells, Flatten[Map[iDocWebReferenceCells[#, file] &, refs], 1]]];

(* 第二部 (計算の再構成) に渡す本文 *)
iDocWebBodyText[blocks_List] :=
  StringRiffle[Map[Switch[#["type"],
      "title", "# " <> #["text"],
      "heading", StringRepeat["#", Clip[#["level"] + 1, {2, 4}]] <> " " <> #["text"],
      "display_math", "$$ " <> #["latex"] <> " $$ " <> #["label"],
      "code", "```\n" <> #["text"] <> "\n```",
      "paragraph" | "quote" | "item" | "caption", #["text"],
      _, Nothing] &, blocks], "\n\n"];

DocImportWebPage[fileIn_String, opts:OptionsPattern[]] :=
  Module[{file, fmt, wget, cfg, doc, title, url, blocks, tr, nFail = 0, cells, comp, nbExpr, outPath, t0 = AbsoluteTime[]},
    file = AbsoluteFileName[fileIn];
    If[! StringQ[file] || ! FileExistsQ[file], Message[DocImportWebPage::nofile, fileIn]; Return[$Failed]];
    fmt = iDocWebFormat[file];
    If[fmt === None, Message[DocImportWebPage::format, file]; Return[$Failed]];
    wget = Function[name, Lookup[Join[Flatten[{opts}], Options[DocImportWebPage]], name]];
    cfg = iDocPaperConfig[{opts}, Options[DocImportWebPage]];
    If[! StringQ[wget["Directive"]], cfg["Directive"] = iDocWebDefaultDirective[cfg["TargetLanguage"]]];
    doc = If[fmt === "html", iDocWebParseHTML[file, wget["BaseURL"]], iDocWebParseText[file, fmt]];
    If[! AssociationQ[doc], Message[DocImportWebPage::empty, file]; Return[$Failed]];
    title = With[{t = wget["Title"]}, If[StringQ[t] && StringTrim[t] =!= "", StringTrim[t], doc["Title"]]];
    url = With[{u = wget["BaseURL"]}, If[StringQ[u] && StringTrim[u] =!= "", StringTrim[u], doc["BaseURL"]]];
    blocks = iDocWebFinalizeBlocks[doc["Blocks"], iDocWebEscape[title, doc["MathMode"]]];
    If[Count[blocks, b_ /; b["type"] =!= "title"] === 0, Message[DocImportWebPage::empty, file]; Return[$Failed]];
    cfg = iDocPaperResolveTranslate[cfg, iDocWebLanguageSample[blocks]];
    iDocPaperLog[cfg["Verbose"], FileNameTake[file] <> ": " <> ToString[Length[blocks]] <> " ブロック (" <>
      iDocPaperTranslateNote[cfg] <> ")"];
    $DocPaperLastAnalysis = <|"Source" -> file, "URL" -> url, "Kind" -> "web", "Pages" -> {},
      "SourceLanguage" -> cfg["SourceLanguage"], "TargetLanguage" -> cfg["TargetLanguage"],
      "Translated" -> cfg["Translate"], "FailedPages" -> {}, "FailedItems" -> 0|>;
    If[TrueQ[cfg["Translate"]],
      tr = iDocWebTranslateBlocks[blocks, cfg];
      If[tr === $Failed,
        iDocPaperLog[True, "LLM サーバに接続できません: " <> StringTake[$iDocPaperLastError, UpTo[300]]];
        Return[$Failed]];
      {blocks, nFail} = tr;
      $DocPaperLastAnalysis["FailedItems"] = nFail;
      If[nFail > 0, iDocPaperLog[True, "翻訳できなかった項目: " <> ToString[nFail] <> " (原文のまま残します)"]]];
    If[TrueQ[wget["Images"]],
      blocks = iDocWebFetchImages[blocks, cfg, Replace[wget["MaxImages"], Except[_Integer?NonNegative] -> 30]]];
    $DocPaperLastAnalysis["Blocks"] = Map[KeyDrop[#, {"Image"}] &, blocks];
    cells = iDocWebBlocksToCells[blocks, file, url, cfg];
    If[TrueQ[cfg["Reconstruct"]],
      comp = iDocPaperExtractComputationsImpl[iDocWebBodyText[blocks], cfg];
      If[AssociationQ[comp],
        cells = Join[cells, iDocPaperComputationCells[comp, file, cfg["TargetLanguage"]]],
        iDocPaperLog[True, "計算の再構成に失敗しました (本文のみ出力します)。"]]];
    cells = Join[iDocPaperMetaCells[cfg], cells];
    $DocPaperLastAnalysis["Cells"] = Length[cells];
    nbExpr = Notebook[cells,
      WindowSize -> {900, 800},
      TaggingRules -> {$iDocTagRoot -> {
        "paperSource" -> If[url =!= "", url, file],
        "paperFile" -> file,
        "paperKind" -> "web",
        "paperImportedAt" -> DateString["ISODateTime"],
        "paperTargetLanguage" -> cfg["TargetLanguage"],
        "paperSourceLanguage" -> cfg["SourceLanguage"],
        "paperTranslated" -> TrueQ[cfg["Translate"]]}}];
    outPath = iDocPaperOutputPath[file, cfg["OutputPath"]];
    iDocPaperFinishNotebook[nbExpr, outPath, cfg, file, Length[cells], t0]];

(* ============================================================
   パレット用アクション (documentation.wl のパレットから呼ばれる)
   ============================================================ *)

iDocImportPaperAction[] :=
  Module[{path},
    path = SystemDialogInput["FileOpen", {"", {iL["PDF ファイル", "PDF files"] -> {"*.pdf"},
        iL["Web ページ (HTML)", "Web pages (HTML)"] -> {"*.html", "*.htm"}}},
      WindowTitle -> iL["論文 PDF / Web ページを選択", "Choose a paper PDF or a web page"]];
    If[!StringQ[path] || !FileExistsQ[path], Return[$Canceled]];
    DocImportPaper[path, Fallback -> TrueQ[Quiet[ClaudeCode`GetPaletteFallback[]]]]];

End[];
EndPackage[];
