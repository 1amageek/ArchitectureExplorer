# ArchitectureExplorer — 外部拡張契約

**追加仕様バージョン：1.3 / Extension API：1.0（開発中draft）**
**作成日：2026-11-16**
**改訂日：2026-11-17**
**状態：開発中。実装と受け入れ証拠はPROGRESS.mdとEXTENSIONS-VERIFICATION.mdを参照。**
**適用先：ArchitectureExplorer-SPEC.md v1.0**

> ArchitectureExplorerは構造探索の基盤であり、検証を統括しない。外部パッケージが同じ構造情報・入力世代・GUIを利用するための、型付き・権限付きの拡張契約を提供する。

## 0. この追補の位置付け

既存仕様の§2（責務）、§7（IR）、§8（Provider）、§12–13（Query／Events）、§17（Annotation／extensionGraphs）、§20（安全性）を土台とする。既存仕様を全面的に置換しない。重複箇所ではこの追補の具体的な拡張プロトコルを優先し、次の不変条件は維持する。

- ArchitectureExplorer → swift-formalの直接・推移依存を追加しない。
- Explorerの解析スケジューラを検証スケジューラへ変更しない。
- 構造の正本を、外部の検出候補・テスト結果・証明結果で上書きしない。
- 検証の実行、再検証、総合判定、ツール導入は上位パッケージの責務。
- ArchitectureIRとFormalIRを統合しない。
- Webは既存の別Swift Package・別プロセス構成を維持する。

今回追加するのは「外部ツールの画面と操作も扱える汎用拡張口」。Explorer自身がTLC／Lean／テスト／Fuzzerを起動する機能ではない。

MUSTは完成条件、SHOULDは理由付きADRで変更できる指針とする。上位の統合検証ツール名はInvar、CLIは`invar`に確定した。ただし、Explorerの汎用APIや実装にInvar専用の依存・分岐を組み込まない。Invarは本契約を利用する一つの外部Providerである。

本追補v1.3は、認可主体・確認token・要求同一性・run公開・digest照合・cancel完了の契約を修正する。Extension API 1.0は開発中draftの対象版であり、v1.2以前の仮実装とのwire互換性を宣言しない。登録時に仕様profile `aex-1.3`を交換し、共通profileがなければ拒否する。既存の公開済みschema majorを変更せず、公開前にSDK・schema・受け入れ試験をこのprofileで一致させる。公開後の必須意味の変更は§4のmajor更新規則に従う。

Invar側の要求は同梱の`Invar-SPEC.md` v0.2と`Invar-AGENT-HANDOFF.md`を参照する。本追補を参照する利用者も対応profileを明示し、名称だけで互換済みと扱わない。

## 1. ソースに基づく既存契約と新しい設計判断

| 区分 | 内容 |
|---|---|
| 既存仕様 | §17にAnnotation、extensionGraphs、入力適用状態、Provider別namespaceがある |
| 既存仕様 | §12–13にsnapshot固定Query、変更通知、再同期がある |
| 既存仕様 | §8に言語・振る舞いProviderの能力宣言と解析契約がある |
| 新規要求 | 拡張の登録・互換性交渉・権限・切断・無効化を規定する |
| 新規要求 | Inspector、overlay、部分graph、table、timeline等の宣言的表示を登録できる |
| 新規要求 | UI操作を、起動済みの認可された外部Providerへ型付きintentとして転送できる |
| 新規要求 | 上位ツールが固定入力を取得するためのlease・InputManifest契約を補足する |

「仕様にある」は「実装済み」と同義ではない。P0で公開APIの実在と試験結果を確認する。

## 2. 依存方向と実行責任

```text
上位検証パッケージ
    ├── ArchitectureExplorerのClient / Extensions API
    └── swift-formal、Test Backend、Fuzz Backend等

ArchitectureExplorer
    ├── 既存の解析・Store・Query
    ├── Extension Registry / Dispatcher
    └── Webホストの汎用Extension Renderer

Explorerは外部Providerを起動しない。
外部Providerが自ら起動し、ユーザーが許可したセッションとして登録する。
```

UIの操作に対し、Explorerは§5の認可と§7の要求検査を通したActionIntentだけを転送する。Providerは承認済み対象・引数・固定入力・権限の範囲で実行可否と実行方法を決める。対象の入力世代はActionIntentに固定し、Providerが別世代へ変更しない。Explorerはジョブの優先順位・再実行・プロセス管理を代行しない。

外部Providerが停止していても構造探索は継続する。関連ボタンは「Provider未接続」として無効化する。クリックを契機に未知の実行ファイルを起動してはいけない。

## 3. 提供する拡張点

