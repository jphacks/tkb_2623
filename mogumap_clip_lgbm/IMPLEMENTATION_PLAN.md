# バックエンド推薦切り替え・GCP自動学習

更新日: 2026-10-25。ユーザーによる最新の指定に合わせ、当初の20／21件境界を6件へ変更した。

## 確定仕様

- 有効記録0〜5件はGemini、6件以上は利用可能な本人のLightGBMモデルを使用する。
- 初回学習は6件以上。初回モデルが使えない間はGeminiを継続する。
- 以降は前回成功した学習に未包含の店舗IDが5件以上追加されるごとに全履歴で再学習。
- 学習中・失敗時に前回成功したモデルを維持する。
- iOSの画面は変更しない。0〜4件で推薦画面を出さない既存UIも維持する。
- 手動学習は開発者CLIとCloud Run Jobだけに用意し、既定では本番に公開しない。

## 実装と検証の対応

| 項目 | 対応 |
|---|---|
| 推薦経路から学習を除去 | `api.py`。Gemini／LightGBMの切り替え、互換応答、モデル破損時の修復予約 |
| 候補だけを使うGemini推薦 | `recommend.py`。JSON選択とID・評価範囲検証、不要な候補写真取得を省略 |
| 件数・画像検証の共通化 | `policy.py`, `history.py`, `repository.py` |
| 永続ジョブと排他 | `20261025120000_ai_background_training.sql`。DBトリガー、変更版、リース、公開時のジョブID照合 |
| 自動実行 | `training_worker.py`。再試行・時間予算・学習済みID集合・変更中の通知保持 |
| モデル公開 | 世代別GCS保存後、DBで公開先と学習指標を原子的に変更 |
| 手動テスト | `train_cli.py`。dry-run、隔離ローカル出力、GCS manual-tests、明示的publish |
| GCP設定 | `deploy/`。Service、自動Job、手動Job、Scheduler、サービスアカウント・IAMのスクリプト |
| テスト | `tests/test_backend.py`, `supabase/tests/ai_training.sql` と一時DB実行スクリプト |

## 導入手順

1. Pythonのユニットテストと一時DBでマイグレーションを検証。
2. 非公開CLIで実際のCLIP・LightGBM学習を確認。
3. Supabaseへ追加マイグレーションを適用。
4. GCPのIAM・Secret参照とコンテナを準備してService／Jobをデプロイ。
5. Edge Functionを更新。
6. 手動検証Job、自動Jobの単発実行、公開世代と推薦切り替えを確認。
7. Schedulerを有効にする。最初は5分間隔とし、完了までの時間保証は設けない。

編集・削除の即時再学習、CLIP埋め込みの永続キャッシュ、即時WebhookによるJob起動、旧モデル世代の自動削除は今後の改善対象。GCP実反映・本番DB変更はコードのローカル検証とは分けて記録する。
