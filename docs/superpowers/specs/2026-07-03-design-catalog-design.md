# デザインカタログ（コンポーネント語彙・アプリ内ギャラリー・視覚リグレッション）設計

- 日付: 2026-07-03
- 対象: `YoruMimizukuKit`（共有フィクスチャ・余白定数）、macOS / iPadOS アプリ
  （`apps/macos`, `apps/ipados`）のギャラリー UI、新設するアプリ側テストターゲット
- 状態: 設計合意済み（実装計画はこれから）

## 背景と問題

余白やレイアウトの調整を人間と AI エージェントで議論するとき、対象を指す共通の
語彙がない。「いいねやリポストの UI と投稿の隙間」のような自然言語の指示は、どの
View のどの padding を指すのかの解釈が毎回必要で、齟齬の温床になる。また余白の
実値は各 View にマジックナンバー（2 / 3 / 4 / 5 / 6 / 10 …）として散在しており、
同じ意図の余白が別の値になっても気づけない。

さらに、デザインルールを文書化しても、実際の描画と突き合わせて確認する場が
ない。現状 `#Preview` / PreviewProvider は一切なく、コンポーネントを単体で描画
する手段は本物のタイムラインに流れてくるのを待つだけである。2026-07-03 の
「2枚並び画像のオーバーラップ」のような見た目のリグレッションも、目視でしか
発見できない。

## 目標

1. **議論の語彙**: コンポーネントと主要な余白に、コードの識別子と一致する名前を
   与える。「PostRow の `actionBarTopGap` を 6→8 に」で会話が完結する状態。
2. **動く見本**: 本体アプリ内（DEBUG のみ）のギャラリーで、本物の View を固定
   フィクスチャで一覧描画し、密度・テーマ・カラム幅を切り替えて目視確認できる。
3. **視覚リグレッション検出**: 同じフィクスチャをスナップショットテストで描画し、
   参照 PNG との比較で意図しない見た目の変化を検出する。

## 非目標

- 抽象 spacing トークン体系（`spacing.s/m/l`）の導入。定数化は既存値の名前付けに
  とどめ、値の段階整理はしない（将来必要になれば別スペック）。
- Windows のギャラリー / スナップショット。XAML 側は対象外（DesignMetrics の値を
  参照することは妨げない）。
- 寸法線つきの本格的な余白ビジュアライザ。初版は定数名ラベルの注記まで。
- CI での自動実行。スナップショットはローカル実行のみ（CI 基盤は別件）。

## 決定ログ（2026-07-03 ブレインストーミング）

- 主目的は視覚リグレッション検出まで含む（語彙・目視・回帰の3点セット）
- ギャラリーは**本体アプリ内の隠しギャラリー**（別アプリ・静的 PNG ギャラリー案は不採用）
- 命名は**コンポーネント名 + 余白定数名**（トークン方式は過剰として不採用）
- 対象は **macOS + iPadOS 同時**
- スナップショットは **swift-snapshot-testing**（Point-Free）を導入。自前実装は
  許容誤差・差分可視化・record フローの作り込みコストが見合わず不採用
- フィクスチャは **Kit で共有**（案A）。プラットフォーム別フィクスチャは見本の
  乖離を招くため不採用

## アーキテクチャ

```
core/Sources/YoruMimizukuKit/
├── DesignMetrics.swift        # 命名済み余白・角丸定数（プラットフォーム中立）
└── Catalog/
    ├── CatalogFixtures.swift  # 決定的な PostDisplay 等のサンプル集
    ├── CatalogVariant.swift   # 見本一覧の列挙（ID: "PostRow/two-images" 等）
    └── Resources/             # サンプル画像（SPM resources、file:// で参照）

apps/macos/Catalog/            # DEBUG のみビルド対象
└── DesignCatalogView.swift    # ギャラリーウィンドウ（メニュー: ヘルプ > デザインカタログ）

apps/ipados/Catalog/           # DEBUG のみ。設定画面末尾の隠し項目から開く

テスト（新設）:
├── YoruMimizukuTests          # macOS アプリのテストターゲット
└── YoruMimizukuPadTests       # iPadOS アプリのテストターゲット（シミュレータ実行）
    └── swift-snapshot-testing はテストターゲットのみに依存追加（本体にはリンクしない）
```

設計原則は次の3点。

1. **フィクスチャと見本一覧は Kit、View の組み立ては各アプリ。** macOS と iPadOS の
   `PostRowView` は別実装なので「フィクスチャ→View」のレジストリは各アプリが持つが、
   「どの見本が存在すべきか」は Kit の `CatalogVariant` が単一の正。スナップショット
   テストがレジストリと `CatalogVariant.allCases` を突き合わせ、見本の取りこぼしを
   検出する。
2. **画像の決定性はバンドルリソースで担保。** 小さなサンプル画像を Kit のリソースに
   持ち、フィクスチャは `file://` URL で参照する。`ImageDownsampler` が file URL を
   そのまま読めることを実装プランの最初で検証し、読めない場合はローダ注入
   （`RemoteImage` に環境経由でローダを差し替える口を開ける）に切り替える。
3. **ギャラリーとテストは同じレジストリを回す。** ギャラリーに見本を追加すれば
   スナップショット対象にも自動で入る。

## 命名規約