| 拡張点 | 外部ツールができること | Explorerが守る境界 |
|---|---|---|
| Query | snapshotに固定した部分graph・根拠・能力の取得 | 既存の予算・pagination・coverageを維持 |
| Change Subscription | 入力無効化・構造更新の購読 | 欠落時は再同期。検証要否は決めない |
| Annotation | 指摘、外部状態、前提、証跡への参照を登録 | Provider状態と入力適用状態を分離 |
| Extension Graph | 反例、実行トレース、証明依存等を表示 | core graphを変更しない |
| View Contribution | タブ、overlay、table、Inspector section、timelineを登録 | v1は宣言的データのみ |
| Action Contribution | 再検査、再生、キャンセル等の操作を登録 | shellを実行せず、型付きintentを外部へ転送 |
| Input Snapshot Lease | InputManifest・許可された入力範囲を取得 | 読み取り専用、digestと世代の不一致を検出 |

言語Provider追加は既存のArchitectureFrontend契約を利用する。今回のExtension APIを任意のネイティブコード・ブラウザコードのローダーにしない。新言語の解析能力と、結果表示拡張の互換性は別に管理する。

## 4. ライブラリとスキーマ

Headless Packageに`ArchitectureExtensions`を公開する。ExtensionManifest、Permission、ActionIntent、Contribution、Registration、Annotationの参照型等を所有する。依存はArchitectureCore／ArchitectureIRまでとし、swift-web／swift-formalをimportしない。

Registry、権限、購読、transactionはArchitectureServiceが合成する。ArchitectureClientが型付きクライアントAPIを提供する。Web Rendererは汎用の転送型だけを利用し、Provider固有のSwift型を要求しない。

Schemasに以下を追加する。

```text
extension-manifest.schema.json
extension-registration.schema.json
extension-action.schema.json
extension-view.schema.json
extension-publication.schema.json
input-manifest.schema.json
input-lease.schema.json
```

開発中は現行契約だけを実装し、旧schema・API・保存形式の互換層を残さない。不要になった型・分岐・保存経路は削除し、呼び出し元・schema・試験を同時に更新する。公開後に必須意味を変更する場合はmajorを上げる。ホスト版、IR版、Extension API版、Provider版を混同しない。

## 5. 登録と互換性

### 5.1 Manifest概念例

以下は新規契約の例であり、既存APIや実装済み機能の説明ではない。

```json
{
  "schemaVersion": "1.0",
  "extensionID": "local.example.verifier",
  "displayName": "Verification",
  "version": "0.1.0",
  "extensionAPI": { "major": 1, "minimumMinor": 0 },
  "architectureIRMajors": [1],
  "specificationProfiles": ["aex-1.3"],
  "requestedPermissions": [
    "graph.read",
    "events.subscribe",
    "annotations.write.own",
    "extensionGraphs.write.own",
    "views.write.own",
    "runs.write.own",
    "actions.receive"
  ],
  "views": [
    { "id": "findings", "kind": "table", "title": "検出結果" },
    { "id": "risk", "kind": "overlay", "title": "調査候補" }
  ],
  "actions": [
    {
      "id": "verify-selection",
      "title": "選択範囲を検証",
      "effect": "externalExecution",
      "requiresConfirmation": true,
      "inputSchemaID": "verify-selection.v1"
    }
  ]
}
```

Manifestに実行コマンド、shell、任意URL、任意JSを記載できない。入力schemaは登録時に有界なJSON Schema部分集合で検査する。schemaに従うことは実行権限を与えない。

### 5.2 接続

ユーザーが承認したローカル接続で認証し、API major、対応schema、要求権限と付与権限を交渉する。登録はworkspace・Provider identity・セッションへ結び付ける。Providerの自己申告だけで権限を付与しない。

JSON-RPCは既存IPCのframingを踏襲する。ネットワークの任意endpointをworkspace設定だけから登録しない。v1は同一ユーザーのローカル接続のみ。

APIは`extensions.register`、`extensions.list`、`extensions.unregister`を持つ。Providerの版更新・バイナリ変更・要求権限拡大では再確認する。利用するProvider binaryのhashと承認をユーザー設定へ記録するが、hashを正しさの証拠にはしない。

### 5.3 ライフサイクル

`registered → connected → disconnected / disabled → unregistered`を追跡する。切断時は非終端jobの現在状態を`unknown`とし、最後の観測を別に保持する。既に記録した終端状態と過去の結果は、切断だけで失敗・未完了へ変更しない。再接続は認証・付与権限を再検査して新session IDを発行し、旧sessionの全操作を拒否する。Actionの再送・照会は§7.2、公開済みrunの履歴は§8に従う。

