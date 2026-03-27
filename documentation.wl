(* ::Package:: *)

(* documentation.wl -- Documentation Authoring Package
   This file is encoded in UTF-8.
   Load via: Block[{$CharacterEncoding = "UTF-8"}, Get["documentation.wl"]]

   \:30a2\:30a6\:30c8\:30e9\:30a4\:30f3\:30d7\:30ed\:30bb\:30c3\:30b5\:62e1\:5f35: \:30a2\:30a4\:30c7\:30a2 \[RightArrow] \:30d1\:30e9\:30b0\:30e9\:30d5\:5c55\:958b\:30b7\:30b9\:30c6\:30e0\:3002

   \:898f\:7d04:
   - \:30bb\:30eb\:5185\:5bb9\:3078\:306e\:30a2\:30af\:30bb\:30b9\:306f\:3059\:3079\:3066 NBAccess` \:306e\:516c\:958b\:95a2\:6570\:7d4c\:7531\:3067\:884c\:3046\:3002
   - LLM \:547c\:3073\:51fa\:3057\:306f NBAccess`NBCellTransformWithLLM \:7d4c\:7531\:3067\:884c\:3046\:3002
     (\:30d7\:30e9\:30a4\:30d0\:30b7\:30fc\:30ec\:30d9\:30eb\:306b\:5fdc\:3058\:305f LLM \:81ea\:52d5\:9078\:629e\:306fNBAccess\:304c\:62c5\:5f53)
   - \:30d1\:30ec\:30c3\:30c8 UI \:306e\:305f\:3081\:306e\:30ce\:30fc\:30c8\:30d6\:30c3\:30af/\:30bb\:30eb\:30a4\:30f3\:30c7\:30c3\:30af\:30b9\:89e3\:6c7a\:306e\:307f\:5185\:90e8\:3067\:884c\:3046\:3002

   \:4f9d\:5b58: NBAccess` (\:30bb\:30eb\:30a2\:30af\:30bb\:30b9\:30fbLLM \:30eb\:30fc\:30c6\:30a3\:30f3\:30b0), ClaudeCode` (LLM \:30b3\:30fc\:30eb\:30d0\:30c3\:30af)

*)

BeginPackage["Documentation`"];

(* ---- \:4f9d\:5b58\:30d1\:30c3\:30b1\:30fc\:30b8 ---- *)
Needs["NBAccess`"];
Needs["ClaudeCode`"];

(* ---- \:516c\:958bAPI ---- *)

DocExpandIdea::usage =
  "DocExpandIdea[nb, cellIdx] \:306f\:6307\:5b9a\:30bb\:30eb\:306e\:30a2\:30a4\:30c7\:30a2\:30c6\:30ad\:30b9\:30c8\:3092\n" <>
  "LLM \:3092\:4f7f\:3063\:3066\:6587\:7ae0\:54c1\:8cea\:306e\:30d1\:30e9\:30b0\:30e9\:30d5\:306b\:5c55\:958b\:3059\:308b\:3002\n" <>
  "\:5143\:306e\:30a2\:30a4\:30c7\:30a2\:306f\:30bb\:30eb\:306e TaggingRules \:306b\:4fdd\:5b58\:3055\:308c\:308b\:3002\n" <>
  "\:65e2\:306b\:30d1\:30e9\:30b0\:30e9\:30d5\:8868\:793a\:4e2d\:306e\:5834\:5408\:306f\:4fdd\:5b58\:6e08\:307f\:30a2\:30a4\:30c7\:30a2\:304b\:3089\:518d\:5c55\:958b\:3059\:308b\:3002\n" <>
  "Options: Fallback -> False\n" <>
  "\:4f8b: DocExpandIdea[EvaluationNotebook[], 3]";

DocToggleView::usage =
  "DocToggleView[nb, cellIdx] \:306f\:30bb\:30eb\:306e\:30a2\:30a4\:30c7\:30a2\:3068\:30d1\:30e9\:30b0\:30e9\:30d5\:306e\:8868\:793a\:3092\:5207\:308a\:66ff\:3048\:308b\:3002\n" <>
  "\:73fe\:5728\:8868\:793a\:4e2d\:306e\:5185\:5bb9\:ff08\:7de8\:96c6\:6e08\:307f\:3067\:3082\:ff09\:3092\:4fdd\:5b58\:3057\:3066\:304b\:3089\:5207\:308a\:66ff\:3048\:308b\:3002\n" <>
  "\:4f8b: DocToggleView[EvaluationNotebook[], 5]";


ShowDocPalette::usage =
  "ShowDocPalette[] \:306f\:30c9\:30ad\:30e5\:30e1\:30f3\:30c8\:4f5c\:6210\:7528\:30d1\:30ec\:30c3\:30c8\:3092\:8868\:793a\:3059\:308b\:3002";

$DocTranslationLanguage::usage =
  "$DocTranslationLanguage \:306f\:7ffb\:8a33\:5148\:306e\:8a00\:8a9e\:540d\:3002\n" <>
  "\:30c7\:30d5\:30a9\:30eb\:30c8: $Language \:304c\:82f1\:8a9e\:4ee5\:5916\:306a\:3089 \"English\"\:3001\:82f1\:8a9e\:306a\:3089 \"Japanese\"\:3002\n" <>
  "\:30e6\:30fc\:30b6\:30fc\:304c\:4efb\:610f\:306e\:8a00\:8a9e\:540d\:306b\:5909\:66f4\:53ef\:80fd\:3002\n" <>
  "\:4f8b: $DocTranslationLanguage = \"French\"";

Begin["`Private`"];

(* ============================================================
   \:30ed\:30fc\:30ab\:30ea\:30bc\:30fc\:30b7\:30e7\:30f3
   ============================================================ *)
iL[ja_String, en_String] := If[$Language === "Japanese", ja, en];

(* ============================================================
   \:5b9a\:6570: \:8996\:899a\:30b9\:30bf\:30a4\:30eb
   ============================================================ *)

(* \:5c55\:958b\:306e\:8996\:899a\:8868\:73fe: \:5de6\:5074\:67a0\:7dda\:306e\:307f\:5236\:5fa1\:3002
   Background \:3068 CellDingbat \:306f\:6a5f\:5bc6\:30b7\:30b9\:30c6\:30e0 (NBAccess) \:306e\:7ba1\:8f44\:3067\:3042\:308a\:3001
   documentation \:5074\:3067\:306f\:4e00\:5207\:89e6\:3089\:306a\:3044\:3002\:3053\:308c\:306b\:3088\:308a\:6a5f\:5bc6\:80cc\:666f\:8272\:304c\:4fdd\:6301\:3055\:308c\:308b\:3002 *)

(* \:30d1\:30e9\:30b0\:30e9\:30d5\:8868\:793a\:30e2\:30fc\:30c9: \:5de6\:5074\:306b\:7dd1\:306e\:67a0\:7dda *)
$iDocParagraphCellOpts = {
  CellFrame      -> {{3, 0}, {0, 0}},
  CellFrameColor -> RGBColor[0.3, 0.6, 0.5]
};

(* \:30a2\:30a4\:30c7\:30a2\:8868\:793a\:30e2\:30fc\:30c9: \:5de6\:5074\:306b\:7425\:73c0\:8272\:306e\:67a0\:7dda *)
$iDocIdeaCellOpts = {
  CellFrame      -> {{3, 0}, {0, 0}},
  CellFrameColor -> RGBColor[0.8, 0.65, 0.3]
};

(* \:7ffb\:8a33\:8868\:793a\:30e2\:30fc\:30c9: \:5de6\:5074\:306b\:9752\:306e\:67a0\:7dda *)
$iDocTranslationCellOpts = {
  CellFrame      -> {{3, 0}, {0, 0}},
  CellFrameColor -> RGBColor[0.3, 0.45, 0.75]
};

(* \:7ffb\:8a33\:4ed8\:304d\:30bb\:30eb\:ff08\:5143\:30c6\:30ad\:30b9\:30c8\:8868\:793a\:4e2d\:ff09: \:5de6\:5074\:306b\:6c34\:8272\:306e\:67a0\:7dda *)
$iDocTranslatedCellOpts = {
  CellFrame      -> {{3, 0}, {0, 0}},
  CellFrameColor -> RGBColor[0.5, 0.75, 0.9]
};

(* ============================================================
   TaggingRules \:30d1\:30b9\:5b9a\:6570
   ============================================================ *)
$iDocTagRoot = "documentation";
$iDocTagAlternate = {$iDocTagRoot, "alternate"};
$iDocTagMode = {$iDocTagRoot, "mode"};
$iDocTagTranslation = {$iDocTagRoot, "translation"};
$iDocTagTranslationSrc = {$iDocTagRoot, "translationSrc"};
$iDocTagShowTranslation = {$iDocTagRoot, "showTranslation"};

