# documentation_paper2nb API Reference

Context: `Documentation\`` (this file extends documentation.wl; load via `Get["documentation_paper2nb.wl"]` after documentation.wl, or let documentation.wl's trailing `Get` load it).
Dependencies: `NBAccess\`` ([NBAccess](https://github.com/transreal/NBAccess)), `ClaudeCode\`` ([claudecode](https://github.com/transreal/claudecode)).

## Overview
Converts a paper PDF into a documentation-convention notebook (reverse direction of documentation.wl's notebook→LaTeX/Word/Markdown). Two parts:
- Part 1 (text reproduction): rebuilds heading hierarchy, translates paragraphs into Text cells while keeping the original in `TaggingRules` (`translationSrc`, `mode->"translated"`, toggleable via DocToggleView), renders inline math as `Cell[BoxData[FormBox[...]]]` inside TextData, renders display math as `"DisplayFormula"` cells (falls back to a cropped page-image when LaTeX→box conversion fails), crops figures/tables from page images with captions as tagged Text cells, and emits Bibliography/Directive/Dictionary meta cells. Every generated cell carries `"refSources" -> {pdf, {pages}}`.
- Part 2 (computation reconstruction): extracts reproducible computations/algorithms/formulas from the full paper text into WL definitions + runnable examples. Generated code is checked with `SyntaxQ`; on failure one fix-up LLM round trip is attempted. Code is never evaluated by the package.

Element positioning: `Import[pdf, {"PagePositionedObjects", p}]` gives text blocks with PDF-space bounding boxes (origin bottom-left); blocks are numbered `[Bn]` and shown to the LLM, which returns the block ids composing each figure/table/equation. Crop regions are the union of those ids' rectangles, extended to neighboring-block boundaries for a figure with no interior text. Page images (`Import[pdf, {"PageImages", p}, ImageResolution -> r]`) are indexed via `px = x*r/72`, `py = (H - y)*r/72`.

LLM calls go through `ClaudeCode\`ClaudeQueryBg` (synchronous, no FE interaction, no ScheduledTask). Page images are passed as `{prompt, image}` list items; non-CLI (raw API) providers need `Fallback -> True` for vision. JSON responses are read with `ImportByteArray[..., "RawJSON"]`.

Privacy: PDF text and page images are sent to whichever LLM provider is selected in the palette. Use a local provider (e.g. lmstudio) for unpublished manuscripts. `"CloudPublishable"` is NOT set by default; pass `True`/`False` explicitly to have `NBSetCloudPublishable` applied to the output notebook.

## DocImportPaper[pdfPath, opts]
Converts a paper PDF into a documentation-convention notebook (Part 1 + Part 2) and saves/opens it.
→ NotebookObject (if opened in a front end) | file path string (headless) | $Failed
Options: "TargetLanguage" -> Automatic (defaults to $Language, else "English"), "Translate" -> True, "Reconstruct" -> True (run Part 2), "Pages" -> All | {1,2,...} | Span, "ImageResolution" -> 150, "MathMode" -> "Auto" ("Auto": LaTeX→boxes else image fallback; "Image": display math always cropped from page image; "Text": never falls back to an image, keeps raw LaTeX text), "Vision" -> Automatic (page images also sent to LLM; auto-retries text-only on failure/timeout/no-vision-model; False disables), "VisionTimeout" -> Automatic (seconds before a vision-attempt is aborted and retried text-only; auto-resolves to 1500s for local providers (lmstudio/llamacpp/freetoken), 600s otherwise), "OutputPath" -> Automatic (defaults to `<pdf-folder>/<name>.nb`, auto-suffixed `_2`, `_3`, ... to avoid overwrite), "Open" -> True, "Save" -> True, "CloudPublishable" -> None (None: no SourceVault declaration; True|False: applies NBSetCloudPublishable), "Directive" -> Automatic (translation instruction, also written into the Directive cell; language-dependent default), "Dictionary" -> {} (list of {sourceTerm, targetTerm, context} triples, written into the Dictionary cell and the translation prompt), "HeadingStyles" -> Automatic ({"Section","Subsection","Subsubsection","Subsubsubsection"}), "Verbose" -> True, Fallback -> False (allow paid/cloud API), Model -> Automatic, Timeout -> Automatic
例:
```
DocImportPaper["C:/papers/original.pdf"]
DocImportPaper[pdf, "Pages" -> 1 ;; 3, "Reconstruct" -> False]
DocImportPaper[pdf, "MathMode" -> "Image", "Vision" -> False, "CloudPublishable" -> False]
```

## DocPaperAnalyzePage[pdfPath, page, opts]
Runs the per-page structural analysis stage alone (what DocImportPaper does internally for each page): extracts positioned text blocks + page image, asks the LLM to reconstruct reading order and classify elements.
→ List of block associations, each like `<|"type","text","latex","label","ids","translation","Page","Region",...|>`, in reading order | $Failed
Options: "TargetLanguage" -> Automatic, "Translate" -> True, "ImageResolution" -> 150, "Vision" -> Automatic, "Directive" -> Automatic, "Dictionary" -> {}, "Verbose" -> True, "VisionTimeout" -> Automatic, Fallback -> False, Model -> Automatic, Timeout -> Automatic
`"type"` is one of: "title","authors","affiliation","abstract","keywords","heading","paragraph","list","display_math","figure","table","caption","references","footnote","page_header","other". `"level"` (1-3) is set for headings. `"ids"` lists the source block ids (e.g. `["B4","B5"]`, ranges as `"B12-B40"`) that compose the element. `"continues"`/`"unfinished"` flag elements cut across the page boundary (merged across pages internally). `"bib"` is populated for `"references"` blocks with `{"key","author","year","title"}`.

## DocPaperExtractComputations[pdfPath, opts]
## DocPaperExtractComputations[pdfPath, blocks, opts]
Extracts reproducible computations/algorithms/formulas from the paper's full text and reconstructs them as WL code with runnable examples (Part 2 standalone). The 2-argument form reuses previously analyzed blocks (concatenation of DocPaperAnalyzePage results) as the source text instead of re-extracting plain text from the PDF.
→ `<|"summary" -> String, "units" -> {<|"title","description","code","example","syntaxOK"|>, ...}, "notes" -> String|>` | $Failed
Options: "TargetLanguage" -> Automatic, "Pages" -> All, "Verbose" -> True, Fallback -> False, Model -> Automatic, Timeout -> Automatic
Each unit's `"code"` is checked with SyntaxQ; on parse failure a single LLM fix-up round trip is attempted and `"syntaxOK"` reflects the final result (code is inserted either way — see `DocImportPaper::syntax`).

## DocPaperTeXToBoxes[latex] → BoxExpression | $Failed
Converts a LaTeX math string to a TraditionalForm box expression. Tries (1) a built-in simplified LaTeX parser (subscripts/superscripts, fractions, roots, matrix environments, Greek letters, operator symbols — literal, not semantic), then (2) `ToExpression[..., TeXForm] // ToBoxes`. Returns $Failed if both fail.
例: `Cell[BoxData[FormBox[DocPaperTeXToBoxes["\\frac{a}{b}"], TraditionalForm]], "DisplayFormula"]`

## DocPaperTextToTextData[text] → TextData | String
Converts a string containing `$...$` or `\(...\)` inline math into a TextData expression with embedded inline-math cells (each formula run through DocPaperTeXToBoxes, falling back to a monospaced literal LaTeX StyleBox on failure). Returns the input unchanged if it contains no math delimiters. Ready to use directly as Text-cell content.

## $DocPaperLastAnalysis
型: Association (or unset), 初期値: none
Holds the intermediate state of the most recent DocImportPaper / DocPaperAnalyzePage / DocPaperExtractComputations call: `<|"PDF","Pages","Blocks","Computations","Cells"|>`. Kept for debugging/reuse; DocImportPaper strips heavy per-page fields (`"PageBlocks"`,`"PageImage"`,`"PageClaimedIds"`) from `"Blocks"` before returning.

## Messages
DocImportPaper::nofile — PDF file not found.
DocImportPaper::nopages — could not determine PDF page count.
DocImportPaper::llm — LLM call failed.
DocImportPaper::json — LLM response could not be parsed as JSON (page `n`).
DocImportPaper::syntax — reconstructed code still fails SyntaxQ after one fix attempt; inserted as-is.