### 5.4 認可主体と互換profile

ArchitectureServiceが接続に束縛したprincipalを認可の正本とする。principalはworkspace ID、安定したProvider identity、registration ID、session ID、付与権限revision、許可root／scope、失効状態を持つ。payload中のProvider名・namespace・registration IDをprincipalの代用にしない。同一UID・socketへの接続成功だけではProvider間の認可は成立しない。

登録は、ホストが確認した接続peerとユーザー側に記録した承認対象へ束縛する。申告されたPID・binary path・hashだけを本人確認に使わない。接続とのbindingを立証できない認証方式は拒否し、自己申告へfallbackしない。承認・credential発行・権限変更はホストのユーザー操作／明示policyが所有し、Providerの登録要求から昇格させない。

ホストは認可済み接続へ限定したcredentialを発行し、全request・通知・応答で有効なsessionとpermissionを検査する。別接続のregistration ID、別Providerのnamespace、失効したcredentialは拒否する。`own`の対象はprincipalから決定する。認証・権限・scopeの不一致は副作用を起こす前にtyped errorで失敗させる。

| 操作 | 必要な主体・権限 | 追加の束縛 |
|---|---|---|
| `extensions.register` | ユーザー承認に結び付いたbootstrap接続 | peer・workspace・binary identity・profile。登録成功だけで実行権限は得ない |
| `extensions.list/unregister` | ホストユーザー、または自分の登録に限定した有効なProvider session | 他Providerの管理・権限変更はホストユーザーのみ |
| 構造Query・`inputs.manifest`・`inputs.acquire/renew/release` | `graph.read` | 許可scope。leaseは作成principalとsessionへ束縛する |
| `source.read`・`inputs.read` | `inputs.read` | 許可root／path／範囲。lease readは同じ所有sessionのみ |
| 差分購読 | `events.subscribe` | workspace・scope・再同期契約 |
| `annotations.replaceBatch` | `annotations.write.own` | 自分のnamespace。新profileのrun公開は§8を適用 |
| `extensionGraphs.replace` | `extensionGraphs.write.own` | 自分のnamespace・公開単位 |
| Viewの動的データ更新 | `views.write.own` | 登録済みview IDと公開単位 |
| `runs.begin/prepare/commit/abort`・進捗更新 | `runs.write.own`と、対象Contribution種別ごとの書き込み権限 | §8のslot・run・publication。commit時にも全権限を再検査 |
| Actionのdispatch・確認token発行 | ホストユーザーの操作または明示承認済みpolicy | §7.1。Providerの`actions.receive`では代用しない |
| Actionの受信・receipt／job状態の報告 | `actions.receive` | 自分へdispatchされたrequest・job・session。受信権限はユーザーコード実行許可を意味しない |

permissionは上表の各操作に適用し、旧API名、バッチ、購読、既存socketへの再接続を迂回路にしない。権限失効後の読み書き・新規転送を拒否し、未完のstagingを公開しない。資源解放と必要なcancelはホストが所有者情報に基づいて処理できること。新sessionへ古いleaseやstagingの権限を暗黙移譲しない。

開発中のProvider profileは`aex-1.3`だけとする。`host-user`はホストが所有する認証主体であり、Providerが登録できるprofileではない。互換profile・旧操作のadapter・legacy-slotを提供しない。旧Clientや削除したAPI名は明示的に拒否し、呼び出し元を現行SDKへ更新する。別のprofileやcredentialを補って成功扱いしない。

## 6. View Contribution

v1の表示プリミティブは`text`、`table`、`keyValue`、`artifactList`、`graph`、`timeline`、`overlay`とする。データを宣言し、実際のDOM・style・navigationはホストが構築する。

Inspector、選択範囲の補助タブ、グラフoverlay、結果一覧に配置できる。ノード／edgeへのbindingはEntityID・FactID・snapshot・入力fingerprintで行う。

外部値はplain text。外部HTML／JavaScript／SVG markupを直接挿入しない。表示色だけで証明状態を表さず、Provider名、命題、入力範囲、前提、translation状態、適用状態への詳細を残す。

ユーザーのzoom、layout、選択、既存filterを拡張登録でリセットしない。重い外部graphも部分取得と既存の上限を使う。構造graphと実行graphのedgeを暗黙に結合しない。

## 7. ActionIntent

### 7.1 要求同一性とユーザー承認

ActionIntentは次を持つ。

```text
requestID / registrationID / sessionID / actionID / actionDefinitionDigest
workspaceID / snapshotID / selection / inputManifestDigest
inputSchemaID / typed arguments / effect
requestedAt / deadline / idempotencyKey / requestFingerprint
authorizationToken
```