(* ============================================================
   \:30d1\:30ec\:30c3\:30c8\:72b6\:614b
   ============================================================ *)
If[!ValueQ[$docPalette], $docPalette = None];
(* \:76f4\:524d\:306e\:64cd\:4f5c\:5bfe\:8c61\:30bb\:30eb\:8a18\:61b6: {nb, cellIdx}
   \:30bb\:30eb\:9078\:629e\:304c\:89e3\:9664\:3055\:308c\:3066\:3082\:3001\:540c\:3058\:30ce\:30fc\:30c8\:30d6\:30c3\:30af\:4e0a\:306a\:3089\:76f4\:524d\:306e\:30bb\:30eb\:3092\:518d\:5229\:7528\:3059\:308b\:3002
   \:5225\:30bb\:30eb\:306e\:9078\:629e\:3001\:5225\:30ce\:30fc\:30c8\:30d6\:30c3\:30af\:3078\:306e\:5207\:66ff\:3067\:30af\:30ea\:30a2\:3055\:308c\:308b\:3002 *)
$iDocLastTarget = {None, 0};

(* ============================================================
   \:30d1\:30ec\:30c3\:30c8\:7528: \:30ce\:30fc\:30c8\:30d6\:30c3\:30af/\:30bb\:30eb\:89e3\:6c7a (UI \:30e1\:30bf\:30c7\:30fc\:30bf\:306e\:307f\:3001\:5185\:5bb9\:975e\:63a5\:89e6)
   ============================================================ *)

(* \:30d1\:30ec\:30c3\:30c8\:304b\:3089\:547c\:3070\:308c\:3066\:3082\:6b63\:3057\:3044\:30e6\:30fc\:30b6\:30fc\:30ce\:30fc\:30c8\:30d6\:30c3\:30af\:3092\:8fd4\:3059 *)
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

(* \:64cd\:4f5c\:5bfe\:8c61\:30bb\:30eb\:30a4\:30f3\:30c7\:30c3\:30af\:30b9\:30921\:3064\:89e3\:6c7a\:3059\:308b\:3002
   \:30bb\:30eb\:30d6\:30e9\:30b1\:30c3\:30c8\:9078\:629e\:304c\:3042\:308c\:3070\:305d\:308c\:3092\:4f7f\:3044\:8a18\:61b6\:3059\:308b\:3002
   \:9078\:629e\:304c\:306a\:3044\:5834\:5408\:3001\:540c\:3058\:30ce\:30fc\:30c8\:30d6\:30c3\:30af\:4e0a\:306e\:76f4\:524d\:64cd\:4f5c\:30bb\:30eb\:3092\:518d\:5229\:7528\:3059\:308b\:3002
   \:30ce\:30fc\:30c8\:30d6\:30c3\:30af\:304c\:5909\:308f\:3063\:305f\:3089\:8a18\:61b6\:3092\:30af\:30ea\:30a2\:3059\:308b\:3002 *)
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

(* \:64cd\:4f5c\:5bfe\:8c61\:30bb\:30eb\:30a4\:30f3\:30c7\:30c3\:30af\:30b9\:3092\:8907\:6570\:89e3\:6c7a\:3059\:308b\:ff08\:30bb\:30eb\:30b0\:30eb\:30fc\:30d7\:9078\:629e\:5bfe\:5fdc\:ff09\:3002
   \:8907\:6570\:9078\:629e: \:305d\:306e\:307e\:307e\:5168\:30a4\:30f3\:30c7\:30c3\:30af\:30b9\:3092\:8fd4\:3059\:3002
   \:5358\:4e00\:9078\:629e or \:30ab\:30fc\:30bd\:30eb\:4f4d\:7f6e: 1\:8981\:7d20\:30ea\:30b9\:30c8\:3068\:3057\:3066\:8fd4\:3059\:3002
   \:9078\:629e\:306a\:3057: \:76f4\:524d\:64cd\:4f5c\:30bb\:30eb\:3092\:518d\:5229\:7528\:3002 *)
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
   \:8a00\:8a9e\:30d8\:30eb\:30d1\:30fc
   ============================================================ *)

(* $Language \:306b\:57fa\:3065\:304f\:51fa\:529b\:8a00\:8a9e\:540d\:3002\:5c55\:958b\:30d7\:30ed\:30f3\:30d7\:30c8\:3067\:4f7f\:7528\:3002 *)
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

(* \:7ffb\:8a33\:5148\:8a00\:8a9e\:306e\:521d\:671f\:5316: $Language \:304c\:82f1\:8a9e\:4ee5\:5916\:306a\:3089\:82f1\:8a9e\:306b\:3001\:82f1\:8a9e\:306a\:3089\:65e5\:672c\:8a9e\:306b *)
If[!StringQ[$DocTranslationLanguage],
  $DocTranslationLanguage = If[StringQ[$Language] && $Language === "English",
    "Japanese", "English"]];

(* \:7ffb\:8a33\:5148\:8a00\:8a9e\:3092\:8fd4\:3059\:ff08\:5927\:57df\:5909\:6570\:7d4c\:7531\:ff09 *)
iDocTranslationTarget[] := $DocTranslationLanguage;

(* \:30c6\:30ad\:30b9\:30c8\:306e\:8a00\:8a9e\:3092\:30d2\:30e5\:30fc\:30ea\:30b9\:30c6\:30a3\:30c3\:30af\:3067\:691c\:51fa\:3059\:308b\:3002
   \:3072\:3089\:304c\:306a\:30fb\:30ab\:30bf\:30ab\:30ca \[RightArrow] "Japanese"
   \:30cf\:30f3\:30b0\:30eb \[RightArrow] "Korean"
   CJK\:7d71\:5408\:6f22\:5b57\:306e\:307f\:ff08\:304b\:306a\:7121\:3057\:ff09\[RightArrow] "Chinese"
   \:305d\:308c\:4ee5\:5916 \[RightArrow] "English" \:ff08\:30e9\:30c6\:30f3\:6587\:5b57\:7cfb\:3092\:4e00\:62ec\:ff09 *)
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

(* $Language \:3092\:691c\:51fa\:8a00\:8a9e\:3068\:6bd4\:8f03\:53ef\:80fd\:306a\:5f62\:5f0f\:306b\:5909\:63db *)
iDocLangCategory[lang_String] := Switch[lang,
  "Japanese", "Japanese",
  "English", "English",
  "Korean", "Korean",
  "ChineseSimplified" | "ChineseTraditional", "Chinese",
  "French" | "German" | "Spanish" | "Italian" | "Portuguese", "European",
  _, "Other"
];

(* \:666e\:901a\:306e\:30bb\:30eb\:7528: \:30c6\:30ad\:30b9\:30c8\:8a00\:8a9e\:3092\:691c\:51fa\:3057\:3066\:7ffb\:8a33\:5148\:3092\:6c7a\:5b9a\:3059\:308b\:3002
   \:30c6\:30ad\:30b9\:30c8\:306e\:8a00\:8a9e\:304c $Language \:3068\:7570\:306a\:308b \[RightArrow] $Language \:306b\:7ffb\:8a33
   \:30c6\:30ad\:30b9\:30c8\:306e\:8a00\:8a9e\:304c $Language \:3068\:540c\:3058 \[RightArrow] iDocTranslationTarget[] *)
iDocTranslationTargetForText[text_String] := Module[{detected, myLang},
  detected = iDocDetectTextLanguage[text];
  myLang = iDocLangCategory[If[StringQ[$Language], $Language, "Japanese"]];
  If[detected =!= myLang,
    (* \:30c6\:30ad\:30b9\:30c8\:306e\:8a00\:8a9e\:304c $Language \:3068\:7570\:306a\:308b \[RightArrow] $Language \:306b\:7ffb\:8a33 *)
    iDocOutputLanguage[],
    (* \:540c\:3058 \[RightArrow] \:5225\:306e\:8a00\:8a9e\:306b\:7ffb\:8a33 *)
    iDocTranslationTarget[]]
];

(* ============================================================
   LLM \:30d7\:30ed\:30f3\:30d7\:30c8\:69cb\:7bc9\:95a2\:6570 (NBCellTransformWithLLM \:306e promptFn \:3068\:3057\:3066\:4f7f\:3046)
   ============================================================ *)

(* \:30ce\:30fc\:30c8\:30d6\:30c3\:30af\:306e\:30b3\:30f3\:30c6\:30ad\:30b9\:30c8\:60c5\:5831\:3092\:53ce\:96c6\:3059\:308b\:3002
   \:5bfe\:8c61\:30bb\:30eb\:306e\:5468\:8fba\:30bb\:30eb\:30c6\:30ad\:30b9\:30c8\:3068\:30a2\:30bf\:30c3\:30c1\:30e1\:30f3\:30c8\:60c5\:5831\:3092\:542b\:3080\:3002
   LLM \:304c\:30a2\:30a4\:30c7\:30a2\:4e2d\:306e\:7565\:8a9e\:30fb\:56fa\:6709\:540d\:8a5e\:3092\:6b63\:3057\:304f\:89e3\:91c8\:3059\:308b\:305f\:3081\:306b\:4f7f\:3046\:3002 *)
