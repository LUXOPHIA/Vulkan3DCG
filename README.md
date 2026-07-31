# Vulkan3DCG

[English](README.md) | [日本語](ja/README.md)

Real-time 3DCG demo with the [Vulkan](https://registry.khronos.org/vulkan/) **rasterizer** in Delphi / FireMonkey.
A graphics pipeline built from two GLSL shaders — compiled to SPIR-V at runtime by an embedded glslang — draws a lit, spinning cube, and a swapchain presents it straight into a FireMonkey form through a child `HWND`.
Drag with the left button to orbit the camera; spin the wheel to dolly in and out.

![Vulkan3DCG](--------/_SCREENSHOT/Vulkan3DCG.png)

## 利用ライブラリ

* [**LUX**](https://github.com/LUXOPHIA/LUX) ：The foundation math library of LUXOPHIA.
* [**LUX.Vulkan**](https://github.com/LUXOPHIA/LUX.Vulkan) ：A wrapper library for the Vulkan API.

## 1. Overview

* **Full graphics-pipeline path of Vulkan**: render pass, graphics pipeline, vertex / index buffers, push constants, depth buffer, surface and swapchain.
* **Scene graph**: the application never touches a Vulkan handle. It builds a tree of `TVkScener` / `TVkCube3D` / `TVkCameraPers3D` nodes and assigns matrices; drawing, matrix accumulation and change propagation are handled by the [`LUX.Vulkan`](https://github.com/LUXOPHIA/LUX.Vulkan) library.
* **Runtime GLSL compilation**: `Shader.vert` / `Shader.frag` are plain GLSL files, compiled on load by `glslang.dll` [5]. No offline step, no Vulkan SDK, no CMake — edit a file and restart the app.
* **Change-driven redraw**: assigning one matrix (`_Cube.LocalPose := …`) propagates up the tree and redraws the viewer automatically; no explicit render call is needed.
* **Two presentation paths**: direct presentation into a bare `WS_CHILD` window over the frame (`TVkSwaper`), or an offscreen render copied into a `TBitmap` (`TVkRender`) that obeys FireMonkey's paint order — switchable at runtime.
* **No descriptor sets**: all per-object data travels in a 128-byte push constant, exactly the minimum size every Vulkan implementation must support [1].

## 2. Technical Background

### 2.1. The Vulkan rendering model

Vulkan exposes the GPU as an explicit object chain [1][2]:

* **Instance → physical device**: `TVulkan` creates the `VkInstance` and enumerates the `VkPhysicalDevice`s (`TVulkan.Devices`).
* **Logical device**: `TVkContex` creates a `VkDevice` on one physical device, selecting a graphics-capable queue family and enabling `VK_KHR_swapchain` by default.
* **Queue**: `TVkQueuer` wraps a `VkQueue` of that family plus a `VkCommandPool`; it records, submits, and presents.
* **Render pass**: `TVkPasser` describes the most basic `VkRenderPass` — one color attachment, one depth attachment, one subpass, both cleared on load (`loadOp = CLEAR`). For presentation its final color layout is `VK_IMAGE_LAYOUT_PRESENT_SRC_KHR`.
* **Graphics pipeline**: `TVkRaster3D` builds the `VkPipeline` from the two shader stages, the fixed `TVkVertex3D` vertex layout, and the `TVkPush3D` push-constant range. Pipelines are reusable across *compatible* render passes (same attachment formats and sample counts), so one pipeline serves both presentation paths.
* **Swapchain**: `TVkSwaper` turns an `HWND` into a `VkSurfaceKHR` + `VkSwapchainKHR` and runs a one-frame-in-flight loop: acquire → record → submit → present → wait.

### 2.2. Transformation chain

Every scene node carries a local pose matrix; `GlobalPose` is the product of all ancestor poses. With the model matrix $M$ (the accumulated pose of the cube), the view matrix $V$ (the inverse of the camera's global pose, `TVkCamera.ViewMat`), and the projection $P$, a vertex $p$ reaches clip space as

```math
p_{clip} = P \, V \, M \, p \tag{1}
```

The vertex shader receives the two products it needs as push constants (`TVkPush3D`): `ProjViewPose` $= P V M$ applied to positions, and `Pose` $= M$ alone, whose upper-left $3 \times 3$ block transforms the normals (isotropic scaling is assumed):

```math
n_{world} = M_{3 \times 3} \, n \tag{2}
```

### 2.3. Projection under Vulkan conventions

Vulkan's clip space differs from OpenGL's: the framebuffer $y$ axis points **down**, and the normalized depth range is $z \in [0, 1]$ instead of $[-1, +1]$ [1]. The library therefore builds Vulkan-native projection matrices directly (`VkProjPers3D` / `VkProjOrth3D`) rather than converting the OpenGL-style ones from `LUX.D4x4`. For a camera screen of physical size $s_x \times s_y$ placed at focal distance $f$ (`TVkCameraPers3D.FocusZ`), with near / far planes $z_n$, $z_f$:

```math
P_{pers} =
\begin{pmatrix}
\dfrac{2f}{s_x} & 0 & 0 & 0 \\
0 & -\dfrac{2f}{s_y} & 0 & 0 \\
0 & 0 & \dfrac{z_f}{z_n - z_f} & \dfrac{z_f \, z_n}{z_n - z_f} \\
0 & 0 & -1 & 0
\end{pmatrix} \tag{3}
```

The negated second row realizes the Y-down convention, and the third row maps the view-space depth range $[-z_n, -z_f]$ onto $[0, 1]$. The field of view is a derived quantity: assigning `AngleY` moves the focal distance while the screen stays put, $f = \frac{s_y}{2} \cot\frac{\theta_y}{2}$.

The camera's screen aspect ($s_x : s_y$, here $4 : 3$) is independent of the render target's pixel aspect. `VkFitViewport` letterboxes the `VkViewport` so the camera's field lands centered and undistorted inside the target; the bars need no extra drawing because the render pass has already cleared the whole framebuffer to the scene's background color.

### 2.4. Shaders and push constants

The two stages are ordinary GLSL files, compiled at load time by the embedded glslang [5]:

```GLSL
layout( push_constant ) uniform Push { mat4 ProjViewPose; mat4 Pose; } uPush;

layout( location = 0 ) in vec3 aPos;
layout( location = 1 ) in vec3 aNor;
layout( location = 2 ) in vec2 aTex;
```

The 128-byte `TVkPush3D` block is exactly `maxPushConstantsSize`'s guaranteed minimum [1], so the demo needs no descriptor set at all. The fragment shader tints each face by its world-space normal ($C = \frac{N}{2} + \frac{1}{2}$), overlays a $4 \times 4$ checkerboard derived from the texture coordinates, and applies Lambert diffuse from a fixed directional light — so all six faces stay distinguishable as the cube turns.

## 3. Architecture

### 3.1. Class diagram

Actual classes and ownership (`LUX.Vulkan`); arrows `─▶` denote references, indented lines denote ownership:

```
[ Core objects — indentation = ownership; wrapped Vulkan handle on the right ]

・TVulkan
  ┗・TVkSystem              ･･･ VkInstance
     ┗・TVkDevice           ･･･ VkPhysicalDevice
        ┗・TVkContex        ･･･ VkDevice (logical device)
           ┣・TVkQueuer     ･･･ VkQueue ＋ VkCommandPool (submit / present)
           ┣・TVkShader ×2 ･･･ VkShaderModule (GLSL → SPIR-V by glslang)
           ┣・TVkRaster3D   ･･･ VkPipeline ＋ Layout
           ┗・TVkPasser     ･･･ VkRenderPass (color ＋ depth, 1 subpass)

[ References — not owned ]

・TVkRaster3D
  ┗・Stagers                ･･･ references the 2 TVkShader instances

[ Scene graph — owned as a tree; Free releases the whole subtree ]

・TVkScener                  ･･･ root: Contex / Queuer / BackColor, OnChange
  ┣・TVkCube3D              ･･･ TVkShaper3D: TVkVerBuf3D(24)＋TVkIndBuf3D(36)
  ┃  ┗・Raster             ･･･ references TVkRaster3D (inherited, not owned)
  ┗・TVkCameraPers3D        ･･･ TVkCamera3D: ProjMat/ViewMat, OnChange→OnScene

[ Presentation — TVkViewer = TFrame on the form ]

・TVkViewer
  ┣・_Passer :TVkPasser     ･･･ ColorLast = PRESENT_SRC_KHR
  ┣・Direct = True
  ┃  ┗・_Window :HWND (WS_CHILD)
  ┃     ┗・TVkSwaper       ･･･ VkSurfaceKHR＋VkSwapchainKHR＋depth attachment
  ┗・Direct = False
     ┗・TVkRender           ･･･ offscreen TBitmap, drawn by Canvas.DrawBitmap
```

Data flow of one frame:

```
[ One frame — nesting shows what happens inside the step above ]

・_Cube.LocalPose := …                 ･･･ (the only line the demo writes)
  ┗・Changed climbs the tree
     ┗・TVkScener.OnChange
        ┗・TVkCamera.OnScene
           ┗・TVkViewer.Render
              ┣・TVkSwaper.BeginFrame  ･･･ acquire image
              ┣・VkRecordScene
              ┃  ┣・begin render pass ･･･ clear color ＋ depth
              ┃  ┣・letterbox viewport
              ┃  ┗・TVkCamera.Render  ･･･ ProjView := ProjMat × ViewMat
              ┃     ┗・TVkScener.Draw ･･･ accumulate poses (TVkDrawer state)
              ┃        ┗・TVkCube3D.DrawMain
              ┃           ┣・BindRaster
              ┃           ┣・vkCmdPushConstants
              ┃           ┗・vkCmdDrawIndexed
              ┗・TVkSwaper.EndFrame
                 ┣・submit
                 ┣・present
                 ┗・wait
```

### 3.2. Scene graph and change propagation

The scene is a tree of `TVkObject` nodes (`TTreeKnot`); `TVkScener` is a node that refuses any parent, so the root is found by simply walking up. `Create( Parent )` joins the tree, `Free` releases a whole subtree, and cycles are rejected by the tree layer. A pipeline (`Raster`) set on any node is inherited by its descendants; nodes reference it but never own it.

Redrawing is **not** driven by the timer. Any mutation — pose, size, visibility, insertion or removal — travels up the tree as `Changed`, leaves the scene through `TVkScener.OnChange` (a multicast delegate), is forwarded by the subscribed camera as `OnScene`, and lands on the viewer, which re-records and re-presents the frame. The whole animation is therefore one assignment per tick:

```Delphi
procedure TForm1.Timer1Timer(Sender: TObject);
begin
     _Spin := _Spin + 0.012;

     _Cube.LocalPose := TSingleM4.RotateY( _Spin ) * TSingleM4.RotateX( _Spin * 0.6 );
end;
```

### 3.3. Viewer: embedding a swapchain in FireMonkey

FireMonkey paints a whole form into a single `HWND`, so there is no natural seam for Vulkan to present into. `TVkViewer` (a `TFrame`) therefore creates a bare **`WS_CHILD` window** — not a `TForm` — over its own rectangle and presents into it through `TVkSwaper`. Being a child of the form's `HWND`, it is clipped by the form and follows it through moves, minimization and destruction; no z-order or activation bookkeeping is needed. The child window returns `HTTRANSPARENT` from `WM_NCHITTEST`, so it swallows no input: the mouse reaches FireMonkey as usual, and the orbit / zoom handlers are plain `OnMouseDown` / `OnMouseMove` / `OnMouseWheel` events on the frame. It also ignores `WM_ERASEBKGND` and validates `WM_PAINT` without drawing, since Vulkan owns every pixel.

With `Direct := False` the viewer switches to `TVkRender`, which renders offscreen and blits a `TBitmap` in `Paint`. That path obeys FireMonkey's paint order — controls can be layered on top — at the cost of a GPU → CPU → GPU round trip per frame. `TVkSwaper` runs one frame in flight and treats `VK_ERROR_OUT_OF_DATE_KHR` / `VK_SUBOPTIMAL_KHR` as rebuild signals; while minimized, `Ready` turns `False` and frames are skipped entirely.

### 3.4. File tree

```
・Vulkan3DCG/
  ┣・Vulkan3DCG.dpr / .dproj ･･･ FireMonkey application project (Win32/Win64)
  ┣・Main.pas / Main.fmx     ･･･ TForm1: construction ＋ orbit-camera input
  ┣・_DATA/
  ┃  ┣・Shader.vert         ･･･ vertex stage: push constants, aPos/aNor/aTex
  ┃  ┗・Shader.frag         ･･･ fragment stage: normal tint＋checker＋diffuse
  ┗・_LIBRARY/LUXOPHIA/
     ┣・LUX/                 ･･･ base library: TSingle3D, TSingleM4, tree/list
     ┗・LUX.Vulkan/          ･･･ Vulkan wrapper library (git subtree)
        ┣・Core/             ･･･ Contex / Queuer / Shader / Passer / Raster …
        ┣・Graphics/         ･･･ scene graph, Swaper, Render, Viewer
        ┣・Glslang/ ＋ _DLL/ ･･･ glslang bindings ＋ glslang.dll [5]
        ┗・Vulkan/           ･･･ Vulkan API translation (vulkan_core, …)
```

## 4. Usage

| Control | Action |
|---|---|
| Left-drag on the view | Orbit the camera around the origin (polar coordinates, pitch clamped to ±1.5 rad) |
| Mouse wheel | Dolly: distance × 1.1 per notch, clamped to [1.2, 40] |
| **Direct** checkbox | On: present via the child-window swapchain ／ Off: offscreen `TVkRender` → `TBitmap` |
| **Rotate ( TTimer )** checkbox | Start / stop the cube's spin |

The memo on the left reports the selected device and Vulkan version, the queue family and enabled extensions, the shader compile results with SPIR-V sizes, the pipeline build status, and the camera's screen / focal length / field of view.

## 5. Building

* **IDE**: RAD Studio / Delphi (FireMonkey project, `ProjectVersion 20.4`).
* **Platforms**: Windows 32-bit / 64-bit (`Win32` / `Win64` targets in `Vulkan3DCG.dproj`).
* **Runtime requirement**: a GPU driver providing the Vulkan runtime (`vulkan-1.dll`). The **Vulkan SDK is not required** — the API translation lives in `_LIBRARY/LUXOPHIA/LUX.Vulkan/Vulkan/`, and the loader is bound at runtime; without Vulkan the app starts and reports "Vulkan is not available."
* **Shader compilation**: none at build time. The GLSL sources in `_DATA/` are compiled to SPIR-V on startup by `glslang.dll` [5], which a post-build event copies from `_LIBRARY/LUXOPHIA/LUX.Vulkan/_DLL/$(Platform)/` next to the executable. Editing a shader only requires restarting the app.

Open `Vulkan3DCG.dproj`, select a platform, and run.

## 6. References

1. Khronos Group, [*Vulkan Specification*](https://registry.khronos.org/vulkan/specs/latest/html/)
2. Khronos Group, [*Vulkan Guide*](https://docs.vulkan.org/guide/latest/index.html)
3. Khronos Group, [*Vulkan Registry*](https://registry.khronos.org/vulkan/)
4. Khronos Group, [*Vulkan-Headers*](https://github.com/KhronosGroup/Vulkan-Headers)
5. Khronos Group, [*glslang*](https://github.com/KhronosGroup/glslang)

## 💖 [Embarcadero](https://www.embarcadero.com/) [**Delphi**](https://www.embarcadero.com/products/delphi)
Integrated Development Environment (IDE) for Creating Native Cross-Platform Apps.
### Free Download: [**Delphi** Community Edition](https://www.embarcadero.com/products/delphi/starter)