`requestID`は論理要求のIDとし、再送時に変更しない。JSON-RPCのrequest IDなど配送単位の識別子とは分ける。`actionDefinitionDigest`は承認した登録manifest内の操作定義を固定する。

ホストは型検査後の次の値を、ベース仕様§7.8の正準シリアライズとSHA-256で`requestFingerprint`にする。

| fingerprintに含める値 | 固定する意味 |
|---|---|
| workspace ID・安定したProvider identity・request ID | 実行主体と論理要求 |
| action ID・操作定義digest・input schema ID／版・effect | 操作と引数の意味 |
| snapshot ID・input manifest digest・selection | 対象と固定入力 |
| 型検査済みarguments・deadline | 実行条件と初回受付期限 |

selectionの集合はschemaで定めた安定順に正規化し、順序に意味がある配列は保持する。argumentの省略とdefaultの同一性も登録schemaの規則で決定する。未知の意味を推測して正規化しない。配送用RPC ID、registration／session ID、token、受信時刻はfingerprintへ含めず、接続・承認の検査で別に束縛する。これにより、再接続後も同じ論理要求を識別できる。

`authorizationToken`の発行・検証・消費の正本はホストのAuthorization ownerとする。tokenは推測不能な参照または改ざん検出可能な値とし、fingerprint、registration／session ID、付与権限revision、ホスト認可epoch、有効期限、nonceに束縛する。ホストは承認根拠となったユーザー確認または明示policy ID／revisionを記録し、payloadの自己申告を承認根拠にしない。

ホストは登録時にeffectを検査する。v1で外部Providerへ転送するActionは`externalExecution`として確認済みtokenを要求する。ホスト内で完結する読み取り／navigationはExtension ActionIntentを作らず、通常のホストUI操作として処理する。未知effectや、外部転送を読み取り操作として扱わせる定義は拒否する。Manifestの`requiresConfirmation`はホストpolicyに確認を追加できるが、確認を省略する権限を与えない。

ユーザーが明示承認したpolicyが、Provider・操作定義・引数・対象入力・期限・予算の全条件を満たす要求を許可する場合は、再度のUI確認なしで、その要求のfingerprintに束縛した確認済みtokenを発行できる。policyの範囲を越える要求はホストの確認UIを経る。別snapshotへの承認拡張を推測せず、Providerにtokenの発行や承認判定を委任しない。

登録されたこと、`actions.receive`があること、schemaに適合することは、確認済みtokenの代用にならない。通常の構造QueryやホストUIの読み取りには、この実行用tokenを要求せず、§5.4の認証・permissionを適用する。

初回転送時は、認可主体・現在のpermission・操作定義・schema・fingerprint・token・期限・対象入力をホストが検査する。tokenの消費と転送台帳の予約を不可分に確定してから、宛先Providerへ一度配送する。検査失敗は転送前に拒否する。同じtokenを別の要求へ流用できない。同一要求の再送ではtokenを新しい承認として消費せず、§7.2の台帳を参照する。

確認後に対象コードが変わったら、Providerは`INPUT_CHANGED`を返すか、確認済みsnapshotの入力を取得・照合できる場合だけ、その固定入力を明示して実行する。現在のファイルや別snapshotへ対象を移さない。再接続時は現在の権限と元の承認を再検査して同じfingerprintのtokenを再発行できるが、新しい実行や期限延長の承認へ読み替えない。

```text
User operation / approved policy
    -> Host authorization and fingerprint-bound token
    -> Atomic authorization consumption and dispatch reservation
    -> Provider receipt and job status
    -> Run publication (§8)
```

Providerは不変の`accepted(jobID)`または`rejected(reason)`のreceiptを返す。結果・進捗は同じrequest／job／入力へ束縛する。Explorerは外部jobの実行・優先順位・再実行を所有しない。

### 7.2 再送・障害回復・キャンセル

#### 再送の所有者と寿命

| owner | 保持する状態 | 保証 |
|---|---|---|
| ホストDispatcher | `(workspaceID, Provider identity, idempotencyKey)`に対するfingerprint、承認、配送状態、receipt | 同一要求の再送で新しい転送を起こさない |
| 外部Provider | 同じkeyとfingerprintに対する受付／開始記録、job ID、receipt | 受付記録を永続化してから処理を開始し、同じ要求を別jobとして開始しない |

同じkey・同じfingerprintは初回receiptへ結び付ける。receipt未取得なら既存の配送状態／unknownを返し、accepted／rejectedを捏造しない。同じkeyでaction、引数、選択、入力、期限、request ID等が異なれば`IDEMPOTENCY_CONFLICT`で拒否する。初回receiptと変化するjob状態を分け、再送によってreceiptのjob IDや意味を変更しない。job状態の照会は副作用を持たず、現在の認可を検査する。