iDocCollectContext[nb_NotebookObject, cellIdx_Integer] :=
  Module[{nCells, texts = {}, mode, text, style, atts, attNames, maxCells = 30},
    NBAccess`NBInvalidateCellsCache[nb];
    nCells = NBAccess`NBCellCount[nb];
    (* \:5468\:8fba\:30bb\:30eb\:306e\:8981\:7d04\:3092\:53ce\:96c6\:ff08\:81ea\:5206\:81ea\:8eab\:3092\:9664\:304f\:3001\:6700\:5927 maxCells \:30bb\:30eb\:ff09 *)
    Do[
      If[i =!= cellIdx,
        style = NBAccess`NBCellStyle[nb, i];
        If[MemberQ[{"Text", "Section", "Subsection", "Subsubsection", "Title",
                     "Subtitle", "Chapter"}, style],
          text = Quiet[NBAccess`NBCellGetText[nb, i]];
          If[StringQ[text] && StringLength[text] > 0,
            (* \:9577\:3059\:304e\:308b\:30bb\:30eb\:306f\:5148\:982d200\:6587\:5b57\:306b\:5207\:308a\:8a70\:3081 *)
            text = If[StringLength[text] > 200,
              StringTake[text, 200] <> "...", text];
            mode = NBAccess`NBCellGetTaggingRule[nb, i, $iDocTagMode];
            AppendTo[texts,
              "[Cell " <> ToString[i] <>
              If[StringQ[mode], " (" <> mode <> ")", ""] <>
              "] " <> text]]]],
    {i, Max[1, cellIdx - maxCells], Min[nCells, cellIdx + maxCells]}];
    (* \:30a2\:30bf\:30c3\:30c1\:30e1\:30f3\:30c8\:60c5\:5831: NBAccess \:516c\:958b API \:7d4c\:7531 *)
    atts = Quiet[NBAccess`NBHistoryGetAttachments[nb, "history"]];
    attNames = If[ListQ[atts] && Length[atts] > 0,
      "Attached files: " <> StringRiffle[FileNameTake /@ atts, ", "],
      ""];
    (* \:30b3\:30f3\:30c6\:30ad\:30b9\:30c8\:6587\:5b57\:5217\:3092\:69cb\:7bc9 *)
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
    "\:3042\:306a\:305f\:306f\:719f\:7df4\:3057\:305f\:30e9\:30a4\:30bf\:30fc\:3067\:3059\:3002\:4ee5\:4e0b\:306e\:77ed\:3044\:30a2\:30a4\:30c7\:30a2\:3084\:30d5\:30ec\:30fc\:30ba\:3092\:3001" <>
    "\:3088\:304f\:7df4\:3089\:308c\:305f\:6bb5\:843d\:306b\:767a\:5c55\:3055\:305b\:3066\:304f\:3060\:3055\:3044\:3002\n" <>
    "\:30eb\:30fc\:30eb:\n" <>
    "- \:5143\:306e\:610f\:5473\:3068\:610f\:56f3\:3092\:5fe0\:5b9f\:306b\:4fdd\:3064\n" <>
    "- \:6df1\:307f\:3001\:660e\:78ba\:3055\:3001\:30d7\:30ed\:30d5\:30a7\:30c3\:30b7\:30e7\:30ca\:30eb\:306a\:6587\:7ae0\:54c1\:8cea\:3092\:52a0\:3048\:308b\n" <>
    "- \:51fa\:529b\:8a00\:8a9e: " <> iDocOutputLanguage[] <> "\n" <>
    "- \:6bb5\:843d\:306e\:30c6\:30ad\:30b9\:30c8\:306e\:307f\:3092\:51fa\:529b\:3057\:3001\:305d\:308c\:4ee5\:5916\:ff08\:524d\:7f6e\:304d\:3084\:8aac\:660e\:ff09\:306f\:4e00\:5207\:51fa\:529b\:3057\:306a\:3044\n" <>
    "- \:30de\:30fc\:30af\:30c0\:30a6\:30f3\:8a18\:6cd5\:306f\:4f7f\:308f\:306a\:3044\n" <>
    "- \:30c9\:30ad\:30e5\:30e1\:30f3\:30c8\:30b3\:30f3\:30c6\:30ad\:30b9\:30c8\:304c\:3042\:308b\:5834\:5408\:306f\:3001\:7565\:8a9e\:3084\:56fa\:6709\:540d\:8a5e\:306e\:610f\:5473\:3092\:6587\:8108\:304b\:3089\:5224\:65ad\:3059\:308b\n" <>
    "- \:30ea\:30af\:30a8\:30b9\:30c8\:3092\:5b9f\:884c\:3067\:304d\:306a\:3044\:5834\:5408\:ff08\:30d5\:30a1\:30a4\:30eb\:672a\:691c\:51fa\:30fb\:60c5\:5831\:4e0d\:8db3\:7b49\:ff09\:306f\:3001\:6bb5\:843d\:3067\:306f\:306a\:304f [ERROR]: \:306b\:7d9a\:3051\:3066\:7406\:7531\:3092\:51fa\:529b\:3059\:308b\n\n" <>
    "\:30a2\:30a4\:30c7\:30a2:\n" <> ideaText,
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

(* \:518d\:5c55\:958b\:7528\:30d7\:30ed\:30f3\:30d7\:30c8: \:4fee\:6b63\:3055\:308c\:305f\:30a2\:30a4\:30c7\:30a2\:3068\:4ee5\:524d\:306e\:30d1\:30e9\:30b0\:30e9\:30d5\:306e\:4e21\:65b9\:3092\:6e21\:3059 *)
iDocReExpandPromptFn[ideaText_String, prevParagraph_String, context_String:""] :=
  context <>
  iL[
    "\:3042\:306a\:305f\:306f\:719f\:7df4\:3057\:305f\:30e9\:30a4\:30bf\:30fc\:3067\:3059\:3002\:4ee5\:4e0b\:306e\:300c\:4fee\:6b63\:3055\:308c\:305f\:30a2\:30a4\:30c7\:30a2\:300d\:306b\:57fa\:3065\:3044\:3066\:3001" <>
    "\:300c\:4ee5\:524d\:306e\:6bb5\:843d\:300d\:3092\:66f8\:304d\:76f4\:3057\:3066\:304f\:3060\:3055\:3044\:3002\n" <>
    "\:30eb\:30fc\:30eb:\n" <>
    "- \:4ee5\:524d\:306e\:6bb5\:843d\:306e\:6587\:4f53\:30fb\:69cb\:6210\:30fb\:30e6\:30fc\:30b6\:30fc\:306e\:4fee\:6b63\:3092\:53ef\:80fd\:306a\:9650\:308a\:8e0f\:8972\:3059\:308b\n" <>
    "- \:4fee\:6b63\:3055\:308c\:305f\:30a2\:30a4\:30c7\:30a2\:306e\:5185\:5bb9\:5909\:66f4\:306b\:5f93\:3063\:3066\:5fc5\:8981\:7b87\:6240\:3092\:66f8\:304d\:63db\:3048\:308b\n" <>
    "- \:51fa\:529b\:8a00\:8a9e: " <> iDocOutputLanguage[] <> "\n" <>
    "- \:6bb5\:843d\:306e\:30c6\:30ad\:30b9\:30c8\:306e\:307f\:3092\:51fa\:529b\:3057\:3001\:305d\:308c\:4ee5\:5916\:ff08\:524d\:7f6e\:304d\:3084\:8aac\:660e\:ff09\:306f\:4e00\:5207\:51fa\:529b\:3057\:306a\:3044\n" <>
    "- \:30de\:30fc\:30af\:30c0\:30a6\:30f3\:8a18\:6cd5\:306f\:4f7f\:308f\:306a\:3044\n" <>
    "- \:30c9\:30ad\:30e5\:30e1\:30f3\:30c8\:30b3\:30f3\:30c6\:30ad\:30b9\:30c8\:304c\:3042\:308b\:5834\:5408\:306f\:3001\:7565\:8a9e\:3084\:56fa\:6709\:540d\:8a5e\:306e\:610f\:5473\:3092\:6587\:8108\:304b\:3089\:5224\:65ad\:3059\:308b\n" <>
    "- \:30ea\:30af\:30a8\:30b9\:30c8\:3092\:5b9f\:884c\:3067\:304d\:306a\:3044\:5834\:5408\:ff08\:30d5\:30a1\:30a4\:30eb\:672a\:691c\:51fa\:30fb\:60c5\:5831\:4e0d\:8db3\:7b49\:ff09\:306f\:3001\:6bb5\:843d\:3067\:306f\:306a\:304f [ERROR]: \:306b\:7d9a\:3051\:3066\:7406\:7531\:3092\:51fa\:529b\:3059\:308b\n\n" <>
    "\:4fee\:6b63\:3055\:308c\:305f\:30a2\:30a4\:30c7\:30a2:\n" <> ideaText <>
    "\n\n\:4ee5\:524d\:306e\:6bb5\:843d:\n" <> prevParagraph,
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
   \:30b3\:30a2\:95a2\:6570: \:30a2\:30a4\:30c7\:30a2\:5c55\:958b
   \:5168\:30bb\:30eb\:5185\:5bb9\:30a2\:30af\:30bb\:30b9\:306f NBAccess \:7d4c\:7531\:3002LLM \:306f NBCellTransformWithLLM \:7d4c\:7531\:3002

   \:52d5\:4f5c\:30e2\:30fc\:30c9:
   - mode \:672a\:8a2d\:5b9a\:ff08\:521d\:56de\:ff09: \:30a2\:30a4\:30c7\:30a2 \[RightArrow] \:30d1\:30e9\:30b0\:30e9\:30d5\:306b\:5c55\:958b
   - mode === "idea"\:ff08\:30d7\:30ed\:30f3\:30d7\:30c8\:8868\:793a\:4e2d\:ff09:
     \:4fdd\:5b58\:6e08\:307f\:30d1\:30e9\:30b0\:30e9\:30d5\:304c\:3042\:308c\:3070\:518d\:5c55\:958b\:ff08\:4fee\:6b63\:30a2\:30a4\:30c7\:30a2 + \:65e7\:30d1\:30e9\:30b0\:30e9\:30d5\:3092\:6e21\:3059\:ff09
     \:306a\:3051\:308c\:3070\:521d\:56de\:5c55\:958b\:3068\:540c\:3058
   - mode === "paragraph"\:ff08\:30d1\:30e9\:30b0\:30e9\:30d5\:8868\:793a\:4e2d\:ff09: \:5c55\:958b\:3092\:7981\:6b62
   ============================================================ *)

Options[DocExpandIdea] = {Fallback -> False};

DocExpandIdea[nb_NotebookObject, cellIdx_Integer, opts:OptionsPattern[]] :=
  Module[{mode, prevParagraph, useFallback, promptFn, context},
    useFallback = TrueQ[OptionValue[Fallback]];

    (* \:73fe\:5728\:306e\:30e2\:30fc\:30c9\:78ba\:8a8d (NBAccess \:7d4c\:7531) *)
    mode = NBAccess`NBCellGetTaggingRule[nb, cellIdx, $iDocTagMode];

    (* \:30d1\:30e9\:30b0\:30e9\:30d5\:8868\:793a\:4e2d \[RightArrow] \:5c55\:958b\:7981\:6b62 *)
    If[mode === "paragraph",
      MessageDialog[iL[
        "\:30d1\:30e9\:30b0\:30e9\:30d5\:30e2\:30fc\:30c9\:3067\:306f\:5c55\:958b\:3067\:304d\:307e\:305b\:3093\:3002\n" <>
        "\:5148\:306b\:300c\:5207\:66ff\:300d\:3067\:30d7\:30ed\:30f3\:30d7\:30c8\:30e2\:30fc\:30c9\:306b\:623b\:3057\:3066\:304b\:3089\:3001\:30d7\:30ed\:30f3\:30d7\:30c8\:3092\:4fee\:6b63\:3057\:3066\:518d\:5c55\:958b\:3057\:3066\:304f\:3060\:3055\:3044\:3002",
        "Cannot expand in paragraph mode.\n" <>
        "Switch to idea mode first, edit the prompt, then expand again."]];
      Return[$Failed]];

    (* \:30ce\:30fc\:30c8\:30d6\:30c3\:30af\:30b3\:30f3\:30c6\:30ad\:30b9\:30c8\:53ce\:96c6: \:5468\:8fba\:30bb\:30eb + \:30a2\:30bf\:30c3\:30c1\:30e1\:30f3\:30c8\:60c5\:5831 *)
    context = iDocCollectContext[nb, cellIdx];

    (* \:30d7\:30ed\:30f3\:30d7\:30c8\:69cb\:7bc9\:95a2\:6570\:306e\:9078\:629e *)
    prevParagraph = If[mode === "idea",
      NBAccess`NBCellGetTaggingRule[nb, cellIdx, $iDocTagAlternate],
      None];
    promptFn = If[StringQ[prevParagraph] && StringTrim[prevParagraph] =!= "",
      With[{prev = prevParagraph, ctx = context},
        Function[t, iDocReExpandPromptFn[t, prev, ctx]]],
      With[{ctx = context},
        Function[t, iDocExpandPromptFn[t, ctx]]]
    ];

    (* \:975e\:540c\:671f LLM \:5909\:63db: \:30ab\:30fc\:30cd\:30eb\:3092\:30d6\:30ed\:30c3\:30af\:3057\:306a\:3044\:3002 *)
    With[{nb2 = nb},
      NBAccess`NBCellTransformWithLLM[nb, cellIdx,
        promptFn,
        (* completionFn: LLM \:5fdc\:7b54\:5f8c\:306b\:5b9f\:884c\:3055\:308c\:308b\:30b3\:30fc\:30eb\:30d0\:30c3\:30af *)
        Function[result,
          If[AssociationQ[result],
            Module[{ci = result["CellIdx"]},
              NBAccess`NBCellSetTaggingRule[nb2, ci, $iDocTagAlternate,
                result["OriginalText"]];
              NBAccess`NBCellSetTaggingRule[nb2, ci, $iDocTagMode, "paragraph"];
              NBAccess`NBCellSetOptions[nb2, ci,
                Sequence @@ $iDocParagraphCellOpts]],
            (* \:30a8\:30e9\:30fc *)
            MessageDialog[iL[
              "\:30a8\:30e9\:30fc: LLM \:5fdc\:7b54\:3092\:53d6\:5f97\:3067\:304d\:307e\:305b\:3093\:3067\:3057\:305f\:3002",
              "Error: Could not get LLM response."]]]],
        Fallback -> useFallback]
    ];
  ];

