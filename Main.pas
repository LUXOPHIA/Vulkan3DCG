unit Main;

interface //#################################################################### ■

uses
  System.SysUtils, System.Types, System.UITypes, System.Classes, System.Math,
  FMX.Types, FMX.Controls, FMX.Forms, FMX.Graphics, FMX.Dialogs,
  FMX.Controls.Presentation, FMX.StdCtrls, FMX.Objects,
  FMX.Memo.Types, FMX.ScrollBox, FMX.Memo,
  vk_platform, vulkan_core, vulkan_functions,
  glslang_c_shader_types,
  LUX, LUX.D3, LUX.D4x4,
  LUX.Vulkan,
  LUX.Vulkan.Show,
  LUX.Vulkan.Graphics,
  LUX.Vulkan.Graphics.D3,
  LUX.Vulkan.Graphics.D3.Shapers,
  LUX.Vulkan.Viewer;

type
  TForm1 = class(TForm)
    PanelB: TPanel;
      CheckD: TCheckBox;
      CheckT: TCheckBox;
      MemoS: TMemo;
    Viewer: TVkViewer;
    Timer1: TTimer;
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure Timer1Timer(Sender: TObject);
    procedure CheckDChange(Sender: TObject);
    procedure CheckTChange(Sender: TObject);
    procedure ViewerMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Single);
    procedure ViewerMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Single);
    procedure ViewerMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Single);
    procedure ViewerMouseWheel(Sender: TObject; Shift: TShiftState; WheelDelta: Integer; var Handled: Boolean);
  private
    { private 宣言 }
    _DownPos :TPointF;
    _Draging :Boolean;
    _AngleH  :Single;
    _AngleV  :Single;
    _Distan  :Single;
    _Spin    :Single;
    ///// M E T H O D
    procedure FitCamera;
    procedure ShowBuild;
  public
    { public 宣言 }
    _Contex  :TVkContex;
    _Queuer  :TVkQueuer;
    _ShaderV :TVkShader;
    _ShaderF :TVkShader;
    _Raster  :TVkRaster3D;
    _Scene   :TVkScener;
    _Cube    :TVkCube3D;
    _Camera  :TVkCameraPers3D;
    ///// M E T H O D
    procedure MakeContext;
    procedure MakeShaders;
    procedure MakeScene;
  end;

var
  Form1: TForm1;

implementation //############################################################### ■

{$R *.fmx}

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& private

//////////////////////////////////////////////////////////////////// M E T H O D

procedure TForm1.FitCamera;
var
   P :TSingle3D;
begin
     P.X := _Distan * Cos( _AngleV ) * Sin( _AngleH );                          // 極座標で軌道を回る
     P.Y := _Distan * Sin( _AngleV );
     P.Z := _Distan * Cos( _AngleV ) * Cos( _AngleH );

     _Camera.LookAt( P, TSingle3D.Create( 0, 0, 0 ) );                          // 原点を見る
end;

//------------------------------------------------------------------------------

procedure TForm1.ShowBuild;
var
   S :String;
begin
     with MemoS.Lines do
     begin
          Add( '▼ Device' );
          Add( _Contex.Device.DEVICE_NAME + '  ( Vulkan ' + _Contex.Device.API_VERSION.ToString + ' )' );
          Add( 'queue family = ' + _Contex.FamilyI.ToString );
          for S in _Contex.UsingExtens do Add( 'device extension = ' + S );
          Add( '' );

          Add( '▼ Shader' );
          Add( 'vertex   : ' + BoolToStr( _ShaderV.CompileOK, True ) + '  ' + _ShaderV.CompileLog );
          Add( 'fragment : ' + BoolToStr( _ShaderF.CompileOK, True ) + '  ' + _ShaderF.CompileLog );
          Add( 'SPIR-V   : ' + _ShaderV.Binary.Size.ToString + ' ＋ '
                             + _ShaderF.Binary.Size.ToString + ' Bytes' );
          Add( '' );

          Add( '▼ Pipeline' );
          Add( 'BuildOK = ' + BoolToStr( _Raster.BuildOK, True ) );
          if _Raster.BuildLog <> '' then Add( _Raster.BuildLog );
          Add( '' );

          Add( '▼ Camera' );
          Add( Format( 'screen = %.0f × %.0f', [ _Camera.SizeX, _Camera.SizeY ] ) );
          Add( Format( 'focus  = %.3f  →  angle %.1f° × %.1f°',
                       [ _Camera.FocusZ, RadToDeg( _Camera.AngleX ), RadToDeg( _Camera.AngleY ) ] ) );
     end;
end;

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& public

//////////////////////////////////////////////////////////////////// M E T H O D

procedure TForm1.MakeContext;
begin
     ////////// CONTEXT ( 論理デバイス )

     _Contex := TVkContex.Create( TVulkan.Devices[ 0 ] );                        // 生成

     // QueFlags の既定は GRAPHICS ＋ COMPUTE なので、描画できるキューが選ばれる。
     // VK_KHR_swapchain も既定で有効化される（TVkContex.UsingExtens）。

     ////////// QUEUE

     _Queuer := TVkQueuer.Create( _Contex );                                     // 生成

     Assert( Assigned( _Contex.Handle ), '_Contex is Error!' );                  // 検証
     Assert( Assigned( _Queuer.Handle ), '_Queuer is Error!' );                  // 検証
end;

//------------------------------------------------------------------------------

