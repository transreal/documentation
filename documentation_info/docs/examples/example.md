# 使用例集 — Documentation

## 例 1: パレットを開く

```mathematica
ShowDocPalette[]
```

> ドキュメント作成用パレットが画面に表示されます。

---

## 例 2: アイデアをパラグラフに展開する

```mathematica
nb = EvaluationNotebook[];
DocExpandIdea[nb, 2]
```

> セル 2 のアイデアテキストが LLM によって文章品質のパラグラフに書き換えられます。

---

## 例 3: 展開済みパラグラフをアイデア表示に戻す（トグル）

```mathematica
nb = EvaluationNotebook[];
DocToggleView[nb, 2]
```

> セル 2 がパラグラフ表示中であればアイデア表示に、アイデア表示中であればパラグラフ表示に切り替わります。

---

## 例 4: 選択中のセルに対して展開を実行する

```mathematica
nb  = EvaluationNotebook[];
idx = First @ Cells[nb, CellStyle -> "Text"];
DocExpandIdea[nb, idx]
```

> ノートブック内の最初の Text セルを取得し、そのセルのアイデアをパラグラフに展開します。

---

## 例 5: 翻訳先言語を変更してから展開する

```mathematica
$DocTranslationLanguage = "English";
DocExpandIdea[EvaluationNotebook[], 5]
```

> セル 5 を展開後、翻訳機能が呼ばれた際に英語への翻訳が行われます。

---

## 例 6: フランス語への翻訳を設定する

```mathematica
$DocTranslationLanguage = "French"
```

> 翻訳先が French に設定されます。以後、翻訳トグルを実行するとフランス語訳が表示されます。

---

## 例 7: 複数セルを順番に展開する

```mathematica
nb   = EvaluationNotebook[];
idxs = {3, 5, 7};
Scan[DocExpandIdea[nb, #] &, idxs]
```

> セル 3、5、7 を順番に LLM でパラグラフ展開します。

---

## 例 8: すべてのアイデアセルをパラグラフ表示に揃える

```mathematica
nb   = EvaluationNotebook[];
idxs = Range[Length @ Cells[nb]];
Scan[DocExpandIdea[nb, #] &, idxs]
```

> ノートブック内の全セルに対してパラグラフ展開を試みます（アイデアが未入力のセルはスキップされます）。