ACK喪失・切断・再起動により配送／開始の有無が不明になった要求は`deliveryUnknown`または`unknown`とし、ホストは自動で再配送しない。再接続したProviderの台帳と照合して既存receipt／jobへ復帰する。Providerが台帳を復旧できない場合も、新しいjobとして再実行せず`ACTION_OUTCOME_UNKNOWN`を返す。ホスト再起動では認可epochを更新し、旧epochの要求を新規実行として受け付けない。履歴照会・状態照合と新規実行を区別する。

idempotencyKeyの初回受付期限と台帳保持期限はホストが発行時に固定する。保持期限は初回受付期限より短くしない。受付期限を過ぎた要求を新規実行せず、保持期限後は`IDEMPOTENCY_KEY_EXPIRED`とする。期限／epochの有効性は個別台帳entryの有無とは別に検査し、entry削除後の古いkeyを未使用keyへ戻さない。Providerも同じ期限を検査する。両ownerは登録時に保持可能な件数・期間・進行中件数の予算を宣言し、予算外の新規要求を拒否する。期限内の台帳を追い出して重複排除保証を弱めない。

#### cancelと停止完了

cancelは独立したrequest ID・idempotencyKeyを持つ型付きActionIntentとし、対象の元request ID・job ID・run IDをargumentsへ含めてfingerprintに束縛する。再接続時も元jobを対象とし、別jobへ置き換えない。

| 観測 | Explorerの表示／遷移 |
|---|---|
| 有効なcancelを転送 | `cancelling`。直前のjob状態を保持 |
| Providerがcancelを受理 | `cancelling`を継続。受付は停止完了を意味しない |
| Providerが対象jobの所有処理の停止・後始末完了を報告 | `cancelled` |
| cancel受付前後に通常の完了・失敗が確定 | 報告された`completed`／`failed`。cancel受付だけで書き換えない |
| 受付応答や停止完了通知が来ない、または切断 | `unknown`と最後の観測状態。停止済みと表示しない |
| cancelが拒否され、現在の実行状態が確認できる | 確認できた状態と拒否理由。停止を推測しない |

停止完了は、認証済みProviderによる対象job・run・入力に一致した終端通知で確認する。各jobの状態通知は単調増加するrevisionを持ち、古い／重複通知を再適用しない。終端状態は不可逆とし、競合する終端報告はprotocol errorとして隔離する。`cancelled`はProviderが所有する処理の停止を報告した意味であり、副作用のrollbackや指摘の修正済みを意味しない。ExplorerはProviderのprocessを代わりに管理しない。

### 7.3 MCP

構造情報を読むArchitectureExplorer MCP toolsはread-only。Canvas toolsは共有表示セッションの操作を提供する。検証を実行するMCP toolsは上位ツール側で公開する。汎用`runCommand`や`executeShell`をExplorerに追加しない。

## 8. Annotation・部分graphの更新

### 8.1 runと公開単位

Registry／Storeを合成するArchitectureServiceが、公開順序とtransactionを所有する。これは検証jobのスケジューリングではない。

現在結果のslotを`(workspaceID, Provider identity, logical scope ID, contribution set ID)`で識別する。slotは入力manifestの版を含めず、runごとにsnapshot ID・input manifest digest・scope・run IDを不変に束縛する。`runs.begin`でホストがslot内の単調増加generationとpublication IDを予約し、Storeへ確定してから応答する。Providerは対象runの結果作成を始める前にこの予約を取得し、結果到着時にgenerationを取り直さない。Providerの時計や自己申告generationを順序の正本にしない。

同じProvider・run IDでbeginを再送した場合、slotと入力bindingが同じなら元のgenerationへ結び付け、異なれば拒否する。再接続した所有者が復帰する場合は、権限再検査後に同じgenerationの新しいpublication IDを発行できるが、旧sessionのstagingは破棄し、再送して検査し直す。既にcommit済みなら不変の公開結果を返し、編集可能なstagingへ戻さない。Storeはgenerationの採番と公開headを再起動後も維持し、保持期限を過ぎたrunの再利用／復帰を明示拒否する。

begin時には対象scopeとContribution種別／登録view IDを宣言する。結果作成後、`runs.prepare`でAnnotation、部分graph、view／table／timeline／overlayデータのID集合・件数・digestを有界なpublication manifestとして固定してからstageする。prepareの同一内容の再送は同じ結果に結び付け、内容の変更は拒否する。同じ公開単位内のbindingと入力世代を一致させ、未提供の種別を別runのデータから暗黙に継承しない。

