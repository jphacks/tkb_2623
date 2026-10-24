GourmetShareMap/
├── App/
│   ├── GourmetShareMapApp.swift
│   ├── RootView.swift                  // 未ログイン→01 / 初回→初回登録 / 通常→MainTabView
│   ├── MainTabView.swift               // フッター（マップ・登録・プロフィール）
│   ├── AppTab.swift
│   └── AppRouter.swift                 // 選択中タブ、マップの表示対象（07→02）
│
├── Core/                               // 共通で実装する処理
│   ├── essionStore.swift             　// 認証管理：ログイン状態・ユーザーID
│   ├── RecordStore.swift              // 画面間データ連携：保存後に全画面へ反映
│   └── AppColor.swift                 // 配色
│
├── Features/
│   ├── Auth/                           // 01 ログイン画面
│   │   ├── Views/
│   │   │   ├── LoginView.swift         // Appleでサインイン
│   │   │   └── OnboardingView.swift    // 初回のみ：ユーザー情報の登録
│   │   └── ViewModels/
│   │       └── AuthViewModel.swift
│   │
│   ├── Map/                            // 02　マップ
│   │   ├── Views/
│   │   │   └── MapScreen.swift
│   │   ├── ViewModels/
│   │   │   └── MapViewModel.swift
│   │   └── Components/
│   │       ├── 
│   │
│   ├── Record/                         // 03/05 登録・編集
│   │   ├── Views/
│   │   │   ├── RecordCreateView.swift  // 03
│   │   │   └── RecordEditView.swift    // 05（リピート回数・削除含む）
│   │   ├── ViewModels/
│   │   │   ├── RecordCreateViewModel.swift
│   │   │   └── RecordEditViewModel.swift
│   │   └── Components/
│   │       ├── PhotoGridEditor.swift   // 写真の追加・変更・削除・表紙
│   │       ├── PhotoSourceMenu.swift   // カメラ／写真を選択
│   │
│   ├── Profile/                        // 04/06-a プロファイル
│   │   ├── Views/
│   │   │   ├── ProfileView.swift
│   │   │   └── ProfileEditView.swift
│   │   └── ViewModels/
│   │       ├── ProfileViewModel.swift
│   │       └── ProfileEditViewModel.swift
│   │
│   └── Friend/                         // 06-b/07 フレンド
│       ├── Views/
│       │   ├── FriendListView.swift
│       │   └── FriendProfileView.swift
│       ├── ViewModels/
│       │   ├── FriendListViewModel.swift
│       │   └── FriendProfileViewModel.swift
│       └── Components/
│           ├── UserSearchBar.swift     // ユーザーIDで検索・追加
│           └── FriendRow.swift
│
├── Shared/
│   └── Components/                     // 複数の機能で使う部品
│       │──　ErrorView.swift
│       └──
│
├── Models/
│   ├── AppUser.swift                   // user
│   ├── StoreRecord.swift               // store（ユーザーごとの訪問記録）
│   ├── RecordImage.swift               // image
│   ├── Friendship.swift                // friend
│
├── Repositories/                       // データの取得・保存の窓口（ViewModelから呼ぶ）
│   ├── AuthRepository.swift            // Appleサインイン→Supabase認証
│   ├── UserRepository.swift            // ユーザー取得・登録・更新・検索
│   ├── RecordRepository.swift          // 店舗記録の取得・登録・更新・削除
│   ├── FriendRepository.swift          // フレンド関係の登録・取得
│   └── ImageRepository.swift           // Storageへのアップロード・取得・削除
│
├── Supabase/                           // 接続の準備だけ（Notion手順書のパスを維持）
│   ├── SupabaseConfig.swift.example
│   ├── SupabaseConfig.swift            // .gitignore 済み
│
├── Services/                           // 端末の機能と外部API
│   ├── Places/
│   │   ├── PlacesConfig.swift.example
│   │   ├── PlacesConfig.swift          // .gitignore に追加
│   │   └── PlacesClient.swift          // Nearby Search
│   ├── LocationService.swift           // Core Locationで現在地
│   └── PhotoLocationReader.swift       // 撮影位置の取得
│
├── Mock/
│   └── MockData.swift                  // プレビュー・デモ用
│
└── Resources/
└── Assets.xcassets