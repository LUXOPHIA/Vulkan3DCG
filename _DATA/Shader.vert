#version 450

//////////////////////////////////////////////////////////// 押込定数（TVkPush3D）

layout( push_constant ) uniform Push
{
     mat4 ProjViewPose;  // 射影 × 視野 × 姿勢
     mat4 Pose;          // 姿勢のみ
} uPush;

//////////////////////////////////////////////////////////// 頂点属性（TVkVertex3D）

layout( location = 0 ) in vec3 aPos;
layout( location = 1 ) in vec3 aNor;
layout( location = 2 ) in vec2 aTex;

////////////////////////////////////////////////////////////

layout( location = 0 ) out vec3 vNor;
layout( location = 1 ) out vec2 vTex;

////////////////////////////////////////////////////////////

void main()
{
     gl_Position = uPush.ProjViewPose * vec4( aPos, 1.0 );

     vNor = mat3( uPush.Pose ) * aNor;  // 等方スケールを前提とした法線変換
     vTex = aTex;
}