### 8.2 staging・commit・現在結果

`annotations.replaceBatch`、`extensionGraphs.replace`、viewデータ更新はpublication IDを指定して自分の領域へstageする。ページごとのID・件数・digestを検査し、全受信まで現在結果へ表示しない。`runs.commit`は全構成要素の充足・予算・入力binding・現在の権限を再検査し、Contribution全体と公開headを一つのtransactionで確定する。中途データや種別ごとのheadを公開しない。通知はcommit後の同じpublication IDへ束縛し、GUIも一つの公開単位として切り替える。

公開完了と外部の検証判定を分ける。`completion = complete`はProviderが宣言した範囲の処理・結果作成を完了し、publication manifestの全構成要素が揃った意味であり、PASSや証明成立を意味しない。欠陥を検出した結果でも処理が完了していれば公開できる。実行失敗・部分完了・cancel・unknownは`failed / partial / cancelled / unknown`として最新試行に記録し、現在結果のheadを置換しない。

| commitするrun | 現在結果と履歴 |
|---|---|
| `complete`かつgenerationが現在の完了公開headより新しい | transactionでheadを更新し、前回の公開を履歴として保持 |
| 古いgenerationが遅れて完了 | `PUBLICATION_SUPERSEDED`。新しいheadを上書きしない。履歴の保存可否を応答に明示 |
| 新しい試行が失敗・未完了・cancel・unknown | 試行状態を表示し、前回の公開headを保持 |
| 宣言した全構成要素が揃った`complete`の空結果 | 空の公開headへ更新できる。前回結果は履歴に残り、「修正済み」という意味はProviderの明示状態以外から付けない |

headのgenerationは単調増加させる。新しい試行が開始しただけではheadを進めないため、より新しい完了公開がない間は、先行runの遅い完了を公開できる。最新試行の失敗と最後の完了結果を別に表示し、先行runを新しい試行の成功として扱わない。

commitの再送はpublication manifestの同一digestに対する同じ結果を返す。別内容で同じpublication IDを使えば拒否する。commit後の内容は不変とし、変更は新しいrunで行う。未commitのstagingには所有session・期限・件数／bytes上限を設け、abort・失効・権限剥奪時に破棄する。切断／再起動で未完のstagingを公開しない。公開headと履歴の保持予算はStoreが所有する。

### 8.3 既存APIと適用状態

書き込み経路はrun単位の公開transactionに統一する。`annotations.upsert/remove`と`extensionGraphs.upsert`は削除し、別々の保存テーブルや更新分岐を残さない。Annotationと部分graphの読み取りも、commit済みrunのContributionを正本として返す。新しい完了runに対象IDを含めないことで、現在結果から削除する。

## 9. 入力snapshotを外部検証へ渡す

InputManifestと入力leaseのAPIを`inputs.manifest`／`inputs.acquire/read/renew/release`へ統一する。別名のlease APIは提供しない。leaseは読み取り対象のgraph snapshotと入力manifestを固定する。leaseが全ソースbytesの保存を意味するとは限らない。

`inputs.manifest`は相対path、source digest、依存lock、context、provider coverage、設定、除外範囲を返す。入力内容の取得は別権限`inputs.read`を要求する。存在しない旧bytesを現在ファイルで代用しない。

`inputs.read`は許可root内の特定ファイル・範囲だけを返す。leaseと同じ所有session・snapshot・path・offset・件数を検査し、各応答に元ファイルのsource digest・全bytes数・EOFを付ける。range応答のdigestはファイル全体のdigestと区別する。

| digest | 対象と照合方法 |
|---|---|
| `sourceDigest` | 元ファイルの全bytesのSHA-256。コピー先で全rangeを正しいoffsetへ復元した後、`SHA256(fileBytes) == manifest.files[path].sourceDigest`を検査 |
| `inputManifestDigest` | schema、workspace／scope、pathとsource digestの集合、依存lock、context、設定、coverage、除外範囲を含むManifest本体の正準シリアライズのSHA-256。自身のdigest値を本体から除外 |
| Action／結果の入力binding | `snapshotID`と`inputManifestDigest`を、固定したlease／manifestと照合 |

Manifestのkey順・集合の安定sort・UTF-8はschemaで固定する。取得したファイルbytesのhashをManifest全体のhashと比較しない。上位ツールは全range・全対象ファイルの照合を完了したコピーだけを、自分の有界なimmutable workspaceとして確定する。取得するbytesが固定manifestと異なる場合やdigest／offset／EOFが不整合な場合は、`INPUT_CHANGED`または対応するtyped errorで失敗させ、部分コピーを完全な入力として使わない。ライブのdiskが編集されても、leaseが保持する照合済みの旧bytesは固定入力として取得できる。これを現入力と一致した意味へ昇格させない。旧bytesを保持していない場合は別の明示エラーとし、現在ファイルで代用しない。

