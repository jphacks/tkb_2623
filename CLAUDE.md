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