**コンポーネント名**は Swift 型名から `View` を落としたものを正とする
（`PostRowView` →「PostRow」）。内部の部位は既存の computed property 名
（`authorLine` / `bodyText` / `mediaSection` / `actionBar` / `quoteSection`）を
そのまま語彙にする。新しい名前体系は発明しない。見本 ID は
「コンポーネント名/バリアント名」（例: `PostRow/two-images`）。

**余白定数（DesignMetrics）**は `<場所><役割>` 形式で命名する。

```swift
public enum DesignMetrics {
    /// 本文/メディアとアクションバーの間
    public static let actionBarTopGap: CGFloat = 6
    /// 本文とメディアの間
    public static let mediaTopGap: CGFloat = 3
    /// 画像グリッドのタイル間
    public static let gridGutter: CGFloat = 5
    /// サムネイル・カード類の角丸
    public static let thumbnailCornerRadius: CGFloat = 10
    /// 密度依存の値は関数にする
    public static func bodyStackSpacing(_ density: DisplayDensity) -> CGFloat
}
```

- 導入時は**既存のマジックナンバーを値を変えずに定数化するだけ**とし、見た目の
  変化を伴わない純粋な構造的変更としてコミットを分離する。
- 名前を付けるのは「議論・再利用される余白」に限る。一度きりの装飾的 padding は
  網羅しない。
- 語彙の一覧は wiki の `design-system.md`（本スペックから導出）に載せ、ギャラリー
  でも各見本に使用定数名を注記する。

## ギャラリー

**macOS**: `#if DEBUG` でメニュー「ヘルプ > デザインカタログ」を追加し、専用
ウィンドウを開く。左サイドバーにコンポーネント一覧、右に選択コンポーネントの
全バリアントを縦に並べ、各見本に「バリアント名 + 使用 DesignMetrics 定数名」の
キャプションを付ける。ツールバーに検査用コントロールを3つ置く。

1. **密度 A/B とテーマの切替** — カタログ専用の `ThemeStore` /
   `DisplaySettingsStore` インスタンスを注入し、本体設定に影響させない
2. **カラム幅スライダー** — PostRow の 680pt リフロー境界をまたいで動かし、
   縦積み⇔本文左/メディア右の切り替わりを目視できる幅依存問題の再現装置
3. **余白注記トグル** — ON で余白部分に定数名と値のラベルを重ねる（初版は
   ラベルのみ。寸法線は必要になってから）

**iPadOS**: サイドバー末尾に DEBUG のみ表示の「デザインカタログ」行を置き、
タップでシート表示する（設定画面は未実装のため。設定画面が入ったら移設して
よい）。

ギャラリーが描画するのは**本物の View**（PostRowView 等）であり、カタログ用の
複製は作らない。見本の追加は「Kit の `CatalogVariant` に1ケース + 各アプリの
レジストリに1行」で完了する。

初版の見本セット（`CatalogVariant`）: PostRow の標準 / 画像1枚（縦長クロップ）/
画像2枚 / 画像4枚 / 引用 / 動画ポスター / リンクカード / NSFW ぼかし / 長文、
ActionBar 単体、QuoteCard、LinkCard、VideoPoster、Toast。各バリアントは対応
プラットフォームを宣言でき（例: Toast は現状 macOS のみ）、網羅一致テストは
宣言されたプラットフォームに対してのみ照合する。

## スナップショット運用

- 各アプリのテストターゲットでレジストリを全件ループし、
  `assertSnapshot(of:as: .image(perceptualPrecision: 0.98))` で比較する。
  参照 PNG は `__Snapshots__/` として git 管理する。リポジトリは公開予定のため、
  フィクスチャの文言・画像は公開して問題ない内容だけを使う。
- 実行はローカルのみ。`xcodebuild test -scheme YoruMimizuku` に統合し、iPad 側は
  シミュレータ destination で実行する。`cd core && swift test` の日常フローには
  影響しない。
- 参照画像の更新は record モードで行い、更新 PNG は通常のコミットとしてレビュー
  する（git の画像 diff で意図した変化かを確認）。
- OS 更新等でフォントレンダリングが変わり一斉に落ちた場合は、目視確認のうえ
  一括 record する。この判断はリリース作業と独立。

## テスト戦略

- `CatalogVariant.allCases` とアプリ側レジストリの網羅一致はユニットテストで検証
  （スナップショット以前の取りこぼし検出）。
- `DesignMetrics` の定数化リファクタは既存のコアテスト（456件）が緑のまま通る
  ことを確認（値を変えないため）。
- スナップショットの初回 record を「参照の基準」としてコミットし、以後の PR は
  差分の有無で見た目の変化を可視化する。

## 段階導入

1. **Phase 1**: `DesignMetrics` 定数化（値変更なし・構造的変更のみ）+ wiki
   `design-system.md` 新設
2. **Phase 2**: Kit の `CatalogFixtures` / `CatalogVariant` + サンプル画像リソース
   + file URL 読み込みの検証
3. **Phase 3**: macOS ギャラリー（ウィンドウ・サイドバー・3コントロール・注記）
4. **Phase 4**: iPadOS ギャラリー
5. **Phase 5**: スナップショットテスト2ターゲット新設 + 初回 record

## 未確定事項（実装着手時に確定）

- `ImageDownsampler` が file:// URL を読めるか（読めない場合はローダ注入に切替）
- iPad テストターゲットが使うシミュレータの機種・OS の固定値（参照画像の安定性
  に直結するため、record 環境を1つに固定する）
- 余白注記ラベルの実装方式（overlay + anchorPreference か、単純なキャプション併記か）
- `swift-snapshot-testing` のバージョンピン
