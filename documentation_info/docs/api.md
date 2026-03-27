# Documentation` API Reference

Package: `Documentation``
Context: `Documentation``
Dependencies: [NBAccess](https://github.com/transreal/NBAccess), [claudecode](https://github.com/transreal/claudecode)

Load: `Block[{$CharacterEncoding = "UTF-8"}, Get["documentation.wl"]]`

## Public Functions

### DocExpandIdea[nb, cellIdx, opts]
Expands the idea text in the specified cell into a paragraph using LLM. The original idea is saved in TaggingRules. If already in paragraph mode, expansion is blocked. If in idea mode with a saved paragraph, re-expands using the modified idea plus previous paragraph as context.
→ Null (async) or $Failed
Options: Fallback -> False (use fallback LLM if True)
例: DocExpandIdea[EvaluationNotebook[], 3, Fallback -> True]

### DocToggleView[nb, cellIdx] → String | Null | $Failed
Toggles cell display between idea, paragraph, and translation. Saves current content (even if edited) before switching. Cycle: idea → paragraph → translation (if available) → idea.
例: DocToggleView[EvaluationNotebook[], 5]

### DocInsertNote[nb] → Null
Inserts a Note-style cell at the current cursor position. Uses the notebook's existing "Note" style if defined; otherwise applies built-in visual options (yellow background, small font, indented).

### DocExportMarkdown[nb] → Null
Exports the notebook as Markdown to `NotebookDirectory[]/<name>_md/`. Note cells are excluded. Raster images → PNG, vector/computed results → PDF. Input cells → fenced code blocks, formulas → TeX.

### DocExportLaTeX[nb] → Null
Exports the notebook as LaTeX to `NotebookDirectory[]/<name>_LaTeX/`. Note cells are excluded. Raster images → PNG, vector/computed results → PDF. Input cells → lstlisting, formulas → TeX.

### ShowDocPalette[] → Null
Opens the documentation authoring palette. Closes any previously opened palette instance. Automatically loads palette settings from the current notebook on open and on notebook switch.

## Variables

### $DocTranslationLanguage
型: String, 初期値: "English" (if $Language ≠ "English") or "Japanese" (if $Language === "English")
Translation target language. Set to any language name to override the default. Used by translate and sync operations.
例: $DocTranslationLanguage = "French"

## Palette Buttons (invoked via ShowDocPalette[])

The palette provides these actions on the selected cell(s):
- **Expand** — calls DocExpandIdea on selected cell(s); chains asynchronously for multi-selection
- **Translate** — translates cell text; auto-detects source language; result stored in TaggingRules
- **Sync** — re-generates dependent components from the currently displayed text (idea → re-expand paragraph; paragraph → re-translate; translation → reverse-sync paragraph)
- **Toggle** — calls DocToggleView on selected cell
- **Note** — calls DocInsertNote
- **All Prompts** — bulk-switches all documentation cells to idea (prompt) view
- **All Paragraphs** — bulk-switches all documentation cells to paragraph view
- **All Translations** — bulk-switches all documentation cells to translation view
- **Export MD** — calls DocExportMarkdown
- **Export LaTeX** — calls DocExportLaTeX

## Cell Modes (TaggingRules metadata)

TaggingRules key root: `"documentation"`. Mode values stored at `{"documentation","mode"}`:
- `"idea"` — prompt/idea text shown (amber left border)
- `"paragraph"` — expanded paragraph shown (green left border)
- `"translated"` — cell has a stored translation; original text currently shown (light-blue left border)
- `showTranslation=True` + mode `"paragraph"` — translation currently displayed (blue left border)

## Export Cell Style Mapping

| Cell Style | Markdown | LaTeX |
|---|---|---|
| Title | `# text` | `\title{text}` |
| Chapter | `# text` | `\chapter{text}` |
| Section | `## text` | `\section{text}` |
| Subsection | `### text` | `\subsection{text}` |
| Subsubsection | `#### text` | `\subsubsection{text}` |
| Item | `- text` | `\item text` |
| ItemNumbered | `1. text` | `\item text` |
| Input | ` ```mathematica ... ``` ` | `\begin{lstlisting}[language=Mathematica]...\end{lstlisting}` |
| Output (text) | ` ```...``` ` | `\begin{verbatim}...\end{verbatim}` |
| Output (image) | `![name](file)` | `\includegraphics{file}` |
| DisplayFormula | `$$...$$` | `\[...\]` |
| Note | skipped | skipped |