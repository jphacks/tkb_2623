# GourmetShareMap 開発ルール

## ブランチ運用

- このアプリの開発を行う際は、必ず `main` から作業用ブランチを切ってから作業する。`main` 上で直接コードを変更しない。
- `main` へ直接マージしない。作業が完了したら必ず Pull Request を作成し、レビューを経て PR 経由でマージする。

## Worktree運用(複数Agent並行開発)

このアプリの開発タスクを受けたら、ファイルを編集する前に必ず以下を自動的に行う(ユーザーに確認を取らずに進めてよい):

1. タスク内容からブランチ名を決める。`feature/<タスクを表す具体的な英語スラッグ>`とし、`git worktree list` / `git branch -a` で既存ブランチと衝突していないか確認する。
2. `EnterWorktree` で `origin/main` から新規Worktreeを作成する。
3. Worktreeに入ったら、`.gitignore` 対象のSupabase秘密情報をメインの作業ツリーからコピーする:
   ```bash
   MAIN_WORKTREE=$(git worktree list --porcelain | awk '/^worktree /{print $2; exit}')
   cp "$MAIN_WORKTREE/GourmetShareMap/Supabase/SupabaseConfig.swift" \
      GourmetShareMap/Supabase/SupabaseConfig.swift
   ```
4. 実装が完了したら `open <worktreeパス>/GourmetShareMap.xcodeproj` でXcodeを開き、開発者に▶ボタンで動作確認してもらう。
5. 開発者からOKが出たら、ブランチのpushとPR作成について確認を取ってから実行する。
6. PRがマージされたら、該当Worktreeを削除する(`ExitWorktree({ action: "remove" })`)。

### DerivedDataはWorktree間で共有する(xcodebuild実行時は必須)

Supabase SDKはswift-crypto(BoringSSLを含む)など重いSPM依存を抱えており、Worktreeごとに独立したDerivedDataでビルドすると、新しいWorktreeの初回ビルドで毎回これらをフルビルドし直し数分かかる。これを避けるため、Worktree内で `xcodebuild` を実行する際は必ず固定の共有パスを明示指定する:

```bash
xcodebuild build -project GourmetShareMap.xcodeproj -scheme GourmetShareMap \
  -destination 'platform=iOS Simulator,name=<シミュレータ名>' \
  -derivedDataPath ~/Library/Developer/Xcode/DerivedData/GourmetShareMap-Shared
```

**検証済みの効果:** このパスを固定して複数Worktreeから使うと、Supabase/swift-crypto等の依存のコンパイル結果が再利用され、新しいWorktreeでの初回ビルドが約2分→約1分に短縮される(実測)。Worktree内の相対パス(例: `DerivedData`)など、Worktreeごとに異なるパスを `-derivedDataPath` に指定しないこと。

**既知の制限:** `GourmetShareMap.xcodeproj/project.xcworkspace/xcshareddata/WorkspaceSettings.xcsettings` にも同じ共有パスを設定してあるが、これは `xcodebuild` コマンドラインからは無視されることを確認済み(Appleの既知の制限)。Xcode GUIの▶ボタンでの動作確認では、この設定が効くかはWorktreeごとに保証されない。開発者がXcodeの▶ボタンでも初回ビルドを速くしたい場合は、Xcodeで `File > Workspace Settings...` を開き、Derived Dataの場所を上記と同じ絶対パスに手動で揃えることで同様の効果が期待できる(未検証)。

## 実装方針

- 実装に使用するライブラリ・API・フレームワークは、できるだけ最新の実装・最新バージョンを採用する。非推奨 (deprecated) な方法は避ける。
- 実装方法に迷った場合は、思い込みで進めず、公式ドキュメントやコミュニティの Best Practice を調査してから実装する。
- 実装すべき仕様・要件そのものが曖昧な場合(「何を作るべきか」が決められない場合)は、憶測で決めずに開発者に確認して擦り合わせる。

## タスク分解・実装フロー(PM / Dev Agent)

まとまった機能要望は `/build "<機能要望>"` で進める。

- `pm` エージェント(`.claude/agents/pm.md`)が機能要望をPRサイズのタスクに分解する。
- タスクごとに `dev` エージェント(`.claude/agents/dev.md`)が上記のWorktree運用に従って実装し、仕様が曖昧な点があれば憶測せず開発者に確認する。
- オーケストレーター役(呼び出し元のClaude)が、開発者への質問の取り次ぎ・Xcodeでの動作確認依頼・push/PR実行の確認・PRマージ後のWorktree削除を1タスクずつ仲介する。
- 詳細な手順は `.claude/commands/build.md` を参照。
