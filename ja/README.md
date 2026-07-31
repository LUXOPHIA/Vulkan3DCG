# Vulkan3DCG

[English](../README.md) | [日本語](README.md)

Delphi ／ FireMonkey 上で [Vulkan](https://registry.khronos.org/vulkan/) の**ラスタライザ**を動かすリアルタイム３ＤＣＧデモ。
組み込みの glslang が実行時に SPIR-V へコンパイルする 2 本の GLSL シェーダからグラフィックスパイプラインを組み、ライティングされた回転する立方体を描き、子 `HWND` を介してスワップチェーンが FireMonkey のフォームへ直接提示します。
左ボタンのドラッグでカメラが軌道を回り、ホイールで前後に移動します。

![Vulkan3DCG](../--------/_SCREENSHOT/Vulkan3DCG.png)

## 利用ライブラリ

* [**LUX**](https://github.com/LUXOPHIA/LUX) ：LUXOPHIA の基盤数学ライブラリ。
* [**LUX.Vulkan**](https://github.com/LUXOPHIA/LUX.Vulkan) ：Vulkan API のラッパーライブラリ。

## 1. 概要

* **Vulkan のグラフィックスパイプライン一式**：描画パス、グラフィックスパイプライン、頂点／添字バッファ、押込定数、深度バッファ、表示面とスワップチェーン。
* **シーングラフ**：アプリケーションは Vulkan のハンドルに一度も触れません。`TVkScener` ／ `TVkCube3D` ／ `TVkCameraPers3D` のノードで木を組み、行列を代入するだけで、描画・行列の累積・変更の伝播は [`LUX.Vulkan`](https://github.com/LUXOPHIA/LUX.Vulkan) ライブラリが担います。
* **GLSL の実行時コンパイル**：`Shader.vert` ／ `Shader.frag` はふつうの GLSL ファイルで、読み込み時に `glslang.dll` [5] がコンパイルします。事前工程も Vulkan SDK も CMake も不要 ―― ファイルを書き換えてアプリを起動し直すだけです。
* **変更駆動の再描画**：行列の代入 1 行（`_Cube.LocalPose := …`）が木を伝わり、ビューアが自動的に描き直されます。明示的な描画呼び出しは不要です。
* **2 つの提示経路**：フレームの上に貼った裸の `WS_CHILD` ウィンドウへの直接提示（`TVkSwaper`）と、FireMonkey の描画順に従う `TBitmap` 経由のオフスクリーン描画（`TVkRender`）を、実行中に切り替えられます。
* **記述子セットなし**：オブジェクトごとのデータはすべて 128 バイトの押込定数で渡ります。これは Vulkan のどの実装も必ず対応する最小容量とちょうど同じです [1]。

## 2. 技術的背景

### 2.1. Vulkan の描画モデル

Vulkan は GPU を明示的なオブジェクトの連鎖として公開します [1][2]。

* **インスタンス → 物理デバイス**：`TVulkan` が `VkInstance` を生成し、`VkPhysicalDevice` を列挙します（`TVulkan.Devices`）。
* **論理デバイス**：`TVkContex` がひとつの物理デバイス上に `VkDevice` を生成します。描画できるキューファミリの選択と `VK_KHR_swapchain` の有効化は既定です。
* **キュー**：`TVkQueuer` はそのファミリの `VkQueue` と `VkCommandPool` を包み、記録・投入・提示を行います。
* **描画パス**：`TVkPasser` は最も基本的な `VkRenderPass` ―― 色添付 1 枚＋深度添付 1 枚、サブパス 1 個、どちらも読み込み時に消去（`loadOp = CLEAR`）―― を構成します。提示用には色添付の最終レイアウトを `VK_IMAGE_LAYOUT_PRESENT_SRC_KHR` とします。
* **グラフィックスパイプライン**：`TVkRaster3D` が 2 つのシェーダ段、固定の `TVkVertex3D` 頂点配置、`TVkPush3D` の押込定数範囲から `VkPipeline` を組み立てます。パイプラインは**互換な**描画パス（添付の形式とサンプル数が一致）の間で使い回せるため、ひとつのパイプラインが両方の提示経路を賄います。
* **スワップチェーン**：`TVkSwaper` が `HWND` を `VkSurfaceKHR` ＋ `VkSwapchainKHR` に変え、取得 → 記録 → 投入 → 提示 → 待機の 1 フレーム完結ループを回します。

### 2.2. 変換の連鎖

各シーンノードは局所姿勢行列を持ち、`GlobalPose` は先祖の姿勢の積です。モデル行列 $M$（立方体の累積姿勢）、視野行列 $V$（カメラの大域姿勢の逆行列。`TVkCamera.ViewMat`）、射影 $P$ により、頂点 $p$ は次のようにクリップ空間へ届きます。

```math
p_{clip} = P \, V \, M \, p \tag{1}
```

頂点シェーダは必要な 2 つの積を押込定数（`TVkPush3D`）として受け取ります。位置に適用する `ProjViewPose` $= P V M$ と、姿勢のみの `Pose` $= M$ です。後者の左上 $3 \times 3$ ブロックが法線を変換します（等方スケールを前提とします）。

```math
n_{world} = M_{3 \times 3} \, n \tag{2}
```

### 2.3. Vulkan 規約での射影

Vulkan のクリップ空間は OpenGL と異なり、フレームバッファの $y$ 軸は**下向き**、正規化深度の範囲は $[-1, +1]$ ではなく $z \in [0, 1]$ です [1]。そのためライブラリは `LUX.D4x4` の OpenGL 流の射影行列を変換するのではなく、Vulkan 規約の射影行列を直接作ります（`VkProjPers3D` ／ `VkProjOrth3D`）。実寸 $s_x \times s_y$ のスクリーンを焦点距離 $f$（`TVkCameraPers3D.FocusZ`）に置き、前後クリップ面を $z_n$、$z_f$ とすると：

```math
P_{pers} =
\begin{pmatrix}
\dfrac{2f}{s_x} & 0 & 0 & 0 \\
0 & -\dfrac{2f}{s_y} & 0 & 0 \\
0 & 0 & \dfrac{z_f}{z_n - z_f} & \dfrac{z_f \, z_n}{z_n - z_f} \\
0 & 0 & -1 & 0
\end{pmatrix} \tag{3}
```

第 2 行の負号がＹ下向きの規約を実現し、第 3 行が視野空間の深度範囲 $[-z_n, -z_f]$ を $[0, 1]$ へ写します。画角は導かれる量であり、`AngleY` への代入はスクリーンを保ったまま焦点距離を動かします：$f = \frac{s_y}{2} \cot\frac{\theta_y}{2}$。

カメラのスクリーンの縦横比（$s_x : s_y$。ここでは $4 : 3$）は描画先のピクセルの縦横比から独立しています。`VkFitViewport` が `VkViewport` をレターボックスにして、カメラの視野を歪みなく描画先の中央へ収めます。余白をわざわざ塗る必要はありません。描画パスがフレームバッファ全体をシーンの背景色で消去したあとだからです。

### 2.4. シェーダと押込定数

2 つの段はふつうの GLSL ファイルで、組み込みの glslang [5] が読み込み時にコンパイルします。

```GLSL
layout( push_constant ) uniform Push { mat4 ProjViewPose; mat4 Pose; } uPush;

layout( location = 0 ) in vec3 aPos;
layout( location = 1 ) in vec3 aNor;
layout( location = 2 ) in vec2 aTex;
```

128 バイトの `TVkPush3D` ブロックは `maxPushConstantsSize` の保証最小値とちょうど同じ [1] なので、このデモには記述子セットがひとつもありません。フラグメントシェーダはワールド座標系の法線で各面に色を振り（$C = \frac{N}{2} + \frac{1}{2}$）、テクスチャ座標から導いた $4 \times 4$ の市松模様を重ね、固定の平行光でランバート拡散反射を掛けます。立方体が回っても 6 面を見分けられるようにするためです。

## 3. アーキテクチャ

### 3.1. クラス図

実際のクラスと所有関係（`LUX.Vulkan`）。矢印 `─▶` は参照、字下げは所有を表します。

```
[ コアオブジェクト — 字下げ＝所有。各ノードが包む Vulkan ハンドルを右に併記 ]

・TVulkan
  ┗・TVkSystem              ･･･ VkInstance
     ┗・TVkDevice           ･･･ VkPhysicalDevice
        ┗・TVkContex        ･･･ VkDevice（論理デバイス）
           ┣・TVkQueuer     ･･･ VkQueue ＋ VkCommandPool（投入／提示）
           ┣・TVkShader ×2 ･･･ VkShaderModule（GLSL→SPIR-V を glslang で）
           ┣・TVkRaster3D   ･･･ VkPipeline ＋ Layout
           ┗・TVkPasser     ･･･ VkRenderPass（色＋深度、サブパス 1 個）

[ 参照 — 所有しない ]

・TVkRaster3D
  ┗・Stagers                ･･･ 2 本の TVkShader を参照する

[ シーングラフ — 木として所有。Free で部分木ごと解放 ]

・TVkScener                  ･･･ 根：Contex ／ Queuer ／ BackColor、OnChange
  ┣・TVkCube3D              ･･･ TVkShaper3D：TVkVerBuf3D(24)＋TVkIndBuf3D(36)
  ┃  ┗・Raster             ･･･ TVkRaster3D を参照（継承・所有しない）
  ┗・TVkCameraPers3D        ･･･ TVkCamera3D：ProjMat/ViewMat、OnChange→OnScene

[ 提示 — TVkViewer ＝ フォーム上の TFrame ]

・TVkViewer
  ┣・_Passer :TVkPasser     ･･･ ColorLast = PRESENT_SRC_KHR
  ┣・Direct = True
  ┃  ┗・_Window :HWND (WS_CHILD)
  ┃     ┗・TVkSwaper       ･･･ VkSurfaceKHR ＋ VkSwapchainKHR ＋ 深度添付
  ┗・Direct = False
     ┗・TVkRender           ･･･ TBitmap へ描画し Canvas.DrawBitmap で表示
```

1 フレームのデータフロー：

```
[ 1 フレーム — 入れ子は上の段階の内部で起きることを表す ]

・_Cube.LocalPose := …                 ･･･ （デモが書くのはこの 1 行だけ）
  ┗・Changed が木を遡る
     ┗・TVkScener.OnChange
        ┗・TVkCamera.OnScene
           ┗・TVkViewer.Render
              ┣・TVkSwaper.BeginFrame  ･･･ イメージの取得
              ┣・VkRecordScene
              ┃  ┣・描画パス開始      ･･･ 色＋深度の消去
              ┃  ┣・レターボックスのビューポート
              ┃  ┗・TVkCamera.Render  ･･･ ProjView := ProjMat × ViewMat
              ┃     ┗・TVkScener.Draw ･･･ 姿勢を累積（状態は TVkDrawer）
              ┃        ┗・TVkCube3D.DrawMain
              ┃           ┣・BindRaster
              ┃           ┣・vkCmdPushConstants
              ┃           ┗・vkCmdDrawIndexed
              ┗・TVkSwaper.EndFrame
                 ┣・投入
                 ┣・提示
                 ┗・待機
```

### 3.2. シーングラフと変更の伝播

シーンは `TVkObject` ノード（`TTreeKnot`）の木です。`TVkScener` は親を拒否するノードなので、根は木を遡るだけで見つかります。`Create( Parent )` で木へ加わり、`Free` で部分木ごと解放され、循環は Tree 層が拒否します。あるノードに設定したパイプライン（`Raster`）は子孫へ継承されます。ノードはそれを参照するだけで、所有はしません。

再描画はタイマが起こしているのでは**ありません**。姿勢・寸法・可視性・挿抜などあらゆる変更は `Changed` として木を遡り、`TVkScener.OnChange`（多播デリゲート）でシーンの外へ出て、購読中のカメラが `OnScene` として転送し、ビューアへ届いてフレームが再記録・再提示されます。つまりアニメーション全体が 1 ティックにつき代入 1 行です。

```Delphi
procedure TForm1.Timer1Timer(Sender: TObject);
begin
     _Spin := _Spin + 0.012;

     _Cube.LocalPose := TSingleM4.RotateY( _Spin ) * TSingleM4.RotateX( _Spin * 0.6 );
end;
```

### 3.3. ビューア：FireMonkey へのスワップチェーンの埋め込み

FireMonkey はフォーム全体をひとつの `HWND` へ描くため、Vulkan が提示に割り込む素直な継ぎ目がありません。そこで `TVkViewer`（`TFrame`）は自分の矩形の上に **`WS_CHILD` の裸のウィンドウ** ―― `TForm` ではない ―― を生成し、`TVkSwaper` を通してそこへ提示します。フォームの `HWND` の子なのでフォームにクリップされ、移動・最小化・破棄に付いていくため、Z 順やアクティブ化の管理はいっさい不要です。子ウィンドウは `WM_NCHITTEST` で `HTTRANSPARENT` を返すので入力を飲みません。マウスはふだんどおり FireMonkey へ届き、軌道回転／ズームはフレームのふつうの `OnMouseDown` ／ `OnMouseMove` ／ `OnMouseWheel` イベントで書かれています。あらゆるピクセルを Vulkan が握るため、`WM_ERASEBKGND` は無視し、`WM_PAINT` は何も描かずに検証だけします。

`Direct := False` にするとビューアは `TVkRender` に切り替わり、オフスクリーンに描いて `Paint` で `TBitmap` を転送します。この経路は FireMonkey の描画順に従うため上にコントロールを重ねられますが、毎フレーム GPU → CPU → GPU の往復が入ります。`TVkSwaper` は 1 フレーム完結で動き、`VK_ERROR_OUT_OF_DATE_KHR` ／ `VK_SUBOPTIMAL_KHR` は再構築の合図として扱います。最小化中は `Ready` が `False` となり、フレームは丸ごと飛ばされます。

### 3.4. ファイルツリー

```
・Vulkan3DCG/
  ┣・Vulkan3DCG.dpr / .dproj ･･･ FireMonkey プロジェクト（Win32／Win64）
  ┣・Main.pas / Main.fmx     ･･･ TForm1：オブジェクトの構築＋軌道カメラの入力
  ┣・_DATA/
  ┃  ┣・Shader.vert         ･･･ 頂点段：押込定数、aPos ／ aNor ／ aTex
  ┃  ┗・Shader.frag         ･･･ フラグメント段：法線の色分け＋市松＋拡散反射
  ┗・_LIBRARY/LUXOPHIA/
     ┣・LUX/                 ･･･ 基盤：TSingle3D、TSingleM4、木／リスト
     ┗・LUX.Vulkan/          ･･･ Vulkan ラッパライブラリ（git subtree）
        ┣・Core/             ･･･ Contex／Queuer／Shader／Passer／Raster ほか
        ┣・Graphics/         ･･･ シーングラフ、Swaper、Render、Viewer
        ┣・Glslang/ ＋ _DLL/ ･･･ glslang バインディング＋ glslang.dll [5]
        ┗・Vulkan/           ･･･ Vulkan API の翻訳（vulkan_core ほか）
```

## 4. 使い方

| 操作 | 動作 |
|---|---|
| ビューを左ドラッグ | カメラが原点の周りを軌道回転（極座標。ピッチは ±1.5 rad に制限） |
| マウスホイール | ドリー：1 ノッチごとに距離 × 1.1。[1.2, 40] に制限 |
| **Direct** チェックボックス | オン：子ウィンドウのスワップチェーンへ提示 ／ オフ：オフスクリーンの `TVkRender` → `TBitmap` |
| **Rotate ( TTimer )** チェックボックス | 立方体の回転の開始／停止 |

左のメモには、選択されたデバイスと Vulkan バージョン、キューファミリと有効化された拡張、シェーダのコンパイル結果と SPIR-V のサイズ、パイプラインの構築状況、カメラのスクリーン／焦点距離／画角が表示されます。

## 5. ビルド

* **IDE**：RAD Studio ／ Delphi（FireMonkey プロジェクト、`ProjectVersion 20.4`）。
* **プラットフォーム**：Windows 32 ビット／ 64 ビット（`Vulkan3DCG.dproj` の `Win32` ／ `Win64` ターゲット）。
* **実行時の要件**：Vulkan ランタイム（`vulkan-1.dll`）を提供する GPU ドライバ。**Vulkan SDK は不要**です ―― API の翻訳は `_LIBRARY/LUXOPHIA/LUX.Vulkan/Vulkan/` にあり、ローダは実行時に束縛されます。Vulkan が無い環境でもアプリは起動し、「Vulkan is not available.」と表示します。
* **シェーダのコンパイル**：ビルド時には行いません。`_DATA/` の GLSL ソースは起動時に `glslang.dll` [5] が SPIR-V へコンパイルします。この DLL はビルド後イベントが `_LIBRARY/LUXOPHIA/LUX.Vulkan/_DLL/$(Platform)/` から実行ファイルの隣へコピーします。シェーダの編集はアプリの再起動だけで反映されます。

`Vulkan3DCG.dproj` を開き、プラットフォームを選んで実行してください。

## 6. 参考文献

1. Khronos Group, [*Vulkan Specification*](https://registry.khronos.org/vulkan/specs/latest/html/)
2. Khronos Group, [*Vulkan Guide*](https://docs.vulkan.org/guide/latest/index.html)
3. Khronos Group, [*Vulkan Registry*](https://registry.khronos.org/vulkan/)
4. Khronos Group, [*Vulkan-Headers*](https://github.com/KhronosGroup/Vulkan-Headers)
5. Khronos Group, [*glslang*](https://github.com/KhronosGroup/glslang)

## 💖 [Embarcadero](https://www.embarcadero.com/jp/) [**Delphi**](https://www.embarcadero.com/jp/products/delphi)
ネイティブなクロスプラットフォームアプリを開発するための統合開発環境（ＩＤＥ）。
### Free Download: [**Delphi** Community Edition](https://www.embarcadero.com/jp/products/delphi/starter)