既定leaseは60秒とし、`inputs.renew`は同じ所有sessionの固定snapshot／manifestの有効期間だけを更新する。別世代への更新や権限拡大に使わない。期限・保持量・同時lease数・総寿命はホストが宣言する資源予算内とし、予算超過では既存leaseを勝手に付け替えず明示拒否する。長時間検証は上位ツールの入力コピーを利用し、Explorerの履歴を無制限に固定しない。lease expiry、旧ソース未保持、権限不足を別診断にする。

## 10. 差分イベントと反復防止

既存のsequence／epoch／resync契約を保持する。イベントに`originProviderID`、`causationID`、`category`を追加する。購読streamのepoch／sequenceと、認可epoch・job状態revision・slot内generationは別の識別子として扱い、互いの代用にしない。

上位ツールは入力・構造・能力の変更を検証計画へ使える。自身のAnnotation更新は再検証のトリガーにしない。他Providerの結果を検証入力とする場合は、明示的な依存DAGとcycle検出を要求する。

Providerの書き込みによるevent stormはレート・サイズ・queue制限を適用する。backpressureでは通知を無言で落とさず再同期を要求する。外部結果の大量更新が構造QueryやGUI操作を飢餓状態にしない。

## 11. モジュール間の振る舞いを拡張する余地

現在のArchitectureIRは構造・限定CFGを主対象とする。将来の解析Providerは`read/write resource`、`call argument/return`、`suspend/resume`、`send/receive`、`transaction`等の情報を、namespaced factsまたは外部部分graphとして供給できる。

情報にはsource、context、aliasの精度、観測／静的候補、未解決境界、summary生成規則を付ける。`happensBefore`は実行順序の根拠がある場合だけ生成する。通常のCall Graphから必ず成り立つ時間順序を捏造しない。

共通schemaへ昇格する際は、仕様とテストを追加する。形式検証に足りない意味を「拡張属性があるから完全」と認定しない。影響解析の情報は、実行意味のFormalIRを代替しない。

## 12. セキュリティと障害分離

既存のworkspace trust、loopback／Origin検査、socket権限を適用する。インストール・バイナリ実行・ネットワーク許可はExtension Manifestでは取得できない。

外部Providerは別プロセスで動く。ただし「別プロセス」はsandboxの保証ではない。実コード・ビルドscript・Fuzzerの隔離は上位実行ツールの責任であり、その環境を確認できなければ外部実行を開始しない。

Artifactは許可root内の相対参照とdigestだけを受け取る。Path traversal、symlink、任意URLの自動fetch、秘密情報のexportを防ぐ。外部ログとソースは命令ではなくデータとして扱う。

拡張停止・不正message・timeoutでもcore graphを破損させず、そのProviderだけを隔離できること。

## 13. 段階実装

| Phase | 内容 | 必須の実証 |
|---|---|---|
| E0 | 版・profile・principal・権限・Manifest・公開型 | mock Providerの登録／拒否と、全操作のprincipal／permission検査を実証 |
| E1 | Query・events・input lease | 世代固定・失効・reconnectが試験できる |
| E2 | Annotation・views・partial graph・run公開 | 複数種別を同じpublicationでatomic表示し、失敗／古いrunでheadが戻らないことを実証 |
| E3 | ActionIntent・進捗・cancel | 外部mockへの一度の転送、token検査、ACK喪失／再接続の重複排除、受付と停止完了の区別を実証。Explorerは検証processを起動しない |
| E4 | 実上位ツールとの結合 | 世代更新・Provider異常・offline exportのE2E |

## 14. 追加受け入れテスト

元仕様AE-001〜AE-060を維持し、以下を追加する。