procedure TForm1.MakeShaders;
begin
     ////////// SHADER MODULES ( ＝ VkShaderModule。1 段につき 1 個 )

     _ShaderV := TVkShader.Create( _Contex );                                    // 生成
     _ShaderV.Stage := GLSLANG_STAGE_VERTEX;                                     // 段の指定
     _ShaderV.Source.LoadFromFile( '..\..\_DATA\Shader.vert' );                  // GLSL のロード（自動コンパイル）

     _ShaderF := TVkShader.Create( _Contex );                                    // 生成
     _ShaderF.Stage := GLSLANG_STAGE_FRAGMENT;                                   // 段の指定
     _ShaderF.Source.LoadFromFile( '..\..\_DATA\Shader.frag' );                  // GLSL のロード（自動コンパイル）

     ////////// RASTERIZE PIPELINE ( ＝ VkPipeline )

     _Raster := TVkRaster3D.Create( _Contex );                                   // 生成（頂点配置と押込定数は既定）

     _Raster.Stagers.Add( _ShaderV );                                            // 段の登録
     _Raster.Stagers.Add( _ShaderF );                                            // 段の登録
end;

//------------------------------------------------------------------------------

procedure TForm1.MakeScene;
begin
     ////////// SCENE ( 根 )

     _Scene := TVkScener.Create( _Queuer );                                       // 生成（コンテキストはキューから導かれる）
     _Scene.BackColor := TAlphaColorF.Create( 0.10, 0.12, 0.16, 1 );             // 背景色
     _Scene.Raster    := _Raster;                                               // 既定のパイプライン（子へ継承される）

     ////////// CUBE

     _Cube := TVkCube3D.Create( _Scene );                                        // 生成（シーンへ所属）
     _Cube.Size := TSingle3D.Create( 1, 1, 1 );                                  // 寸法

     ////////// CAMERA

     _Camera := TVkCameraPers3D.Create( _Scene );                                   // 生成（シーンへ所属）
     _Camera.SizeX  := 4;                                                        // スクリーンの幅  （実寸。描画先の縦横比とは独立）
     _Camera.SizeY  := 3;                                                        // スクリーンの高さ（同）
     _Camera.AngleY := DegToRad( 40 );                                           // 縦の画角 → FocusZ が決まる
     _Camera.NeaZ   := 0.1;
     _Camera.FarZ   := 100;

     _AngleH := DegToRad(  30 );
     _AngleV := DegToRad(  20 );
     _Distan := 3.2;

     FitCamera;

     ////////// VIEWER

     Viewer.Attach( _Queuer );                                                   // キューの接続（コンテキストも定まる）
     Viewer.Camera := _Camera;                                                   // カメラの接続（シーンの変化を購読する）
end;

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&

procedure TForm1.FormCreate(Sender: TObject);
begin
     if not TVulkan.Available or ( TVulkan.Devices.Count = 0 ) then
     begin
          MemoS.Lines.Add( 'Vulkan is not available.' );                         // Vulkan が利用できない環境

          Exit;
     end;

     MakeContext;                                                               // コンテキストの生成

     MakeShaders;                                                               // シェーダとパイプラインの生成

     MakeScene;                                                                 // シーングラフの生成

     ShowBuild;                                                                 // ビルド情報の表示

     TVulkan.Show( MemoS.Lines );                                               // システム情報の表示

     Timer1.Enabled := CheckT.IsChecked;                                        // 回転開始
end;

procedure TForm1.FormDestroy(Sender: TObject);
begin
     Timer1.Enabled := False;

     Viewer.Camera := nil;                                                      // 購読を外す（カメラより先に）

     _Scene.Free;                                                               // 部分木ごと解放（立方体とカメラも）

     // _Raster は Contex の子（Contex.Rasters）なので、コンテキストと共に解放される
end;

////////////////////////////////////////////////////////////////////////////////

procedure TForm1.Timer1Timer(Sender: TObject);
begin
     _Spin := _Spin + 0.012;

     // 姿勢を変えるとシーンが Changed → カメラの OnScene → ビューアの再描画、と伝わる。
     // 明示的に Viewer.Render を呼ぶ必要はない。
     _Cube.LocalPose := TSingleM4.RotateY( _Spin ) * TSingleM4.RotateX( _Spin * 0.6 );
end;

//------------------------------------------------------------------------------

procedure TForm1.CheckDChange(Sender: TObject);
begin
     Viewer.Direct := CheckD.IsChecked;  // 子ウィンドウ ／ TBitmap 経由 の切り替え
end;

procedure TForm1.CheckTChange(Sender: TObject);
begin
     Timer1.Enabled := CheckT.IsChecked;
end;

////////////////////////////////////////////////////////////////////////////////

procedure TForm1.ViewerMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Single);
begin
     if Button <> TMouseButton.mbLeft then Exit;

     _DownPos := TPointF.Create( X, Y );
     _Draging := True;
end;

procedure TForm1.ViewerMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Single);
var
   D :TPointF;
begin
     if not _Draging or not ( ssLeft in Shift ) then Exit;

     D := TPointF.Create( X, Y ) - _DownPos;

     _DownPos := TPointF.Create( X, Y );

     _AngleH := _AngleH - D.X * 0.01;
     _AngleV := EnsureRange( _AngleV + D.Y * 0.01, -1.5, +1.5 );  // 真上・真下は避ける

     FitCamera;
end;

procedure TForm1.ViewerMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Single);
begin
     _Draging := False;
end;

procedure TForm1.ViewerMouseWheel(Sender: TObject; Shift: TShiftState; WheelDelta: Integer; var Handled: Boolean);
begin
     _Distan := EnsureRange( _Distan * Power( 1.1, -WheelDelta / 120 ), 1.2, 40 );

     FitCamera;

     Handled := True;
end;

end. //######################################################################### ■