(* ============================================================
   \:30b3\:30a2\:95a2\:6570: \:30c8\:30b0\:30eb\:8868\:793a
   ============================================================ *)

DocToggleView[nb_NotebookObject, cellIdx_Integer] :=
  Module[{currentText, mode, alternate, newMode, showTrans, transSrc,
          storedTranslation},
    NBAccess`NBInvalidateCellsCache[nb];
    mode = NBAccess`NBCellGetTaggingRule[nb, cellIdx, $iDocTagMode];
    showTrans = NBAccess`NBCellGetTaggingRule[nb, cellIdx, $iDocTagShowTranslation];

    (* ========================================================
       \:7ffb\:8a33\:4ed8\:304d\:30bb\:30eb (mode="translated"): \:5143\:30c6\:30ad\:30b9\:30c8 \[LeftRightArrow] \:7ffb\:8a33
       ======================================================== *)
    If[mode === "translated",
      If[TrueQ[showTrans],
        (* \:7ffb\:8a33\:8868\:793a\:4e2d \[RightArrow] \:5143\:30c6\:30ad\:30b9\:30c8\:306b\:623b\:3059\:ff08\:6c34\:8272\:67a0\:ff09 *)
        transSrc = NBAccess`NBCellGetTaggingRule[nb, cellIdx, $iDocTagTranslationSrc];
        If[StringQ[transSrc],
          NBAccess`NBCellSetTaggingRule[nb, cellIdx,
            $iDocTagTranslation, NBAccess`NBCellGetText[nb, cellIdx]];
          NBAccess`NBCellSetTaggingRule[nb, cellIdx, $iDocTagShowTranslation, False];
          NBAccess`NBCellSetOptions[nb, cellIdx,
            Sequence @@ $iDocTranslatedCellOpts];
          NBAccess`NBInvalidateCellsCache[nb];
          NBAccess`NBCellWriteText[nb, cellIdx, transSrc];],
        (* \:5143\:30c6\:30ad\:30b9\:30c8\:8868\:793a\:4e2d \[RightArrow] \:7ffb\:8a33\:3092\:8868\:793a\:ff08\:9752\:67a0\:ff09 *)
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
       \:7ffb\:8a33\:8868\:793a\:4e2d (paragraph \:30e2\:30fc\:30c9): \:7ffb\:8a33 \[RightArrow] \:30a2\:30a4\:30c7\:30a2\:306b\:623b\:3059
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
      (* fallback: \:7ffb\:8a33\:5143\:3092\:5fa9\:5143 *)
      If[StringQ[transSrc],
        NBAccess`NBCellSetOptions[nb, cellIdx,
          CellFrame -> Inherited, CellFrameColor -> Inherited];
        NBAccess`NBInvalidateCellsCache[nb];
        NBAccess`NBCellWriteText[nb, cellIdx, transSrc];];
      Return[]];

    (* ========================================================
       \:901a\:5e38\:30d5\:30ed\:30fc: idea \[LeftRightArrow] paragraph (\[RightArrow] \:7ffb\:8a33\:304c\:3042\:308c\:3070\:7ffb\:8a33)
       ======================================================== *)
    currentText = NBAccess`NBCellGetText[nb, cellIdx];
    alternate = NBAccess`NBCellGetTaggingRule[nb, cellIdx, $iDocTagAlternate];

    If[!StringQ[alternate],
      MessageDialog[iL[
        "\:3053\:306e\:30bb\:30eb\:306b\:306f\:30c8\:30b0\:30eb\:53ef\:80fd\:306a\:30b3\:30f3\:30c6\:30f3\:30c4\:304c\:3042\:308a\:307e\:305b\:3093\:3002\n\:5148\:306b\:300c\:5c55\:958b\:300d\:3092\:5b9f\:884c\:3057\:3066\:304f\:3060\:3055\:3044\:3002",
        "No toggleable content in this cell.\nRun 'Expand' first."]];
      Return[$Failed]];

    (* \:30d1\:30e9\:30b0\:30e9\:30d5\:8868\:793a\:4e2d \[RightArrow] \:7ffb\:8a33\:304c\:3042\:308c\:3070\:7ffb\:8a33\:3078\:3001\:306a\:3051\:308c\:3070\:30a2\:30a4\:30c7\:30a2\:3078 *)
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

    (* idea \[LeftRightArrow] paragraph \:306e2\:6bb5\:968e\:30c8\:30b0\:30eb *)
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
   \:30b3\:30a2\:95a2\:6570: \:7ffb\:8a33
   $Language \:304c\:82f1\:8a9e\:4ee5\:5916\[RightArrow]\:82f1\:8a9e\:306b\:3001\:82f1\:8a9e\[RightArrow]\:65e5\:672c\:8a9e\:306b\:7ffb\:8a33\:3002
   \:7ffb\:8a33\:7d50\:679c\:306f TaggingRules \:306b\:4fdd\:6301\:3057\:3001\:5207\:66ff\:53ef\:80fd\:3002
   
   \:7ffb\:8a33\:53ef\:80fd: \:30d1\:30e9\:30b0\:30e9\:30d5\:30e2\:30fc\:30c9\:3001\:666e\:901a\:306e\:30bb\:30eb\:ff08\:30e2\:30fc\:30c9\:672a\:8a2d\:5b9a\:ff09
   \:7ffb\:8a33\:4e0d\:53ef: \:30d7\:30ed\:30f3\:30d7\:30c8\:ff08\:30a2\:30a4\:30c7\:30a2\:ff09\:30e2\:30fc\:30c9\:3001\:7ffb\:8a33\:8868\:793a\:4e2d
   
   \:518d\:7ffb\:8a33\:6642\:306f\:3001\:30d7\:30ed\:30f3\:30d7\:30c8\:ff08\:3042\:308c\:3070\:ff09\:3092\:53c2\:7167\:3057\:3064\:3064\:3001
   \:30e6\:30fc\:30b6\:30fc\:304c\:4fee\:6b63\:3057\:305f\:65e2\:5b58\:7ffb\:8a33\:3092\:8e0f\:8972\:3057\:3066\:66f4\:65b0\:3059\:308b\:3002
   ============================================================ *)

(* \:521d\:56de\:7ffb\:8a33\:30d7\:30ed\:30f3\:30d7\:30c8: \:666e\:901a\:306e\:30bb\:30eb\:7528\:ff08\:8a00\:8a9e\:81ea\:52d5\:691c\:51fa\:ff09
   \:30c6\:30ad\:30b9\:30c8\:304c primaryLang \:306a\:3089 alternateLang \:306b\:3001\:305d\:308c\:4ee5\:5916\:306a\:3089 primaryLang \:306b\:7ffb\:8a33\:3059\:308b *)
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

(* \:30d1\:30e9\:30b0\:30e9\:30d5\:7528\:7ffb\:8a33\:30d7\:30ed\:30f3\:30d7\:30c8: \:56fa\:5b9a\:30bf\:30fc\:30b2\:30c3\:30c8\:8a00\:8a9e *)
iDocTranslatePromptFn[text_String, targetLang_String] :=
  "Translate the following text into " <> targetLang <> ".\n" <>
  "Rules:\n" <>
  "- Produce a natural, fluent translation\n" <>
  "- Preserve the original structure and meaning faithfully\n" <>
  "- Output ONLY the translated text, nothing else\n" <>
  "- Do not use markdown formatting\n" <>
  "- If you cannot fulfill the request, output ONLY: [ERROR]: followed by the reason\n\n" <>
  "Text to translate:\n" <> text;

(* \:521d\:56de\:7ffb\:8a33\:30d7\:30ed\:30f3\:30d7\:30c8\:ff08\:30d7\:30ed\:30f3\:30d7\:30c8\:53c2\:7167\:4ed8\:304d\:ff09 *)
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

(* \:518d\:7ffb\:8a33\:30d7\:30ed\:30f3\:30d7\:30c8: \:65e2\:5b58\:7ffb\:8a33\:306e\:30e6\:30fc\:30b6\:30fc\:4fee\:6b63\:3092\:8e0f\:8972\:3057\:3064\:3064\:66f4\:65b0 *)
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
    NBAccess`NBInvalidateCellsCache[nb];

    mode = NBAccess`NBCellGetTaggingRule[nb, cellIdx, $iDocTagMode];
    showTrans = NBAccess`NBCellGetTaggingRule[nb, cellIdx, $iDocTagShowTranslation];

    (* \:7ffb\:8a33\:4e0d\:53ef: \:30d7\:30ed\:30f3\:30d7\:30c8\:ff08\:30a2\:30a4\:30c7\:30a2\:ff09\:30e2\:30fc\:30c9 *)
    If[mode === "idea",
      MessageDialog[iL[
        "\:30d7\:30ed\:30f3\:30d7\:30c8\:30e2\:30fc\:30c9\:3067\:306f\:7ffb\:8a33\:3067\:304d\:307e\:305b\:3093\:3002\n" <>
        "\:30d1\:30e9\:30b0\:30e9\:30d5\:306b\:5c55\:958b\:3057\:3066\:304b\:3089\:7ffb\:8a33\:3057\:3066\:304f\:3060\:3055\:3044\:3002",
        "Cannot translate in idea/prompt mode.\n" <>
        "Expand to paragraph first, then translate."]];
      Return[$Failed]];

    (* \:7ffb\:8a33\:4e0d\:53ef: \:7ffb\:8a33\:8868\:793a\:4e2d *)
    If[TrueQ[showTrans],
      MessageDialog[iL[
        "\:7ffb\:8a33\:8868\:793a\:4e2d\:3067\:3059\:3002\n" <>
        "\:300c\:5207\:66ff\:300d\:3067\:5143\:30c6\:30ad\:30b9\:30c8\:306b\:623b\:3057\:3066\:304b\:3089\:518d\:7ffb\:8a33\:3057\:3066\:304f\:3060\:3055\:3044\:3002",
        "Currently showing translation.\n" <>
        "Toggle back to original text before re-translating."]];
      Return[$Failed]];

    currentText = NBAccess`NBCellGetText[nb, cellIdx];
    If[!StringQ[currentText] || StringTrim[currentText] === "",
      Return[$Failed]];

    storedTranslation = NBAccess`NBCellGetTaggingRule[nb, cellIdx, $iDocTagTranslation];
    storedSrc = NBAccess`NBCellGetTaggingRule[nb, cellIdx, $iDocTagTranslationSrc];
    targetLang = iDocTranslationTarget[];

    (* \:30d7\:30ed\:30f3\:30d7\:30c8\:ff08\:30a2\:30a4\:30c7\:30a2\:ff09\:30c6\:30ad\:30b9\:30c8\:3092\:53c2\:7167\:7528\:306b\:53d6\:5f97 *)
    ideaText = If[mode === "paragraph",
      NBAccess`NBCellGetTaggingRule[nb, cellIdx, $iDocTagAlternate],
      None];
    If[!StringQ[ideaText], ideaText = ""];

    (* \:4fdd\:5b58\:6e08\:307f\:7ffb\:8a33\:304c\:3042\:308a\:30bd\:30fc\:30b9\:304c\:4e00\:81f4 \[RightArrow] \:5373\:8868\:793a\:ff08LLM\:4e0d\:8981\:ff09 *)
    If[StringQ[storedTranslation] && StringTrim[storedTranslation] =!= "" &&
       StringQ[storedSrc] && storedSrc === currentText,
      (* \:666e\:901a\:30bb\:30eb\:306a\:3089\:7ffb\:8a33\:4ed8\:304d\:30e2\:30fc\:30c9\:3092\:8a2d\:5b9a *)
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

    (* \:30d7\:30ed\:30f3\:30d7\:30c8\:69cb\:7bc9: \:65e2\:5b58\:7ffb\:8a33\:306e\:6709\:7121\:3067\:5206\:5c90 *)
    promptFn = Which[
      (* \:518d\:7ffb\:8a33: \:30bd\:30fc\:30b9\:304c\:5909\:308f\:3063\:305f + \:65e2\:5b58\:7ffb\:8a33\:3042\:308a \[RightArrow] \:30e6\:30fc\:30b6\:30fc\:4fee\:6b63\:3092\:8e0f\:8972 *)
      StringQ[storedTranslation] && StringTrim[storedTranslation] =!= "",
        With[{prev = storedTranslation, idea = ideaText, tl = targetLang},
          Function[t, iDocReTranslatePromptFn[t, tl, prev, idea]]],
      (* \:521d\:56de\:7ffb\:8a33: \:30d7\:30ed\:30f3\:30d7\:30c8\:53c2\:7167\:4ed8\:304d\:ff08\:30d1\:30e9\:30b0\:30e9\:30d5\:30e2\:30fc\:30c9\:306e\:5834\:5408\:ff09 *)
      ideaText =!= "",
        With[{idea = ideaText, tl = targetLang},
          Function[t, iDocTranslateWithContextPromptFn[t, tl, idea]]],
      (* \:521d\:56de\:7ffb\:8a33: \:666e\:901a\:306e\:30bb\:30eb \[RightArrow] \:8a00\:8a9e\:81ea\:52d5\:691c\:51fa *)
      True,
        With[{pl = iDocOutputLanguage[], al = iDocTranslationTarget[]},
          Function[t, iDocTranslateAutoPromptFn[t, pl, al]]]
    ];

    (* \:975e\:540c\:671f\:7ffb\:8a33 *)
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
   \:30b3\:30a2\:95a2\:6570: \:540c\:671f (Sync)
   \:30d7\:30ed\:30f3\:30d7\:30c8\:30fb\:30d1\:30e9\:30b0\:30e9\:30d5\:30fb\:7ffb\:8a33\:306e\:3046\:3061\:3001\:73fe\:5728\:8868\:793a\:4e2d\:306e\:30c6\:30ad\:30b9\:30c8\:3092\:57fa\:6e96\:3068\:3057\:3066
   \:4ed6\:306e\:30b3\:30f3\:30dd\:30fc\:30cd\:30f3\:30c8\:3092 LLM \:3067\:66f4\:65b0\:3059\:308b\:3002\:30bb\:30eb\:8868\:793a\:306f\:5909\:66f4\:3057\:306a\:3044\:3002

   - \:30d7\:30ed\:30f3\:30d7\:30c8\:8868\:793a\:4e2d (mode="idea"):
     \:30d7\:30ed\:30f3\:30d7\:30c8\:304b\:3089 \[RightArrow] \:30d1\:30e9\:30b0\:30e9\:30d5\:3092\:518d\:751f\:6210\:3002\:7ffb\:8a33\:304c\:3042\:308c\:3070\:9023\:9396\:3067\:518d\:7ffb\:8a33\:3002
   - \:30d1\:30e9\:30b0\:30e9\:30d5\:8868\:793a\:4e2d (mode="paragraph"):
     \:30d1\:30e9\:30b0\:30e9\:30d5\:304b\:3089 \[RightArrow] \:7ffb\:8a33\:3092\:518d\:751f\:6210\:3002
   - \:7ffb\:8a33\:8868\:793a\:4e2d (showTranslation=True):
     \:7ffb\:8a33\:304b\:3089 \[RightArrow] \:30d1\:30e9\:30b0\:30e9\:30d5\:3092\:9006\:66f4\:65b0\:3002
   ============================================================ *)

