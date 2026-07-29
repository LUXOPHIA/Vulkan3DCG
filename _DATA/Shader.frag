#version 450

layout( location = 0 ) in vec3 vNor;
layout( location = 1 ) in vec2 vTex;

layout( location = 0 ) out vec4 oCol;

////////////////////////////////////////////////////////////

const vec3 LigD = normalize( vec3( -0.4, -1.0, -0.6 ) );  // 平行光の進む向き

////////////////////////////////////////////////////////////

void main()
{
     vec3 N = normalize( vNor );

     vec3 C = N * 0.5 + 0.5;  // 面の向きで色分けする（6 面が別の色になる）

     vec2  T = floor( vTex * 4.0 );
     float K = mod( T.x + T.y, 2.0 ) * 0.15 + 0.85;  // 市松模様でテクスチャ座標を示す

     float D = max( dot( N, -LigD ), 0.0 );  // 拡散反射

     oCol = vec4( C * K * ( 0.25 + 0.90 * D ), 1.0 );
}
