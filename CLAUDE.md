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