| ID | 合格条件 |
|---|---|
| AEX-001 | Explorerの依存・owned subprocessにformal／Java／Leanが追加されない |
| AEX-002 | mock Providerを追加してcore parserとGUIの業務ロジックを変更しない |
| AEX-003 | API major不一致を登録時に拒否する |
| AEX-004 | 全APIで未付与permissionのquery／書き込み／input取得を副作用前に拒否し、バッチ・購読でも迂回できない |
| AEX-005 | Provider AがBのProvider名／registration ID／namespaceを申告しても、principalと接続bindingの検査で拒否され、Bの領域やcore Factを変更できない |
| AEX-006 | Provider不在／停止でも構造GUIとCLIが動く |
| AEX-007 | 任意HTML／JS／shellをContributionへ混入しても実行されない |
| AEX-008 | 有効な台帳にreceiptがある同じkey・fingerprintの再送は同じreceipt／job IDへ結び付き、同じ入力でもaction・引数・選択・期限を変えた要求はIDEMPOTENCY_CONFLICTとなる |
| AEX-009 | 確認後のコード変更で現在入力へ移らず、INPUT_CHANGEDまたは照合済みの承認snapshotだけを利用する |
| AEX-010 | mockがcancel受付を返しても処理を継続している間はcancellingを維持し、対応する停止完了通知後だけcancelledへ遷移する |
| AEX-011 | read-only MCPから検証・trust昇格を実行できない |
| AEX-012 | lease失効／旧bytes不在／入力変更を区別して拒否する |
| AEX-013 | 欠けたdependency digestを入力一致と判定しない |
| AEX-014 | Annotation・graph・viewの途中ページ／部分commit／abort／切断を挟んでも、中途結果や種別間で異なるpublicationを現在結果へ表示しない |
| AEX-015 | stale結果を現入力の証明に昇格しない |
| AEX-016 | 同じ名前の別entityへ結果を自動移植しない |
| AEX-017 | 自身のAnnotation書き込みが無限の再検証ループを起こさない |
| AEX-018 | 遅いProvider／viewへbackpressure・resyncを適用する |
| AEX-019 | actionはoffline HTMLで無効化され、liveと誤表示しない |
| AEX-020 | graph・table・timelineが同じpublication ID／run ID／入力bindingで同時に切り替わり、未提供種別を過去runから暗黙継承しない |
| AEX-021 | 認可済みでも予算外のwrite／readを制限する |
| AEX-022 | 切断・権限失効後の旧sessionによる読み書き・転送・commitを拒否し、新sessionへ旧token／lease／stagingの権限を暗黙移譲しない |
| AEX-023 | 外部status、入力適用状態、範囲・前提を別に表示する |
| AEX-024 | data／effect／temporalの未知属性を推測して意味確定しない |
| AEX-025 | token偽造・改変・期限切れ・別session／action／引数への流用を転送前に拒否し、requiresConfirmation=falseや読み取りeffectを申告しても、外部転送に必要なホストの確認policyを下げられない |
| AEX-026 | 削除済みの互換profile・書き込みAPI名・lease別名を拒否する。保存経路はcommit済みrunのContributionだけで、旧テーブル・adapter・移行分岐が存在しない |
| AEX-027 | 複数ファイル・複数rangeのコピーを各sourceDigestで照合し、Manifest全体はinputManifestDigestで別に検証する。欠落・混合世代・範囲不整合を完全入力として確定しない |
| AEX-028 | 新しいrunの公開後に古いrunが完了してもheadが戻らない。新しい試行の失敗／partial／cancelは前回headを保ち、completeの空結果だけが空headを公開できる |
| AEX-029 | cancel受付後の切断／timeoutはunknownと最後の観測を保持する。通常完了との競合・古いrevision・重複終端通知でcompleted／failed／cancelledを誤って変更しない |
| AEX-030 | ACK喪失・Provider再起動・ホスト再起動を挟んでも同じkeyを別jobとして開始しない。台帳喪失はACTION_OUTCOME_UNKNOWN、保持期限後はIDEMPOTENCY_KEY_EXPIREDで拒否し、予算満杯でも有効な台帳を追い出さない |

## 15. 納品物

公開SDK、schemas、mock拡張、CLI／API reference、GUI E2E、権限・異常系テスト、refactor記録、PROGRESSを納品する。SDK・wire schema・API referenceに仕様profile、principal／permission対応、要求fingerprintの正準化、receipt／job状態、publication transaction、digest対象、資源予算のownerと検証条件を揃える。削除済みのAPI・profileの拒否と、更新した現行SDKからのQuery・Annotation公開を実証する。

ベース仕様の原本は変更していない。本追補と合わせて実装し、統合した文書を作る場合も責務境界を弱めない。

## 参考と監査対象

- [B1] `ArchitectureExplorer-SPEC.md` v1.0、特に§2、§7–8、§12–13、§17、§20。原本SHA-256：`13c6006f995b9e0ea5a42317f6ef393bd7f9d0570500c2b6655443c649beb76a`。
- [B2] `ArchitectureExplorer-AGENT-HANDOFF.md`。原本SHA-256：`4760fd813f4b918cdd741ad2d1bcdf5f9671acc9483b64ae3b939e8e03c9da77`。
- [N1] 本追補で新規に定めた契約は設計判断であり、上流ライブラリの既存機能や統合実証を意味しない。
