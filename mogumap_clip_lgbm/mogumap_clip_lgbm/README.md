# MoguMap CLIP + LightGBM 最小実装

目的：ローカルPythonでダミーデータを生成し、CLIPの事前学習画像特徴量とLightGBMでユーザーの店舗総合評価（1〜5）を学習・予測。FastAPIから学習と推論を呼び出せるようにする。

**注意：ダミー画像は図形、評価は人工生成です。実際の嗜好予測精度は確認できません。** CLIPの重みは初回実行時にHugging Faceからダウンロードされます。GPUは不要ですがCPUだと遅くなります。

## この環境でのセットアップ（Ubuntu / Bash）

確認した環境は Ubuntu 24.04（Linux x86_64）、Bash、Python 3.12.3 です。以下のコマンドはこの環境のターミナルで実行します。

このPython APIは `GourmetShareMap/` のiOSアプリとは別プロセスです。ここでのダミーデータ検証にSupabaseの設定やXcodeは不要です。

### 1. 作業ディレクトリと仮想環境

リポジトリ内に同名ディレクトリが2階層あるため、`requirements.txt` と `api.py` がある内側へ移動します。

```bash
cd /home/user/projects/tkb_2623/mogumap_clip_lgbm/mogumap_clip_lgbm
python3 --version
python3 -m venv venv
source venv/bin/activate
python -m pip install --upgrade pip
python -m pip install -r requirements.txt
python -m pip check
```

仮想環境名は、このリポジトリの `.gitignore` に登録済みの `venv/` を使用します。システムのPythonには直接インストールせず、以降は仮想環境内の `python` を使います。新しいターミナルでは、このディレクトリへ移動して `source venv/bin/activate` を再実行してください。

依存パッケージの導入と初回のCLIPモデル取得には外部ネットワークへの接続が必要です。この環境で通信が制限されている場合は、接続可能な環境でパッケージとモデルを用意してください。`requirements.txt` はバージョン範囲指定のため、導入時期によって解決されるバージョンが変わります。

### 2. ローカルで学習・推論を確認

```bash
export CLIP_DEVICE=cpu
python generate_demo.py
python test_local.py
```

- `generate_demo.py` は48枚の人工画像と384件の評価を生成し、既存の `data/images/`、`data/places.json`、`data/train.json` のデモファイルを上書きします。同梱のデモデータを使う場合は省略できます。
- `test_local.py` は学習結果を `TRAIN:`、候補5店舗の予測を `PREDICT:` として出力します。
- 学習モデルは、このディレクトリの `artifacts/model.joblib` に保存・上書きされます。このファイルは現在の `.gitignore` の対象外です。コミット対象に含めないでください。
- CLIPは既定でCPUを使用します。初回はモデルのダウンロードと画像特徴量の計算に時間がかかります。

## APIサーバ起動・確認

セットアップ済みの仮想環境を有効化したターミナルで起動します。

```bash
cd /home/user/projects/tkb_2623/mogumap_clip_lgbm/mogumap_clip_lgbm
source venv/bin/activate
export CLIP_DEVICE=cpu
export MOGUMAP_API_KEY="dev-only-change-me"
python -m uvicorn api:app --host 127.0.0.1 --port 8000
```

別ターミナルで同じディレクトリと仮想環境を使い、サーバと同じAPIキーを設定して実行します。

```bash
cd /home/user/projects/tkb_2623/mogumap_clip_lgbm/mogumap_clip_lgbm
source venv/bin/activate
export MOGUMAP_API_KEY="dev-only-change-me"
python test_api.py
```

`test_api.py` は `/train` で再学習してモデルを上書きし、続いて `/predict` で候補5店舗の予測を取得します。学習成功時には `trained_records: 384`、`users: 12` が返ります。サーバは `Ctrl+C` で停止できます。

`127.0.0.1:8000` はAPIを起動した環境内の接続先です。別ホストのiOS端末から使う際は、バックエンドへの接続経路を別途設定する必要があります。

APIドキュメント： http://127.0.0.1:8000/docs

- GET `/health`：認証不要。`{"status":"ok","trained":false}` などを返す。`trained` はモデルファイルの有無を示し、初回学習後は `true`
- POST `/train`：`{"records": [rating_record, ...]}`。認証ヘッダ `X-API-Key`
- POST `/predict`：`{"history": [rating_record, ...], "candidates": [place_record, ...]}`。認証ヘッダ `X-API-Key`
- 返却値例：`{"predictions": [{"place_id":"demo_001","predicted_rating":3.42}]}`

## 入力形式

店舗候補の例：

```json
{
  "place_id": "store123",
  "image_id": "store123-photo1",
  "image_path": "data/images/store123.png",
  "category": "ramen",
  "price_level": 2,
  "google_rating": 4.2,
  "review_count": 155
}
```

評価履歴・学習用レコードには追加で `user_id`、`rating` (1〜5)、`rated_at` (ISO8601、同一タイムゾーンに統一) を付ける。

`image_path` はAPIサーバ上のローカルファイル向けで、相対パスは `ml.py` のあるディレクトリを基準に解決します。**Swiftアプリからは `image_base64` で画像データを送信**する。`image_id` は同じ画像を一意に指すIDとし、同一リクエスト中で再利用する。

- `category`: `japanese`, `italian`, `ramen`, `cafe`, `chinese`, `other` のいずれか（MoguMapのカテゴリ体系に合わせて変更）
- `price_level`: 1〜4を想定。欠損時はアプリ側で補完
- `google_rating`: Googleの公開平均★。`rating`とは異なる
- `review_count`: 店舗の公開レビュー件数
- `image_base64` はデコード後に最大5MB/枚（API全体の総量制限、レート制限は未実装）

## 学習・推論の仕組み

- CLIP: `sentence-transformers/clip-ViT-B-32`（凍結・特徴量抽出のみ）
- LightGBM: `LGBMRegressor`。モデルを `artifacts/model.joblib` に保存
- 個人嗜好特徴：当該ユーザーの過去平均★、ジャンル別平均★、高評価／低評価画像と候補のCLIPコサイン類似度
- 学習時は各ユーザーの `rated_at` より前の評価だけで履歴特徴量を作成。自分の正解ラベルが入らないようにする
- 推論時はSwiftから渡された履歴（評価済み店舗）と候補店舗を使用
- 推論結果は1〜5にクリップした連続値。整数の星分類ではない

## 実データに置き換える際

1. Supabaseからユーザー評価と対象店舗情報を取得
2. 利用許諾のある写真を紐付ける（Google Maps写真については契約・利用規約を確認）
3. `data/train.json` と同じスキーマで`/train`へ渡す
4. `/predict`へ当該ユーザーの履歴と候補店舗を渡す
5. 定期再学習・画像特徴キャッシュ・Supabase Storageへの保存・十分なデータ量になった後の精度評価を追加

**API公開時の注意**：現状はローカル開発用です。`/train`は高コストかつ学習モデルを書き換えます。インターネット公開前にHTTPS、認証・認可、アップロード容量制限、レート制限、バックグラウンドジョブ・ジョブ状態管理、モデル更新の原子的切替、実行ログを追加。APIキーをiOSアプリ内に埋め込まないでください。Swiftからは認証済みバックエンド経由で呼び出す設計を推奨します。

ローカル `image_path` はPC側だけで通用します。アプリとPCが異なるホストの場合は画像本体を送信するか、サーバ側の認証済みストレージから取り出す必要があります。
