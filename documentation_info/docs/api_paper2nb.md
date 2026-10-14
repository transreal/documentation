# documentation_paper2nb API Reference

Context: `Documentation\`` (this file extends documentation.wl; load via `Get["documentation_paper2nb.wl"]` after documentation.wl, or let documentation.wl's trailing `Get` load it).
Dependencies: `NBAccess\`` ([NBAccess](https://github.com/transreal/NBAccess)), `ClaudeCode\`` ([claudecode](https://github.com/transreal/claudecode)). Optional: `SourceVault\`` / `SourceVault_papernb` ([SourceVault](https://github.com/transreal/SourceVault), [SourceVault_papernb](https://github.com/transreal/SourceVault_papernb)) — only used when `DocImportPaper` is called with a SourceVault reference instead of a local PDF path.

## Overview
Converts a paper PDF into a documentation-convention notebook (reverse direction of documentation.wl's notebook→LaTeX/Word/Markdown). Two parts:
- Part 1 (text reproduction): rebuilds heading hierarchy, translates paragraphs into Text cells while keeping the original in `TaggingRules` (`translationSrc`, `mode->"translated"`, toggleable via DocToggleView), renders inline math as `Cell[BoxData[FormBox[...]]]` inside TextData, renders display math as `"DisplayFormula"` cells (falls back to a cropped page-image when LaTeX→box conversion fails), crops figures/tables from page images with captions as tagged Text cells, and emits Bibliography/Directive/Dictionary meta cells. Every generated cell carries `"refSources" -> {pdf, {pages}}`.
- Part 2 (computation reconstruction): extracts reproducible computations/algorithms/formulas from the full paper text into WL definitions + runnable examples. Generated code is checked with `SyntaxQ`; on failure one fix-up LLM round trip is attempted. Code is never evaluated by the package.

Element positioning: `Import[pdf, {"PagePositionedObjects", p}]` gives text blocks with PDF-space bounding boxes (origin bottom-left); blocks are numbered `[Bn]` and shown to the LLM, which returns the block ids composing each figure/table/equation. Crop regions are the union of those ids' rectangles, extended to neighboring-block boundaries for a figure with no interior text. Page images (`Import[pdf, {"PageImages", p}, ImageResolution -> r]`) are indexed via `px = x*r/72`, `py = (H - y)*r/72`.

LLM calls go through `ClaudeCode\`ClaudeQueryBg` (synchronous, no FE interaction, no ScheduledTask). Page images are passed as `{prompt, image}` list items; non-CLI (raw API) providers need `Fallback -> True` for vision. JSON responses are read with `ImportByteArray[..., "RawJSON"]`. LLM server connection failures are tracked across pages: 2 consecutive connection failures abort the remaining pages (see `DocImportPaper::abort`) rather than spending the whole run on a dead server.

SourceVault delegation: when `DocImportPaper` is called with a reference string instead of a local file path (`"src-..."`, `"sv://..."`, `"arxiv:..."`, or an `http://`/`https://` URL) and `SourceVault\`SourceVaultMakePaperNotebook` is loaded, the call is delegated to it. The ingested source's `PrivacyLevel` is inherited: PL < 0.5 uses the normal cloud LLM path plus a `CloudPublishable` declaration on the output notebook; PL >= 0.5 restricts the LLM path to `$ClaudePrivateModel` only. A plain local PDF path never takes this branch (no PrivacyLevel to inherit, so no declaration is applied automatically — see `"CloudPublishable"` below).

Privacy: PDF text and page images are sent to whichever LLM provider is selected in the palette. Use a local provider (e.g. lmstudio) for unpublished manuscripts. `"CloudPublishable"` is NOT set by default; pass `True`/`False` explicitly to have `NBSetCloudPublishable` applied to the output notebook.

Translation notebooks (2026-10-12): `"Translate" -> Automatic` (the default) detects the source language (`DocPaperDetectLanguage` on the text layer of the first 3 selected pages; for web pages on the extracted text) and translates only when it differs from `"TargetLanguage"` (default `$Language`). When the source is already in the target language the notebook is built without translation (structure only, no `"translation"` field requested from the LLM). If the language cannot be detected, it translates (previous behavior). Chinese Simplified/Traditional are treated as the same language. The result is recorded in `$DocPaperLastAnalysis` (`"SourceLanguage"`, `"Translated"`) and in the notebook's TaggingRules (`"paperSourceLanguage"`, `"paperTranslated"`).

Web pages (2026-10-12): `DocImportWebPage` converts a saved web page (HTML / text / Markdown) into the same notebook convention. Unlike the PDF path, the LLM does not analyze structure: blocks are extracted deterministically from the HTML (main container = largest `<article>` → `<main>`/`role=main` → descend into the child holding ≥70% of the text; nav/footer/forms/scripts and share/sidebar/comment-like containers are pruned) and only the translation is delegated to the LLM, in JSON batches (≤6000 chars / ≤40 items). `DocImportPaper` called with a local `.html`/`.htm`/`.md`/`.txt` path delegates to `DocImportWebPage`.

## DocImportPaper[pdfPath, opts]
## DocImportPaper[sourceRef, opts]
Converts a paper PDF into a documentation-convention notebook (Part 1 + Part 2) and saves/opens it. `sourceRef` (`"src-..."`, `"sv://..."`, `"arxiv:..."`, or an `http://`/`https://` URL) delegates to `SourceVault\`SourceVaultMakePaperNotebook` instead (see Overview) — only when that symbol is loaded and the ref is not itself an existing local file. A local `.html`/`.htm`/`.xhtml`/`.md`/`.txt` path delegates to `DocImportWebPage`.
→ NotebookObject (if opened in a front end) | file path string (headless) | $Failed
Options: "TargetLanguage" -> Automatic (defaults to $Language, else "English"), "Translate" -> Automatic (translate only when the detected source language differs from TargetLanguage) | True | False, "Reconstruct" -> True (run Part 2), "Pages" -> All | {1,2,...} | Span, "ImageResolution" -> 150, "MathMode" -> "Auto" ("Auto": LaTeX→boxes else image fallback; "Image": display math always cropped from page image; "Text": never falls back to an image, keeps raw LaTeX text), "Vision" -> Automatic (page images also sent to LLM; auto-retries text-only on failure/timeout/no-vision-model; False disables), "VisionTimeout" -> Automatic (seconds before a vision-attempt is aborted and retried text-only; auto-resolves to 1500s for local providers (lmstudio/llamacpp/freetoken), 600s otherwise), "OutputPath" -> Automatic (defaults to `<pdf-folder>/<name>.nb`, auto-suffixed `_2`, `_3`, ... to avoid overwrite), "Open" -> True, "Save" -> True, "CloudPublishable" -> None (None: no SourceVault declaration; True|False: applies NBSetCloudPublishable), "Directive" -> Automatic (translation instruction, also written into the Directive cell; language-dependent default), "Dictionary" -> {} (list of {sourceTerm, targetTerm, context} triples, written into the Dictionary cell and the translation prompt), "HeadingStyles" -> Automatic ({"Section","Subsection","Subsubsection","Subsubsubsection"}), "Verbose" -> True, Fallback -> False (allow paid/cloud API), Model -> Automatic, Timeout -> Automatic
例:
```
DocImportPaper["C:/papers/original.pdf"]
DocImportPaper[pdf, "Pages" -> 1 ;; 3, "Reconstruct" -> False]
DocImportPaper[pdf, "MathMode" -> "Image", "Vision" -> False, "CloudPublishable" -> False]
DocImportPaper["arxiv:2401.12345"]  (* delegates to SourceVault, inherits its PrivacyLevel *)
```

## DocPaperAnalyzePage[pdfPath, page, opts]
Runs the per-page structural analysis stage alone (what DocImportPaper does internally for each page): extracts positioned text blocks + page image, asks the LLM to reconstruct reading order and classify elements.
→ List of block associations, each like `<|"type","text","latex","label","ids","translation","Page","Region",...|>`, in reading order | $Failed
Options: "TargetLanguage" -> Automatic, "Translate" -> Automatic (decided from the page's text layer), "ImageResolution" -> 150, "Vision" -> Automatic, "Directive" -> Automatic, "Dictionary" -> {}, "Verbose" -> True, "VisionTimeout" -> Automatic, Fallback -> False, Model -> Automatic, Timeout -> Automatic
`"type"` is one of: "title","authors","affiliation","abstract","keywords","heading","paragraph","list","display_math","figure","table","caption","references","footnote","page_header","other". `"level"` (1-3) is set for headings. `"ids"` lists the source block ids (e.g. `["B4","B5"]`, ranges as `"B12-B40"`) that compose the element. `"continues"`/`"unfinished"` flag elements cut across the page boundary (merged across pages internally). `"bib"` is populated for `"references"` blocks with `{"key","author","year","title"}`.

## DocPaperExtractComputations[pdfPath, opts]
## DocPaperExtractComputations[pdfPath, blocks, opts]
Extracts reproducible computations/algorithms/formulas from the paper's full text and reconstructs them as WL code with runnable examples (Part 2 standalone). The 2-argument form reuses previously analyzed blocks (concatenation of DocPaperAnalyzePage results) as the source text instead of re-extracting plain text from the PDF.
→ `<|"summary" -> String, "units" -> {<|"title","description","code","example","syntaxOK"|>, ...}, "notes" -> String|>` | $Failed
Options: "TargetLanguage" -> Automatic, "Pages" -> All, "Verbose" -> True, Fallback -> False, Model -> Automatic, Timeout -> Automatic
Each unit's `"code"` is checked with SyntaxQ; on parse failure a single LLM fix-up round trip is attempted and `"syntaxOK"` reflects the final result (code is inserted either way — see `DocImportPaper::syntax`).

## DocImportWebPage[path, opts]
Converts a saved web page (`.html`/`.htm`/`.xhtml` → HTML, `.md` → Markdown, `.txt` → text) into a documentation-convention translation notebook. SourceVault web sources go through `SourceVault\`SourceVaultMakePaperNotebook["src-..."]`, which passes the page URL/title and inherits the source PrivacyLevel.
→ NotebookObject (if opened in a front end) | file path string (headless, saved) | Notebook expression ("Save" -> False) | $Failed
Extracted blocks → cells: title (`HeadingStyles[[1]]`, the h1/h2 near the top matching `<title>`/og:title, else the page title is prepended) followed by a source cell (hyperlink + translation note); headings (shallowest heading level used on the page = level 1); paragraphs and blockquotes → `"Text"` (quotes tagged `paperType -> "quote"`); list items → `"Item"`/`"Subitem"`/`"Subsubitem"` (ordered: `"ItemNumbered"`…); `<pre>` / multi-line `<code>` → `"Program"` (not translated); inline `<code>` → monospace StyleBox; MathML (`alttext` or TeX annotation), LaTeXML equation tables (`ltx_equation*`, label from `ltx_tag_equation`), KaTeX annotations and MathJax `<script type="math/tex">` → inline formulas / `"DisplayFormula"`; on pages that load MathJax/KaTeX, prose `$…$`, `$$…$$`, `\(…\)`, `\[…\]` are math, otherwise a literal `$` stays text (`\$` internally); `<table>` → Grid (caption cell first; textual tables translated cell by cell with the original rows kept in `paperTableSrc`; layout tables are read as body text); `<figure>`/`<img>` → image cell (downloaded; data: URIs decoded; resized to ≤900 px wide) + caption cell, or a hyperlink cell when not fetched; icons/emoji/badges/tracking pixels are skipped; bibliography containers (`bibliography`/`references`/`reflist`/`biblist`) → "References" + untranslated Text. Translated cells use the same convention as DocImportPaper (`mode -> "translated"`, `translationSrc`, `showTranslation`, `cleanText`). Every cell carries `"refSources" -> {{file, All}}`. Notebook TaggingRules: `"paperSource"` (URL or file), `"paperFile"`, `"paperKind" -> "web"`, `"paperTargetLanguage"`, `"paperSourceLanguage"`, `"paperTranslated"`.
Options: "BaseURL" -> Automatic (page URL for resolving relative image links and the source cell; Automatic = og:url / canonical link; `<base href>` is honored), "Title" -> Automatic, "TargetLanguage" -> Automatic ($Language), "Translate" -> Automatic | True | False, "Images" -> True (False: link cells only), "MaxImages" -> 30 (the rest become link cells), "Reconstruct" -> False (True: Part 2 computation reconstruction from the page text), "OutputPath" -> Automatic (`<file-folder>/<name>.nb`, auto-suffixed), "Open" -> True, "Save" -> True, "CloudPublishable" -> None, "Directive" -> Automatic (web-oriented default), "Dictionary" -> {}, "HeadingStyles" -> Automatic, "Verbose" -> True, Fallback -> False, Model -> Automatic, Timeout -> Automatic
Translation failures leave the original text in place (`$DocPaperLastAnalysis["FailedItems"]`); 2 consecutive batches failing with an LLM-server connection error abort with `DocImportPaper::abort` and return $Failed. If almost no body text is found (JavaScript-rendered pages), the meta description and then the page's plain text are used.
例:
```
DocImportWebPage["C:/clip/page.html", "BaseURL" -> "https://example.org/post"]
DocImportWebPage[page, "TargetLanguage" -> "English", "Images" -> False, "Save" -> False]
SourceVault`SourceVaultMakePaperNotebook["src-url-…"]   (* SourceVault web source; PL inherited *)
```

## DocPaperDetectLanguage[text] → String | Missing["Unknown"]
Detects the language of a text: by script (kana → "Japanese", Han without kana → "Chinese", Hangul → "Korean", Cyrillic/Arabic/Hebrew/Thai/Devanagari/Greek), one CJK character counting as four Latin letters so Japanese technical prose with English terms stays Japanese; Latin script → "English" when English function words are ≥ 8% of the words, else `LanguageIdentify` (canonical entity name, e.g. "French"). `$...$`, backtick code and URLs are ignored. Used by `"Translate" -> Automatic`.

## DocPaperTeXToBoxes[latex] → BoxExpression | $Failed
Converts a LaTeX math string to a TraditionalForm box expression. Tries (1) a built-in simplified LaTeX parser (subscripts/superscripts, fractions, roots, matrix environments, Greek letters, operator symbols — literal, not semantic), then (2) `ToExpression[..., TeXForm] // ToBoxes`. Returns $Failed if both fail.
例: `Cell[BoxData[FormBox[DocPaperTeXToBoxes["\\frac{a}{b}"], TraditionalForm]], "DisplayFormula"]`

## DocPaperTextToTextData[text] → TextData | String
Converts a string containing `$...$` or `\(...\)` inline math into a TextData expression with embedded inline-math cells (each formula run through DocPaperTeXToBoxes, falling back to a monospaced literal LaTeX StyleBox on failure). Returns the input unchanged if it contains no math delimiters. Ready to use directly as Text-cell content.

## $DocPaperLastAnalysis
型: Association (or unset), 初期値: none
Holds the intermediate state of the most recent DocImportPaper / DocImportWebPage / DocPaperAnalyzePage / DocPaperExtractComputations call: `<|"PDF","Pages","Kind" -> "pdf","Blocks","Computations","Cells","SourceLanguage","TargetLanguage","Translated","FailedPages"|>` (web pages: `"Source"`, `"URL"`, `"Kind" -> "web"`, `"FailedItems"` instead of `"PDF"`). Kept for debugging/reuse; DocImportPaper strips heavy per-page fields (`"PageBlocks"`,`"PageImage"`,`"PageClaimedIds"`) from `"Blocks"` before returning.

## Messages
DocImportPaper::nofile — PDF file not found.
DocImportPaper::nopages — could not determine PDF page count.
DocImportPaper::llm — LLM call failed.
DocImportPaper::abort — LLM server connection failed for 2 consecutive pages; aborts remaining pages and returns $Failed.
DocImportPaper::json — LLM response could not be parsed as JSON (page `n`).
DocImportPaper::syntax — reconstructed code still fails SyntaxQ after one fix attempt; inserted as-is.
DocImportWebPage::nofile — file not found.
DocImportWebPage::format — not an HTML / text / Markdown file.
DocImportWebPage::empty — no body text could be extracted.