(* \:7ffb\:8a33\[RightArrow]\:30d1\:30e9\:30b0\:30e9\:30d5\:9006\:540c\:671f\:30d7\:30ed\:30f3\:30d7\:30c8 *)
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
  "\n\nEdited translation (different language \[LongDash] do NOT output in this language):\n" <> editedTranslation;

(* \:30bf\:30b0\:304b\:3089\:30bb\:30eb\:30a4\:30f3\:30c7\:30c3\:30af\:30b9\:3092\:518d\:691c\:7d22\:3059\:308b\:3002
   Job \:306e\:9032\:6357\:30bb\:30eb\:633f\:5165\:3067\:30a4\:30f3\:30c7\:30c3\:30af\:30b9\:304c\:305a\:308c\:305f\:5834\:5408\:306b\:4f7f\:7528\:3059\:308b\:3002 *)
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
    NBAccess`NBInvalidateCellsCache[nb];
    mode = NBAccess`NBCellGetTaggingRule[nb, cellIdx, $iDocTagMode];
    showTrans = NBAccess`NBCellGetTaggingRule[nb, cellIdx, $iDocTagShowTranslation];
    currentText = NBAccess`NBCellGetText[nb, cellIdx];
    If[!StringQ[currentText] || StringTrim[currentText] === "",
      Return[$Failed]];

    targetLang = iDocTranslationTarget[];
    context = iDocCollectContext[nb, cellIdx];

    (* \:30bb\:30eb\:306b\:30bf\:30b0\:3092\:4ed8\:4e0e: Job \:306e\:9032\:6357\:30bb\:30eb\:633f\:5165\:3067\:30a4\:30f3\:30c7\:30c3\:30af\:30b9\:304c\:305a\:308c\:3066\:3082\:518d\:767a\:898b\:53ef\:80fd\:306b\:3059\:308b *)
    syncTag = "doc-sync-" <> ToString[UnixTime[]] <> "-" <> ToString[RandomInteger[99999]];
    NBAccess`NBCellSetTaggingRule[nb, cellIdx, {$iDocTagRoot, "syncTag"}, syncTag];

    Which[
      (* === Case 1: \:30d7\:30ed\:30f3\:30d7\:30c8\:8868\:793a\:4e2d \[RightArrow] \:30d1\:30e9\:30b0\:30e9\:30d5\:518d\:751f\:6210 (+\:7ffb\:8a33\:9023\:9396) === *)
      mode === "idea",
        ideaText = currentText;
        paragraph = NBAccess`NBCellGetTaggingRule[nb, cellIdx, $iDocTagAlternate];
        translation = NBAccess`NBCellGetTaggingRule[nb, cellIdx, $iDocTagTranslation];
        prompt = If[StringQ[paragraph] && StringTrim[paragraph] =!= "",
          iDocReExpandPromptFn[ideaText, paragraph, context],
          iDocExpandPromptFn[ideaText, context]];
        Quiet[CurrentValue[nb, WindowStatusArea] =
          iL["\:540c\:671f\:4e2d: \:30d1\:30e9\:30b0\:30e9\:30d5\:751f\:6210...", "Syncing: generating paragraph..."]];
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
                      iL["\:540c\:671f\:4e2d: \:7ffb\:8a33\:66f4\:65b0...", "Syncing: updating translation..."]];
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
                            iL["\:540c\:671f\:5b8c\:4e86", "Sync complete"]];
                          RunScheduledTask[With[{pNb = nb2},
                            Quiet[CurrentValue[pNb, WindowStatusArea] = ""]], {3}]]],
                        nb2, PrivacyLevel -> NBAccess`NBCellPrivacyLevel[nb2, idx],
                        Fallback -> fb]],
                    NBAccess`NBCellSetTaggingRule[nb2, idx,
                      {$iDocTagRoot, "syncTag"}, Inherited];
                    Quiet[CurrentValue[nb2, WindowStatusArea] =
                      iL["\:540c\:671f\:5b8c\:4e86", "Sync complete"]];
                    RunScheduledTask[With[{pNb = nb2},
                      Quiet[CurrentValue[pNb, WindowStatusArea] = ""]], {3}]]],
                NBAccess`NBCellSetTaggingRule[nb2, idx,
                  {$iDocTagRoot, "syncTag"}, Inherited];
                Quiet[CurrentValue[nb2, WindowStatusArea] =
                  iL["\:540c\:671f\:30a8\:30e9\:30fc", "Sync error"]];
                RunScheduledTask[With[{pNb = nb2},
                  Quiet[CurrentValue[pNb, WindowStatusArea] = ""]], {3}]]]],
            nb, PrivacyLevel -> NBAccess`NBCellPrivacyLevel[nb, cellIdx],
            Fallback -> useFallback]],

      (* === Case 2: \:30d1\:30e9\:30b0\:30e9\:30d5\:8868\:793a\:4e2d \[RightArrow] \:7ffb\:8a33\:3092\:518d\:751f\:6210 === *)
      mode === "paragraph",
        paragraph = currentText;
        translation = NBAccess`NBCellGetTaggingRule[nb, cellIdx, $iDocTagTranslation];
        ideaText = NBAccess`NBCellGetTaggingRule[nb, cellIdx, $iDocTagAlternate];
        If[!StringQ[ideaText], ideaText = ""];
        If[!StringQ[translation] || StringTrim[translation] === "",
          NBAccess`NBCellSetTaggingRule[nb, cellIdx,
            {$iDocTagRoot, "syncTag"}, Inherited];
          MessageDialog[iL[
            "\:7ffb\:8a33\:304c\:3042\:308a\:307e\:305b\:3093\:3002\:5148\:306b\:7ffb\:8a33\:30dc\:30bf\:30f3\:3067\:7ffb\:8a33\:3092\:751f\:6210\:3057\:3066\:304f\:3060\:3055\:3044\:3002",
            "No translation exists. Use the Translate button first."]];
          Return[$Failed]];
        prompt = iDocReTranslatePromptFn[paragraph, targetLang, translation, ideaText];
        Quiet[CurrentValue[nb, WindowStatusArea] =
          iL["\:540c\:671f\:4e2d: \:7ffb\:8a33\:66f4\:65b0...", "Syncing: updating translation..."]];
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
                iL["\:540c\:671f\:5b8c\:4e86", "Sync complete"]];
              RunScheduledTask[With[{pNb = nb2},
                Quiet[CurrentValue[pNb, WindowStatusArea] = ""]], {3}]]],
            nb, PrivacyLevel -> NBAccess`NBCellPrivacyLevel[nb, cellIdx],
            Fallback -> useFallback]],

      (* === Case 3: \:7ffb\:8a33\:8868\:793a\:4e2d \[RightArrow] \:30d1\:30e9\:30b0\:30e9\:30d5\:3092\:9006\:66f4\:65b0 === *)
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
          iL["\:540c\:671f\:4e2d: \:30d1\:30e9\:30b0\:30e9\:30d5\:66f4\:65b0...", "Syncing: updating paragraph..."]];
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
                iL["\:540c\:671f\:5b8c\:4e86", "Sync complete"]];
              RunScheduledTask[With[{pNb = nb2},
                Quiet[CurrentValue[pNb, WindowStatusArea] = ""]], {3}]]],
            nb, PrivacyLevel -> NBAccess`NBCellPrivacyLevel[nb, cellIdx],
            Fallback -> useFallback]],

      (* === \:305d\:308c\:4ee5\:5916: \:540c\:671f\:5bfe\:8c61\:306a\:3057 === *)
      True,
        NBAccess`NBCellSetTaggingRule[nb, cellIdx,
          {$iDocTagRoot, "syncTag"}, Inherited];
        MessageDialog[iL[
          "\:3053\:306e\:30bb\:30eb\:306b\:306f\:540c\:671f\:53ef\:80fd\:306a\:30b3\:30f3\:30c6\:30f3\:30c4\:304c\:3042\:308a\:307e\:305b\:3093\:3002",
          "No syncable content in this cell."]]
    ];
  ];

(* ============================================================
   \:4e00\:62ec\:8868\:793a\:5207\:66ff
   \:5c55\:958b\:6e08\:307f\:30bb\:30eb\:ff08idea/paragraph/translated \:30e2\:30fc\:30c9\:ff09\:306e\:8868\:793a\:3092\:4e00\:62ec\:3067\:5207\:308a\:66ff\:3048\:308b\:3002
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
      (* \:5bfe\:8c61: documentation \:30e2\:30fc\:30c9\:3092\:6301\:3064\:30bb\:30eb\:306e\:307f *)
      If[StringQ[mode],
        Which[
          (* === \:5168\:30d7\:30ed\:30f3\:30d7\:30c8\:8868\:793a === *)
          targetView === "idea" && mode === "paragraph" && !TrueQ[showTrans],
            (* paragraph \[RightArrow] idea *)
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
            (* translation \[RightArrow] idea (via paragraph revert + toggle) *)
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

          (* === \:5168\:30d1\:30e9\:30b0\:30e9\:30d5\:8868\:793a === *)
          targetView === "paragraph" && mode === "idea",
            (* idea \[RightArrow] paragraph *)
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
            (* translation \[RightArrow] paragraph *)
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

          (* === \:5168\:7ffb\:8a33\:8868\:793a === *)
          targetView === "translation" && !TrueQ[showTrans],
            storedTranslation = NBAccess`NBCellGetTaggingRule[nb, i, $iDocTagTranslation];
            If[StringQ[storedTranslation] && StringTrim[storedTranslation] =!= "",
              (* \:73fe\:5728\:306e\:30c6\:30ad\:30b9\:30c8\:3092 translationSrc \:306b\:4fdd\:5b58 *)
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
      (* translated \:30e2\:30fc\:30c9\:ff08\:666e\:901a\:30bb\:30eb+\:7ffb\:8a33\:ff09\:306e\:30c8\:30b0\:30eb\:3082\:51e6\:7406 *)
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
        iL[ToString[count] <> " \:30bb\:30eb\:3092\:5207\:308a\:66ff\:3048\:307e\:3057\:305f\:3002",
           ToString[count] <> " cells switched."]];
      RunScheduledTask[With[{pNb = nb},
        Quiet[CurrentValue[pNb, WindowStatusArea] = ""]], {3}]];
  ];

(* ============================================================
   \:30d1\:30ec\:30c3\:30c8\:30dc\:30bf\:30f3\:30a2\:30af\:30b7\:30e7\:30f3
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
      MessageDialog[iL["\:30bb\:30eb\:3092\:9078\:629e\:3057\:3066\:304f\:3060\:3055\:3044\:3002", "Please select a cell."]];
      Return[$Failed]];
    If[Length[cellIdxs] === 1,
      DocExpandIdea[nb, First[cellIdxs], Fallback -> ClaudeCode`GetPaletteFallback[]],
      (* \:8907\:6570\:30bb\:30eb: \:975e\:540c\:671f\:30c1\:30a7\:30fc\:30f3\:3067\:9010\:6b21\:5c55\:958b *)
      iDocExpandSelectedChain[nb, cellIdxs, 1, ClaudeCode`GetPaletteFallback[]]]
  ];

(* \:8907\:6570\:30bb\:30eb\:5c55\:958b\:306e\:975e\:540c\:671f\:30c1\:30a7\:30fc\:30f3 *)
iDocExpandSelectedChain[nb_, idxs_, pos_, fb_] :=
  If[pos > Length[idxs],
    Quiet[CurrentValue[nb, WindowStatusArea] =
      iL[ToString[Length[idxs]] <> " \:30bb\:30eb\:3092\:5c55\:958b\:3057\:307e\:3057\:305f\:3002",
         ToString[Length[idxs]] <> " cells expanded."]];
    RunScheduledTask[With[{pNb = nb},
      Quiet[CurrentValue[pNb, WindowStatusArea] = ""]], {3}],
    Quiet[CurrentValue[nb, WindowStatusArea] =
      iL["\:5c55\:958b\:4e2d: ", "Expanding: "] <> ToString[pos] <> "/" <> ToString[Length[idxs]]];
    Module[{cellIdx = idxs[[pos]], mode},
      mode = NBAccess`NBCellGetTaggingRule[nb, cellIdx, $iDocTagMode];
      If[mode === "paragraph",
        (* \:30d1\:30e9\:30b0\:30e9\:30d5\:30e2\:30fc\:30c9\:306f\:30b9\:30ad\:30c3\:30d7 *)
        iDocExpandSelectedChain[nb, idxs, pos + 1, fb],
        (* \:5c55\:958b: completionFn \:5185\:3067\:6b21\:3078\:9032\:3080\:3002
           DocExpandIdea \:306f\:5185\:90e8\:3067 NBCellTransformWithLLM \:3092\:4f7f\:3044\:3001
           completionFn \:3067\:30e1\:30bf\:30c7\:30fc\:30bf\:3092\:8a2d\:5b9a\:3059\:308b\:3002\:3053\:3053\:3067\:306f\:8ffd\:52a0\:306e\:5b8c\:4e86\:51e6\:7406\:3068\:3057\:3066
           \:30c1\:30a7\:30fc\:30f3\:306e\:6b21\:30b9\:30c6\:30c3\:30d7\:3092\:547c\:3076\:3002 *)
        DocExpandIdea[nb, cellIdx, Fallback -> fb];
        (* DocExpandIdea \:306f\:975e\:540c\:671f\:306a\:306e\:3067\:5373\:5ea7\:306b\:6b21\:3078\:9032\:3081\:306a\:3044\:3002
           \:4ee3\:308f\:306b ScheduledTask \:3067\:9045\:5ef6\:5b9f\:884c\:3057\:3066\:6b21\:306e\:30bb\:30eb\:3078\:3002 *)
        RunScheduledTask[
          With[{pNb = nb, is = idxs, p = pos, f = fb},
            iDocExpandSelectedChain[pNb, is, p + 1, f]], {2}]]]
  ];

iDocToggleSelected[] :=
  Module[{nb, cellIdx},
    {nb, cellIdx} = iDocResolveTargetCell[];
    If[cellIdx === 0,
      MessageDialog[iL["\:30bb\:30eb\:3092\:9078\:629e\:3057\:3066\:304f\:3060\:3055\:3044\:3002", "Please select a cell."]];
      Return[$Failed]];
    DocToggleView[nb, cellIdx]
  ];

iDocTranslateSelected[] :=
  Module[{nb, cellIdxs},
    {nb, cellIdxs} = iDocResolveTargetCells[];
    If[Length[cellIdxs] === 0,
      MessageDialog[iL["\:30bb\:30eb\:3092\:9078\:629e\:3057\:3066\:304f\:3060\:3055\:3044\:3002", "Please select a cell."]];
      Return[$Failed]];
    If[Length[cellIdxs] === 1,
      DocTranslate[nb, First[cellIdxs], Fallback -> ClaudeCode`GetPaletteFallback[]],
      (* \:8907\:6570\:30bb\:30eb: \:975e\:540c\:671f\:30c1\:30a7\:30fc\:30f3\:3067\:9010\:6b21\:7ffb\:8a33 *)
      iDocTranslateSelectedChain[nb, cellIdxs, 1, ClaudeCode`GetPaletteFallback[]]]
  ];

(* \:8907\:6570\:30bb\:30eb\:7ffb\:8a33\:306e\:975e\:540c\:671f\:30c1\:30a7\:30fc\:30f3 *)
iDocTranslateSelectedChain[nb_, idxs_, pos_, fb_] :=
  If[pos > Length[idxs],
    Quiet[CurrentValue[nb, WindowStatusArea] =
      iL[ToString[Length[idxs]] <> " \:30bb\:30eb\:3092\:7ffb\:8a33\:3057\:307e\:3057\:305f\:3002",
         ToString[Length[idxs]] <> " cells translated."]];
    RunScheduledTask[With[{pNb = nb},
      Quiet[CurrentValue[pNb, WindowStatusArea] = ""]], {3}],
    Quiet[CurrentValue[nb, WindowStatusArea] =
      iL["\:7ffb\:8a33\:4e2d: ", "Translating: "] <> ToString[pos] <> "/" <> ToString[Length[idxs]]];
    Module[{cellIdx = idxs[[pos]], mode},
      mode = NBAccess`NBCellGetTaggingRule[nb, cellIdx, $iDocTagMode];
      If[mode === "idea",
        (* \:30d7\:30ed\:30f3\:30d7\:30c8\:30e2\:30fc\:30c9\:306f\:30b9\:30ad\:30c3\:30d7 *)
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
      MessageDialog[iL["\:30bb\:30eb\:3092\:9078\:629e\:3057\:3066\:304f\:3060\:3055\:3044\:3002", "Please select a cell."]];
      Return[$Failed]];
    DocSync[nb, cellIdx, Fallback -> ClaudeCode`GetPaletteFallback[]]
  ];

(* ============================================================
   \:30d1\:30ec\:30c3\:30c8\:8a2d\:5b9a
   ============================================================ *)

(* ============================================================
   \:30e1\:30a4\:30f3\:30d1\:30ec\:30c3\:30c8
   ============================================================ *)

ShowDocPalette[] := (
  If[$docPalette =!= None, Quiet@NotebookClose[$docPalette]];
  (* \:521d\:671f\:30ed\:30fc\:30c9: \:73fe\:5728\:306e\:30ce\:30fc\:30c8\:30d6\:30c3\:30af\:304b\:3089\:8a2d\:5b9a\:3092\:8aad\:307f\:8fbc\:3080 *)
  Module[{initNb = Quiet[InputNotebook[]]},
    If[Head[initNb] === NotebookObject,
      ClaudeCode`LoadPaletteSettings[initNb]]];
  $docPalette = CreatePalette[
    DynamicModule[{lastNb = None},
    Dynamic[
      (* \:30ce\:30fc\:30c8\:30d6\:30c3\:30af\:5207\:66ff\:3092\:691c\:51fa\:3057\:3066\:8a2d\:5b9a\:3092\:30ea\:30ed\:30fc\:30c9 *)
      Module[{curNb = Quiet[InputNotebook[]]},
        If[Head[curNb] === NotebookObject &&
           Quiet[CurrentValue[curNb, WindowClickSelect]] =!= False &&
           curNb =!= lastNb,
          lastNb = curNb;
          ClaudeCode`LoadPaletteSettings[curNb]]];
    Column[{
      Style["Documentation", Bold, 11, RGBColor[0.2, 0.5, 0.3]],

      (* -- \:57f7\:7b46\:30c4\:30fc\:30eb -- *)
      Style[iL[" \:57f7\:7b46\:30c4\:30fc\:30eb", " Writing Tools"], Bold, 8, GrayLevel[0.3]],
      iDocButton[iL["\[FilledRightTriangle] \:5c55\:958b", "\[FilledRightTriangle] Expand"],
        RGBColor[0.2, 0.55, 0.35],
        iDocExpandSelected[]],
      iDocButton[iL["\[LeftRightArrow] \:5207\:66ff", "\[LeftRightArrow] Toggle"],
        RGBColor[0.35, 0.45, 0.65],
        iDocToggleSelected[]],
      iDocButton[iL["\[RightGuillemet] \:7ffb\:8a33", "\[RightGuillemet] Translate"],
        RGBColor[0.3, 0.4, 0.65],
        iDocTranslateSelected[]],
      iDocButton[iL["\[Equilibrium] \:540c\:671f", "\[Equilibrium] Sync"],
        RGBColor[0.45, 0.35, 0.6],
        iDocSyncSelected[]],
      Spacer[2],

      (* -- \:4e00\:62ec\:8868\:793a\:5207\:66ff -- *)
      Style[iL[" \:4e00\:62ec\:8868\:793a", " View All"], Bold, 8, GrayLevel[0.3]],
      iDocButton[iL["\[Ellipsis] \:5168\:30d7\:30ed\:30f3\:30d7\:30c8", "\[Ellipsis] All Prompts"],
        RGBColor[0.65, 0.5, 0.2],
        iDocShowAllAs["idea"]],
      iDocButton[iL["\[Paragraph] \:5168\:30d1\:30e9\:30b0\:30e9\:30d5", "\[Paragraph] All Paragraphs"],
        RGBColor[0.25, 0.5, 0.4],
        iDocShowAllAs["paragraph"]],
      iDocButton[iL["\[CapitalAHat] \:5168\:7ffb\:8a33", "\[CapitalAHat] All Translations"],
        RGBColor[0.3, 0.4, 0.65],
        iDocShowAllAs["translation"]],
      Spacer[2],

      (* -- \:8a2d\:5b9a (ClaudeCode \:30d1\:30ec\:30c3\:30c8\:3068\:5171\:6709: \:516c\:958b\:30a2\:30af\:30bb\:30b5\:7d4c\:7531) -- *)
      Style[iL[" \:8a2d\:5b9a", " Settings"], Bold, 8, GrayLevel[0.3]],
      Dynamic[
        Button[
          Style[iL["\:30e2\:30c7\:30eb: ", "Model: "] <>
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
          Style[iL["\:30a8\:30d5\:30a9\:30fc\:30c8: ", "Effort: "] <>
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
          Style[iL["\:8ab2\:91d1API: ", "Paid API: "] <>
            If[ClaudeCode`GetPaletteFallback[],
              iL["\:8a31\:53ef", "On"],
              iL["\:7981\:6b62", "Off"]],
            9, Bold, GrayLevel[0.2]],
          (ClaudeCode`SetPaletteFallback[!ClaudeCode`GetPaletteFallback[]];
           ClaudeCode`SavePaletteSettings[InputNotebook[]]),
          Appearance -> "Frameless"]],
      Spacer[2],

      (* -- \:30b9\:30c6\:30fc\:30bf\:30b9 -- *)
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

(* \:30d1\:30c3\:30b1\:30fc\:30b8\:30ed\:30fc\:30c9\:6642\:306b\:30d1\:30ec\:30c3\:30c8\:3092\:81ea\:52d5\:8868\:793a *)
Documentation`ShowDocPalette[];

(* \:30d1\:30ec\:30c3\:30c8\:30e1\:30cb\:30e5\:30fc\:306b\:767b\:9332\:ff08claudecode.wl \:306e AddToPalettesMenu \:3068\:540c\:3058\:30d1\:30bf\:30fc\:30f3\:ff09 *)
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
